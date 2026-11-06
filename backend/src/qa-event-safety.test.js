import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {createEventNotifications} from './event-notifications.js';

const source = fs.readFileSync(new URL('./server.js', import.meta.url), 'utf8');
function route(method, path, dependencies) {
  const start = source.indexOf(`app.${method}('${path}', `);
  assert.notEqual(start, -1);
  const bodyStart = source.indexOf('async (req, res, next) => {', start);
  const end = source.indexOf('\n});', bodyStart);
  return vm.runInNewContext(`(${source.slice(bodyStart, end + 2)})`, dependencies);
}
function response() {
  return {code: 200, body: null, status(code) {this.code = code; return this;},
    json(body) {this.body = body; return this;}, end() {return this;}};
}
function fixture() {
  const db = new DatabaseSync(':memory:');
  const now = new Date('2026-10-27T03:00:00Z');
  db.function('UTC_TIMESTAMP', () => now.toISOString());
  db.function('CONVERT_TZ', (value, from, to) => {
    const offset = zone => (zone.startsWith('-') ? -1 : 1) *
      (Number(zone.slice(1, 3)) * 60 + Number(zone.slice(4, 6)));
    const date = new Date(/[zZ]|[+]\d\d:\d\d$/.test(value) ? value : `${value.replace(' ', 'T')}Z`);
    return new Date(date.getTime() + (offset(to) - offset(from)) * 60000).toISOString().slice(0, 19);
  });
  db.function('DATE_FORMAT', (value, _format) => value == null ? null : `${value.replace(' ', 'T').replace(/Z$/, '')}Z`);
  db.function('DATEDIFF', (left, right) => Math.round((Date.parse(left) - Date.parse(right)) / 86400000));
  db.exec(`CREATE TABLE users(id INTEGER, nickname TEXT, public_code TEXT, avatar_url TEXT, session_token TEXT, account_status TEXT);
    CREATE TABLE circles(id INTEGER, owner_user_id INTEGER);
    CREATE TABLE circle_members(circle_id INTEGER, user_id INTEGER, created_at TEXT);
    CREATE TABLE user_blocks(blocker_user_id INTEGER, blocked_user_id INTEGER);
    CREATE TABLE event_meeting_points(id INTEGER, event_id INTEGER, circle_id INTEGER, creator_user_id INTEGER,
      latitude REAL, longitude REAL, description TEXT, meet_at TEXT, created_at TEXT);
    CREATE TABLE device_push_tokens(user_id INTEGER, token TEXT);
    CREATE TABLE events(id INTEGER, start_date TEXT);
    CREATE TABLE event_recognition_requests(id INTEGER, event_id INTEGER, day_index INTEGER,
      requester_user_id INTEGER, target_user_id INTEGER, status TEXT, response_message TEXT,
      created_at TEXT, expires_at TEXT, responded_at TEXT);
    INSERT INTO users VALUES (1,'owner','one','a','s1','active'),(2,'peer','two','b','s2','active'),
      (3,'outsider','three','c','s3','active');
    ALTER TABLE circles ADD COLUMN name TEXT;
    INSERT INTO circles VALUES (1,1,'circle');
    INSERT INTO circle_members VALUES (1,1,'a'),(1,2,'b');
    INSERT INTO event_meeting_points VALUES (1,10,1,2,25.1,121.2,'meet','2026-10-27 04:00:00','2026-10-27 03:00:00'),
      (2,10,1,2,25.2,121.3,'old','2026-10-26 04:00:00','2026-10-26 03:00:00');
    INSERT INTO device_push_tokens VALUES (1,'owner-token'),(2,'peer-token'),(3,'outsider-token');`);
  return db;
}

for (const [blocker, blocked] of [[1, 2], [2, 1]]) {
  test(`meetup read excludes either-direction block ${blocker}->${blocked}`, async () => {
    const db = fixture();
    try {
      const pool = {execute: async (sql, params) => [db.prepare(sql).all(...params)]};
      const read = route('get', '/api/events/:eventId/meetups', {pool});
      const req = {userId: 1, params: {eventId: 10}};
      let res = response();
      await read(req, res, error => {throw error;});
      assert.deepEqual(res.body.map(row => row.id), [1]);
      assert.equal(res.body[0].meetAt, '2026-10-27T04:00:00Z');
      db.prepare('INSERT INTO user_blocks VALUES (?,?)').run(blocker, blocked);
      res = response();
      await read(req, res, error => {throw error;});
      assert.deepEqual(res.body, []);
    } finally {db.close();}
  });
}

test('circle owner keeps removal target without gaining blocked profile data', () => {
  const db = fixture();
  try {
    const block = source.split("app.get('/api/circles',")[1].split("app.post('/api/circles',")[0];
    const query = [...block.matchAll(/`(SELECT[\s\S]*?)`/g)][1][1].replace('${placeholders}', '?');
    for (const [blocker, blocked] of [[1, 2], [2, 1]]) {
      db.exec('DELETE FROM user_blocks');
      db.prepare('INSERT INTO user_blocks VALUES (?,?)').run(blocker, blocked);
      const rows = db.prepare(query).all(1, 1, 1, 1, 1);
      const hidden = rows.find(row => row.userId === 2);
      assert.ok(hidden);
      assert.equal(hidden.isBlocked, 1);
      assert.equal(hidden.publicCode, '');
      assert.equal(hidden.avatarUrl, '');
      assert.equal(hidden.nickname, '已隱藏的成員');
      const peerRows = db.prepare(query).all(2, 2, 1, 2, 2);
      assert.deepEqual(peerRows.map(row => row.userId), [2]);
    }
  } finally {db.close();}
});

test('successful meetup insertion triggers notification only after the insert', async () => {
  const calls = [];
  const pool = {execute: async sql => {
    calls.push(sql.startsWith('INSERT') ? 'insert' : 'membership');
    return sql.startsWith('INSERT') ? [{insertId: 42}] : [[{circleId: 1}]];
  }};
  const eventNotifications = {meetupCreated: async payload => {
    calls.push('notify'); assert.equal(payload.meetupId, 42); return {sent: 1, failed: 0};
  }};
  const create = route('post', '/api/events/:eventId/meetups', {
    pool, eventNotifications, normalizeDateTimeForSql: value => value,
  });
  const res = response();
  await create({userId: 1, params: {eventId: 10}, body: {circleId: 1}}, res, error => {throw error;});
  assert.deepEqual(calls, ['membership', 'insert', 'notify']);
  assert.equal(res.code, 201);
  assert.equal(res.body.push.queued, true);
});

test('slow push transport cannot delay committed meetup or recognition responses', async () => {
  let finishDelivery;
  const delivery = new Promise(resolve => {finishDelivery = resolve;});
  let inserts = 0;
  const pool = {execute: async sql => {
    if (sql.startsWith('INSERT')) {inserts++; return [{insertId: 42}];}
    if (sql.startsWith('UPDATE')) return [{affectedRows: 1}];
    return [[{circleId: 1}]];
  }};
  const eventNotifications = {meetupCreated: () => delivery, recognitionResponded: () => delivery};
  const create = route('post', '/api/events/:eventId/meetups', {
    pool, eventNotifications, normalizeDateTimeForSql: value => value,
  });
  const created = response();
  await create({userId: 1, params: {eventId: 10}, body: {circleId: 1}}, created, error => {throw error;});
  assert.equal(created.code, 201);
  assert.equal(created.body.id, 42);
  assert.equal(inserts, 1);
  const respond = route('post', '/api/recognitions/:requestId/respond', {pool, eventNotifications});
  const responded = response();
  await respond({userId: 2, params: {requestId: 4}, body: {status: 'accepted'}}, responded, error => {throw error;});
  assert.equal(responded.code, 204);
  finishDelivery({sent: 1, failed: 0});
  await delivery;
});

test('recognition response notifies once, rejected repeat does not notify', async () => {
  let changed = true;
  let notifications = 0;
  const handler = route('post', '/api/recognitions/:requestId/respond', {
    pool: {execute: async () => [{affectedRows: changed ? 1 : 0}]},
    eventNotifications: {recognitionResponded: async payload => {
      notifications++; assert.equal(payload.status, 'accepted');
    }},
  });
  const req = {userId: 2, params: {requestId: 4}, body: {status: 'accepted'}};
  const first = response();
  await handler(req, first, error => {throw error;});
  assert.equal(first.code, 204);
  changed = false;
  const second = response();
  await handler(req, second, error => {throw error;});
  assert.equal(second.code, 404);
  assert.equal(notifications, 1);
});

test('meetup notification recipients exclude creator, outsiders, and both block directions', async () => {
  const db = fixture();
  try {
    const sent = [];
    const pool = {execute: async (sql, params) => {
      if (sql.includes('DATEDIFF')) return [[{creatorName: 'owner', dayIndex: 1}]];
      return [db.prepare(sql).all(...params)];
    }};
    const notifications = createEventNotifications(pool, {
      sendMeetupPush: async payload => {sent.push(payload); return {successCount: payload.tokens.length, failureCount: 0, invalidTokens: []};},
    });
    const payload = {meetupId: 4, eventId: 10, circleId: 1, creatorUserId: 1};
    assert.equal((await notifications.meetupCreated(payload)).sent, 1);
    assert.deepEqual(sent.at(-1).tokens, ['peer-token']);
    for (const [blocker, blocked] of [[1, 2], [2, 1]]) {
      db.exec('DELETE FROM user_blocks');
      db.prepare('INSERT INTO user_blocks VALUES (?,?)').run(blocker, blocked);
      assert.equal((await notifications.meetupCreated(payload)).sent, 0);
      assert.deepEqual(sent.at(-1).tokens, []);
    }
  } finally {db.close();}
});

test('notification failure does not invalidate a successful domain operation', async () => {
  const notifications = createEventNotifications({execute: async () => {throw new Error('offline');}}, {});
  assert.equal((await notifications.meetupCreated({})).error, 'push_send_failed');
  assert.equal((await notifications.recognitionResponded({})).error, 'push_send_failed');
});

test('recognition read includes only the current Taipei event day', async () => {
  const db = fixture();
  try {
    db.exec(`INSERT INTO events VALUES (10,'2026-10-26');
      INSERT INTO event_recognition_requests VALUES
      (1,10,1,1,2,'accepted','old','2026-10-26 04:00:00','2026-10-26 04:05:00','2026-10-26 04:01:00'),
      (2,10,2,1,2,'accepted','today','2026-10-27 03:00:00','2026-10-27 03:05:00','2026-10-27 03:01:00'),
      (3,10,3,1,2,'accepted','future','2026-10-28 03:00:00','2026-10-28 03:05:00','2026-10-28 03:01:00');`);
    const handler = route('get', '/api/events/:eventId/recognitions', {
      pool: {execute: async (sql, params) => [db.prepare(sql).all(...params)]},
    });
    const res = response();
    await handler({userId: 1, params: {eventId: 10}}, res, error => {throw error;});
    assert.deepEqual(res.body.map(row => row.id), [2]);
    assert.equal(res.body[0].dayIndex, 2);
    assert.equal(res.body[0].expiresAt, '2026-10-27T03:05:00Z');
  } finally {db.close();}
});

test('recognition reply only reaches the active requester and respects both block directions', async () => {
  const db = fixture();
  try {
    db.exec(`INSERT INTO event_recognition_requests VALUES
      (4,10,2,1,2,'accepted','快來','2026-10-27 03:00:00','2026-10-27 03:05:00','2026-10-27 03:01:00');`);
    const sent = [];
    const notifications = createEventNotifications({
      execute: async (sql, params) => [db.prepare(sql).all(...params)],
    }, {
      sendRecognitionReplyPush: async payload => {
        sent.push(payload);
        return {successCount: payload.tokens.length, failureCount: 0, invalidTokens: []};
      },
    });
    const payload = {requestId: 4, targetUserId: 2, status: 'accepted'};
    assert.equal((await notifications.recognitionResponded(payload)).sent, 1);
    assert.deepEqual(sent.at(-1).tokens, ['owner-token']);
    assert.equal(sent.at(-1).dayIndex, 2);
    assert.equal(sent.at(-1).responderName, 'peer');
    for (const [blocker, blocked] of [[1, 2], [2, 1]]) {
      db.exec('DELETE FROM user_blocks');
      db.prepare('INSERT INTO user_blocks VALUES (?,?)').run(blocker, blocked);
      assert.equal((await notifications.recognitionResponded(payload)).sent, 0);
      assert.deepEqual(sent.at(-1).tokens, []);
    }
    db.exec("DELETE FROM user_blocks; UPDATE users SET session_token=NULL WHERE id=1;");
    assert.equal((await notifications.recognitionResponded(payload)).sent, 0);
    assert.deepEqual(sent.at(-1).tokens, []);
  } finally {db.close();}
});
