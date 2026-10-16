import crypto from 'node:crypto';
import { importEvents } from '../scripts/scrape-events.js';
import { sourceSnapshotsTableSql } from '../scripts/event-snapshot.js';

export const eventSyncJobsTableSql = `CREATE TABLE IF NOT EXISTS event_sync_jobs (
  id VARCHAR(36) PRIMARY KEY,
  scheduled_date DATE NULL,
  status ENUM('running','success','partial','failure') NOT NULL,
  attempts INT UNSIGNED NOT NULL DEFAULT 1,
  sources_json JSON NULL,
  error_code VARCHAR(80) NULL,
  started_at DATETIME NOT NULL,
  finished_at DATETIME NULL,
  UNIQUE KEY uniq_event_sync_daily (scheduled_date),
  KEY idx_event_sync_status (status, started_at)
)`;

export function dailySyncDate(now, timeZone = 'Asia/Taipei') {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', hourCycle: 'h23',
  }).formatToParts(now);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return Number(values.hour) >= 12 ? `${values.year}-${values.month}-${values.day}` : null;
}

function formatJob(row) {
  if (!row) return null;
  const sources = typeof row.sources_json === 'string' ? JSON.parse(row.sources_json) : row.sources_json ?? [];
  return {id: row.id, status: row.status, attempts: row.attempts, sources,
    errorCode: row.error_code ?? '', startedAt: row.started_at, finishedAt: row.finished_at};
}

export function createEventSyncService(pool, {
  importer = importEvents, now = () => new Date(), timeZone = 'Asia/Taipei',
  retrySeconds = 1800, maxAttempts = 3, notifyFailure = (report) => console.error('[event-sync] attention required', report),
} = {}) {
  const lockName = 'coscircle-event-sync';
  const readJob = async (id) => {
    const [rows] = await pool.execute('SELECT * FROM event_sync_jobs WHERE id = ?', [id]);
    return formatJob(rows[0]);
  };
  const release = async (connection) => {
    try {
      await connection.execute('SELECT RELEASE_LOCK(?)', [lockName]);
      connection.release();
    } catch { connection.destroy(); }
  };
  const executeJob = async (id, connection) => {
    const sources = [];
    try {
      await importer(pool, {}, async (report, db = pool) => {
        await db.execute(`INSERT INTO source_sync_runs
          (source_key,source_url,status,imported_count,error_code,error_message) VALUES (?,?,?,?,?,?)`,
        [report.sourceKey, report.sourceUrl, report.status, report.importedCount,
          report.errorCode ?? null, report.errorMessage ?? null]);
        const saved = {...report, createdAt: now().toISOString()};
        await db.execute('UPDATE event_sync_jobs SET sources_json=? WHERE id=?',
          [JSON.stringify([...sources, saved]), id]);
        // The importer publishes this in-memory state only after commit.
        return () => sources.push(saved);
      });
      const status = sources.some((source) => source.status === 'failure') ? 'partial' : 'success';
      await pool.execute(`UPDATE event_sync_jobs SET status=?, sources_json=?, finished_at=UTC_TIMESTAMP()
        WHERE id=?`, [status, JSON.stringify(sources), id]);
      if (status === 'partial') notifyFailure({id, status, sources});
    } catch (error) {
      const code = String(error.code ?? 'sync_failed').slice(0, 80);
      await pool.execute(`UPDATE event_sync_jobs SET status='failure', sources_json=?, error_code=?,
        finished_at=UTC_TIMESTAMP() WHERE id=?`, [JSON.stringify(sources), code, id]);
      notifyFailure({id, status: 'failure', errorCode: code});
    } finally { await release(connection); }
  };
  const start = async (date = null) => {
    const connection = await pool.getConnection();
    let ownsLock = false;
    let handedOff = false;
    try {
      const [[lock]] = await connection.execute('SELECT GET_LOCK(?, 0) AS acquired', [lockName]);
      ownsLock = lock.acquired === 1;
      if (!ownsLock) {
        const [active] = await pool.execute("SELECT * FROM event_sync_jobs WHERE status='running' ORDER BY started_at DESC LIMIT 1");
        if (!active.length) throw Object.assign(new Error('event_sync_busy'), {code: 'event_sync_busy'});
        return {...formatJob(active[0]), reused: true};
      }
      // Acquiring the cross-process lock proves no previous worker still owns it.
      await connection.execute(`UPDATE event_sync_jobs SET status='failure', error_code='sync_interrupted',
        finished_at=UTC_TIMESTAMP() WHERE status='running'`);
      let job;
      if (!date) {
        const [recent] = await connection.execute(`SELECT *, TIMESTAMPDIFF(SECOND, finished_at, UTC_TIMESTAMP()) AS recent_age
          FROM event_sync_jobs WHERE status IN ('success','partial') ORDER BY finished_at DESC LIMIT 1`);
        if (recent[0] && recent[0].recent_age < 60) return {...formatJob(recent[0]), reused: true};
      }
      if (date) {
        const [rows] = await connection.execute(`SELECT *,
          TIMESTAMPDIFF(SECOND, finished_at, UTC_TIMESTAMP()) AS retry_age
          FROM event_sync_jobs WHERE scheduled_date=?`, [date]);
        job = rows[0];
        if (job && (job.status === 'success' || job.attempts >= maxAttempts || job.retry_age < retrySeconds)) {
          return {...formatJob(job), reused: true};
        }
      }
      const id = job?.id ?? crypto.randomUUID();
      if (job) {
        await connection.execute(`UPDATE event_sync_jobs SET status='running', attempts=attempts+1,
          sources_json=NULL, error_code=NULL, started_at=UTC_TIMESTAMP(), finished_at=NULL WHERE id=?`, [id]);
      } else {
        await connection.execute(`INSERT INTO event_sync_jobs (id,scheduled_date,status,started_at)
          VALUES (?,?,'running',UTC_TIMESTAMP())`, [id, date]);
      }
      handedOff = true;
      void executeJob(id, connection).catch((error) => notifyFailure({id, errorCode: error.code ?? 'sync_job_storage_failed'}));
      return {id, status: 'running', attempts: (job?.attempts ?? 0) + 1, sources: [], reused: false};
    } finally {
      if (!handedOff) {
        if (ownsLock) await release(connection);
        else connection.release();
      }
    }
  };
  return {
    initialize: async () => {
      await pool.execute(eventSyncJobsTableSql);
      await pool.execute(sourceSnapshotsTableSql);
      const connection = await pool.getConnection();
      let ownsLock = false;
      try {
        const [[lock]] = await connection.execute('SELECT GET_LOCK(?, 0) AS acquired', [lockName]);
        ownsLock = lock.acquired === 1;
        if (ownsLock) await connection.execute(`UPDATE event_sync_jobs SET status='failure',
          error_code='sync_interrupted', finished_at=UTC_TIMESTAMP() WHERE status='running'`);
      } finally {
        if (ownsLock) await release(connection);
        else connection.release();
      }
    },
    startManual: () => start(),
    readJob,
    readLatest: async () => {
      const [rows] = await pool.execute('SELECT * FROM event_sync_jobs ORDER BY started_at DESC LIMIT 1');
      return formatJob(rows[0]);
    },
    runDueDaily: async () => {
      const date = dailySyncDate(now(), timeZone);
      return date ? start(date) : null;
    },
  };
}
