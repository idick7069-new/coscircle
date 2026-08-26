import 'dotenv/config';
import { pathToFileURL } from 'url';
import { createPool } from '../src/db.js';
import { cleanDoujinEventName, doujinSourceKey } from './scrape-events.js';

const apply = process.argv.includes('--apply');

if (isCliEntry()) {
  const pool = createPool();
  try {
    const summary = await cleanDoujinEvents(pool, { apply });
    console.log(JSON.stringify(summary, null, 2));
  } finally {
    await pool.end();
  }
}

export async function cleanDoujinEvents(pool, { apply = false } = {}) {
  const [rows] = await pool.query(
    `SELECT id,
            source_key AS sourceKey,
            source_type AS sourceType,
            source_name AS sourceName,
            source_url AS sourceUrl,
            name,
            DATE_FORMAT(start_date, '%Y-%m-%d') AS startDate
       FROM events
      WHERE source_key LIKE 'doujin-%'
         OR source_type = 1
         OR source_name = '同人誌中心'
      ORDER BY start_date ASC, id ASC`,
  );

  const groups = new Map();
  for (const row of rows) {
    const cleanName = cleanDoujinEventName(row.name);
    if (!cleanName) continue;
    const cleanSourceKey = doujinSourceKey(cleanName, row.startDate, row.sourceUrl);
    const item = {
      id: Number(row.id),
      sourceKey: row.sourceKey,
      name: row.name,
      startDate: row.startDate,
      cleanName,
      cleanSourceKey,
      dirtyName: row.name !== cleanName,
      dirtySourceKey: row.sourceKey !== cleanSourceKey,
    };
    const group = groups.get(cleanSourceKey) ?? [];
    group.push(item);
    groups.set(cleanSourceKey, group);
  }

  const duplicateGroups = [...groups.values()].filter((group) => group.length > 1);
  const dirtySingles = [...groups.values()]
    .filter((group) => group.length === 1)
    .map((group) => group[0])
    .filter((event) => event.dirtyName || event.dirtySourceKey);

  const summary = {
    mode: apply ? 'apply' : 'dry-run',
    scanned: rows.length,
    duplicateGroups: duplicateGroups.length,
    duplicatesRemoved: 0,
    renamed: 0,
    sourceKeysUpdated: 0,
    groups: duplicateGroups.map((group) => describeGroup(group)),
    dirtySingles: dirtySingles.map((event) => ({
      id: event.id,
      from: event.name,
      to: event.cleanName,
      sourceKey: event.cleanSourceKey,
    })),
  };

  if (!apply) return summary;

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();

    for (const group of duplicateGroups) {
      const canonical = chooseCanonical(group);
      const duplicates = group.filter((event) => event.id !== canonical.id);

      for (const duplicate of duplicates) {
        await moveEventRelations(connection, duplicate.id, canonical.id);
        await connection.execute('DELETE FROM events WHERE id = ?', [duplicate.id]);
        summary.duplicatesRemoved += 1;
      }

      const changed = await updateCanonicalEvent(connection, canonical);
      if (changed.renamed) summary.renamed += 1;
      if (changed.sourceKeyUpdated) summary.sourceKeysUpdated += 1;
    }

    for (const event of dirtySingles) {
      const changed = await updateCanonicalEvent(connection, event);
      if (changed.renamed) summary.renamed += 1;
      if (changed.sourceKeyUpdated) summary.sourceKeysUpdated += 1;
    }

    await connection.commit();
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }

  return summary;
}

async function moveEventRelations(connection, fromEventId, toEventId) {
  await connection.execute(
    `INSERT IGNORE INTO event_bookings
      (event_id, user_id, day_index, role, work_id, character_name,
       outfit_image_url, interaction_tags, available_time, presence_status,
       message, created_at, updated_at)
     SELECT ?, user_id, day_index, role, work_id, character_name,
            outfit_image_url, interaction_tags, available_time, presence_status,
            message, created_at, updated_at
       FROM event_bookings
      WHERE event_id = ?`,
    [toEventId, fromEventId],
  );
  await connection.execute('DELETE FROM event_bookings WHERE event_id = ?', [
    fromEventId,
  ]);

  await connection.execute(
    `INSERT IGNORE INTO shared_locations
      (event_id, day_index, user_id, latitude, longitude, visibility, shared_at, expires_at)
     SELECT ?, day_index, user_id, latitude, longitude, visibility, shared_at, expires_at
       FROM shared_locations
      WHERE event_id = ?`,
    [toEventId, fromEventId],
  );
  await connection.execute('DELETE FROM shared_locations WHERE event_id = ?', [
    fromEventId,
  ]);

  await connection.execute(
    'UPDATE event_meeting_points SET event_id = ? WHERE event_id = ?',
    [toEventId, fromEventId],
  );
  await connection.execute(
    'UPDATE event_recognition_requests SET event_id = ? WHERE event_id = ?',
    [toEventId, fromEventId],
  );
}

async function updateCanonicalEvent(connection, event) {
  const renamed = event.name !== event.cleanName;
  const sourceKeyUpdated = event.sourceKey !== event.cleanSourceKey;
  if (!renamed && !sourceKeyUpdated) {
    return { renamed: false, sourceKeyUpdated: false };
  }

  await connection.execute(
    `UPDATE events
        SET name = ?,
            source_key = ?
      WHERE id = ?`,
    [event.cleanName, event.cleanSourceKey, event.id],
  );
  return { renamed, sourceKeyUpdated };
}

function chooseCanonical(group) {
  return [...group].sort((left, right) => {
    const leftClean = Number(!left.dirtyName && !left.dirtySourceKey);
    const rightClean = Number(!right.dirtyName && !right.dirtySourceKey);
    if (leftClean !== rightClean) return rightClean - leftClean;

    const leftNameClean = Number(!left.dirtyName);
    const rightNameClean = Number(!right.dirtyName);
    if (leftNameClean !== rightNameClean) return rightNameClean - leftNameClean;

    return left.id - right.id;
  })[0];
}

function describeGroup(group) {
  const canonical = chooseCanonical(group);
  return {
    cleanName: canonical.cleanName,
    sourceKey: canonical.cleanSourceKey,
    keepId: canonical.id,
    duplicateIds: group
      .filter((event) => event.id !== canonical.id)
      .map((event) => event.id),
    names: group.map((event) => ({ id: event.id, name: event.name })),
  };
}

export function isCliEntry() {
  return process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
}
