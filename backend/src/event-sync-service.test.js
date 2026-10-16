import assert from 'node:assert/strict';
import test from 'node:test';
import {createEventSyncService, dailySyncDate} from './event-sync-service.js';

function memoryPool(clock) {
  const jobs = new Map();
  let owner = null;
  const execute = async (sql, params = [], connection = null) => {
    if (sql.includes('GET_LOCK')) {
      if (owner) return [[{acquired: 0}]];
      owner = connection;
      return [[{acquired: 1}]];
    }
    if (sql.includes('RELEASE_LOCK')) {if (owner === connection) owner = null;return [[{released: 1}]];}
    if (sql.startsWith('CREATE TABLE')) return [[]];
    if (sql.startsWith('SELECT')) {
      let rows = [...jobs.values()];
      if (sql.includes('scheduled_date=?')) rows = rows.filter((row) => row.scheduled_date === params[0]);
      else if (sql.includes('WHERE id = ?')) rows = rows.filter((row) => row.id === params[0]);
      else if (sql.includes("status='running'")) rows = rows.filter((row) => row.status === 'running');
      else if (sql.includes("status IN ('success','partial')")) rows = rows.filter((row) => ['success','partial'].includes(row.status));
      if (sql.includes('ORDER BY')) rows = rows.reverse().slice(0, 1);
      return [rows.map((row) => ({...row,
        recent_age: row.finished_at ? (clock().getTime() - row.finished_at.getTime()) / 1000 : null,
        retry_age: row.finished_at ? (clock().getTime() - row.finished_at.getTime()) / 1000 : null}))];
    }
    if (sql.startsWith('INSERT INTO event_sync_jobs')) {
      jobs.set(params[0], {id: params[0], scheduled_date: params[1], status: 'running', attempts: 1, started_at: clock(), finished_at: null});
    } else if (sql.includes("WHERE status='running'")) {
      for (const row of jobs.values()) if (row.status === 'running') Object.assign(row, {status: 'failure', error_code: 'sync_interrupted', finished_at: clock()});
    } else if (sql.includes('attempts=attempts+1')) {
      const row = jobs.get(params[0]);Object.assign(row, {status: 'running', attempts: row.attempts + 1, sources_json: null, error_code: null, finished_at: null});
    } else if (sql.includes('SET status=?')) {
      Object.assign(jobs.get(params[2]), {status: params[0], sources_json: params[1], finished_at: clock()});
    } else if (sql.includes("SET status='failure', sources_json=?")) {
      Object.assign(jobs.get(params[2]), {status: 'failure', sources_json: params[0], error_code: params[1], finished_at: clock()});
    } else if (sql.includes('SET sources_json=?')) jobs.get(params[1]).sources_json = params[0];
    else if (!sql.includes('INSERT INTO source_sync_runs')) throw new Error(`Unexpected SQL: ${sql}`);
    return [{affectedRows: 1}];
  };
  return {jobs, execute: (sql, params) => execute(sql, params), getConnection: async () => {
    const connection = {execute: (sql, params) => execute(sql, params, connection), release() {}, destroy() {if (owner === connection) owner = null;}};
    return connection;
  }};
}

async function finished(service, id) {
  for (let index = 0; index < 20; index++) {
    const job = await service.readJob(id);
    if (job.status !== 'running') return job;
    await new Promise(setImmediate);
  }
  throw new Error('Job did not complete');
}

test('Taipei daily date opens at noon and stays due after the exact minute', () => {
  assert.equal(dailySyncDate(new Date('2026-10-06T03:59:59Z')), null);
  assert.equal(dailySyncDate(new Date('2026-10-06T04:00:00Z')), '2026-10-06');
  assert.equal(dailySyncDate(new Date('2026-10-06T12:00:00Z')), '2026-10-06');
});

test('parallel manual requests and another service instance reuse one active job', async () => {
  const now = () => new Date('2026-10-06T05:00:00Z'), pool = memoryPool(now);
  let calls = 0, resolve;
  const gate = new Promise((done) => {resolve = done;});
  const options = {now, importer: async () => {calls++;await gate;}, notifyFailure() {}};
  const first = createEventSyncService(pool, options), second = createEventSyncService(pool, options);
  const job = await first.startManual();
  const reused = await second.startManual();
  assert.equal(job.id, reused.id);
  assert.equal(reused.reused, true);
  assert.equal(calls, 1);
  await second.initialize();
  assert.equal((await first.readJob(job.id)).status, 'running');
  resolve();await finished(first, job.id);
});

test('a late daily run succeeds once and remains deduplicated after restart', async () => {
  const now = () => new Date('2026-10-06T05:00:00Z'), pool = memoryPool(now);
  let calls = 0;
  const options = {now, importer: async () => {calls++;}, notifyFailure() {}};
  const service = createEventSyncService(pool, options);
  const job = await service.runDueDaily();await finished(service, job.id);
  const restarted = createEventSyncService(pool, options);await restarted.initialize();
  assert.equal((await restarted.runDueDaily()).reused, true);
  assert.equal(calls, 1);
});

test('daily failures persist, wait before retry and stop after three attempts', async () => {
  let time = new Date('2026-10-06T05:00:00Z');const now = () => time, pool = memoryPool(now);
  let calls = 0;
  const service = createEventSyncService(pool, {now, importer: async () => {calls++;throw new Error('offline');}, notifyFailure() {}});
  const first = await service.runDueDaily();await finished(service, first.id);
  assert.equal((await service.runDueDaily()).reused, true);
  for (let i = 0; i < 3; i++) {
    time = new Date(time.getTime() + 1800_000);
    const job = await service.runDueDaily();await finished(service, job.id);
  }
  assert.equal(calls, 3);
  assert.equal(pool.jobs.get(first.id).attempts, 3);
});

test('startup recovers interrupted jobs but leaves an active worker untouched', async () => {
  const now = () => new Date('2026-10-06T05:00:00Z'), pool = memoryPool(now);
  pool.jobs.set('old', {id: 'old', status: 'running', attempts: 1, scheduled_date: '2026-10-06', finished_at: null});
  const service = createEventSyncService(pool, {now, notifyFailure() {}});await service.initialize();
  assert.equal((await service.readJob('old')).errorCode, 'sync_interrupted');
});

test('retrying a just-completed manual request reuses the result instead of billing again', async () => {
  let time = new Date('2026-10-06T05:00:00Z');const now = () => time, pool = memoryPool(now);
  let calls = 0;
  const service = createEventSyncService(pool, {now, importer: async () => {calls++;}, notifyFailure() {}});
  const first = await service.startManual();await finished(service, first.id);
  assert.equal((await service.startManual()).id, first.id);
  assert.equal(calls, 1);
  time = new Date(time.getTime() + 61_000);
  const second = await service.startManual();await finished(service, second.id);
  assert.notEqual(second.id, first.id);
  assert.equal(calls, 2);
});
