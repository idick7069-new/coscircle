import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {
  eraseReportPersonalData, listReports as listReportsWithSession, purgeExpiredReportEvidence,
  registerReportAdminRoutes, registerReportRoutes, reviewReport as reviewReportWithSession, submitReport, validateReport,
} from './content-reports.js';

const listReports = (pool, adminId, query = {}) => listReportsWithSession(pool, adminId, query, 'token');
const reviewReport = (pool, adminId, reportId, body) => reviewReportWithSession(pool, adminId, reportId, body, 'token');

function fixture(t) {
  const db = new DatabaseSync(':memory:');
  t.after(() => db.close());
  db.exec(`PRAGMA foreign_keys = ON;
    CREATE TABLE users(id INTEGER PRIMARY KEY, nickname TEXT, bio TEXT, public_code TEXT,
      avatar_url TEXT, other_photo_urls_json TEXT,
      booking_visibility TEXT DEFAULT 'public', is_admin INTEGER DEFAULT 0,
      account_status TEXT DEFAULT 'active', session_token TEXT DEFAULT 'token');
    CREATE TABLE events(id INTEGER PRIMARY KEY);
    CREATE TABLE circles(id INTEGER PRIMARY KEY, owner_user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
      name TEXT, description TEXT, invite_code TEXT, invite_url TEXT);
    CREATE TABLE circle_members(circle_id INTEGER REFERENCES circles(id) ON DELETE CASCADE, user_id INTEGER);
    CREATE TABLE user_blocks(blocker_user_id INTEGER, blocked_user_id INTEGER);
    CREATE TABLE event_bookings(id INTEGER PRIMARY KEY, user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
      event_id INTEGER REFERENCES events(id) ON DELETE CASCADE, day_index INTEGER, role TEXT,
      character_name TEXT, message TEXT, outfit_image_url TEXT, interaction_tags TEXT,
      available_time TEXT, presence_status TEXT, work_id INTEGER, updated_at TEXT);
    INSERT INTO users(id,nickname,bio,public_code,is_admin) VALUES
      (1,'reporter','reporter bio','one',0),(2,'target','target bio','two',0),
      (3,'admin','admin bio','three',1),(4,'second admin','four bio','four',1),
      (5,'outsider','five bio','five',0);
    INSERT INTO events VALUES(10);
    INSERT INTO circles VALUES(20,2,'circle','description','SECRET','https://private.invalid/invite');
    INSERT INTO circle_members VALUES(20,1),(20,2);
    INSERT INTO event_bookings VALUES(30,2,10,1,'coser','character','booking message',
      'https://private.invalid/outfit','chat','noon','open',NULL,'2026-10-28 12:00:00');`);
  const migration = readFileSync(new URL('../db/migrate_content_reports.sql', import.meta.url), 'utf8');
  db.exec(migration.replace(/BIGINT UNSIGNED/g, 'INTEGER').replace(/INT UNSIGNED/g, 'INTEGER')
    .replace(/AUTO_INCREMENT/g, 'AUTOINCREMENT').replace(/ENUM\([^)]*\)/g, 'TEXT')
    .replace(/ ON UPDATE CURRENT_TIMESTAMP/g, '').replace(/^\s*KEY .*\n/gm, ''));
  const calls = [];
  let fault;
  const execute = async (sql, params = []) => {
    calls.push({sql, params});
    const failed = fault?.(sql, params);
    if (failed) return [failed];
    // Only MySQL dialect syntax is translated; SQLite evaluates all visibility predicates and writes.
    const portable = sql.replace(/ FOR UPDATE/g, '').replace(/<=>/g, 'IS')
      .replace(/DATE_SUB\(UTC_TIMESTAMP\(\), INTERVAL 24 HOUR\)/g, "datetime('now','-24 hours')")
      .replace(/DATE_ADD\(UTC_TIMESTAMP\(\), INTERVAL 90 DAY\)/g, "datetime('now','+90 days')")
      .replace(/UTC_TIMESTAMP\(\)/g, "datetime('now')");
    const statement = db.prepare(portable);
    if (statement.columns().length) return [statement.all(...params)];
    const result = statement.run(...params);
    return [{affectedRows: result.changes, insertId: result.lastInsertRowid}];
  };
  let queue = Promise.resolve();
  const pool = {execute, async getConnection() {
    const previous = queue;
    let release;
    queue = new Promise((resolve) => {release = resolve;});
    await previous;
    return {execute,
      async beginTransaction() {db.exec('BEGIN');},
      async commit() {db.exec('COMMIT');},
      async rollback() {db.exec('ROLLBACK');},
      release,
    };
  }};
  return {db, pool, calls, setFault(value) {fault = value;}};
}

const user = {targetType: 'user', targetUserId: '2', reason: 'harassment', details: 'Please review'};
const booking = {targetType: 'booking', targetUserId: '2', eventId: 10, dayIndex: 1, reason: 'spam'};
const circle = {targetType: 'circle', circleId: '20', reason: 'privacy'};
const resolution = {status: 'resolved', action: 'none', note: 'Reviewed', expectedVersion: 1};

test('validates target-specific identifiers, reasons, Unicode limits and rejects client evidence or identity', () => {
  assert.equal(validateReport({...booking, eventId: '10'}).eventId, '10');
  assert.equal(validateReport({...user, details: 'x'.repeat(1000)}).details.length, 1000);
  assert.equal([...validateReport({...user, details: '\u{1f680}'.repeat(1000)}).details].length, 1000);
  for (const body of [null, [], {...user, targetType: '__proto__'}, {...user, targetType: ['user']}, {...user, reason: 'ban'},
    {...user, details: 'x'.repeat(1001)}, {...user, details: 1}, {...user, targetUserId: '-2'},
    {...user, targetUserId: '18446744073709551616'}, {...user, targetUserId: '02'},
    {...user, snapshot: {nickname: 'forged'}}, {...user, reporterId: '5'},
    {...booking, dayIndex: 0}, {...booking, dayIndex: 1.1}, {...booking, dayIndex: 4294967296},
    {...booking, eventId: 9007199254740992}, {...booking, eventId: '10 OR 1=1'},
    {...circle, circleId: undefined}, {...circle, targetUserId: '2'}]) {
    assert.throws(() => validateReport(body), {status: 400});
  }
});

test('server snapshots only bounded visible fields and submission never performs moderation', async (t) => {
  const {db, pool, calls} = fixture(t);
  db.prepare('UPDATE users SET bio=? WHERE id=2').run('x'.repeat(900));
  const result = await submitReport(pool, 1, {...user, details: ' context '});
  assert.deepEqual(result, {id: '1', status: 'pending'});
  const row = db.prepare('SELECT * FROM content_reports').get();
  assert.deepEqual(JSON.parse(row.target_snapshot), {nickname: 'target', bio: 'x'.repeat(500), avatarUrl: null, otherPhotoUrls: []});
  assert.ok(Date.parse(row.evidence_expires_at + 'Z') - Date.now() > 89 * 86400000);
  assert.equal(row.details, 'context');
  assert.equal(row.reporter_user_id, 1);
  assert.equal(db.prepare('SELECT account_status FROM users WHERE id=2').get().account_status, 'active');
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM content_report_reviews').get().n, 0);
  assert.ok(calls.some(({sql}) => sql.includes("account_status = 'active' FOR UPDATE")));
  assert.ok(calls.some(({sql}) => sql.includes('public_code') && sql.endsWith('FOR UPDATE')));
});

for (const target of [user, booking]) {
  for (const [blocker, blocked] of [[1, 2], [2, 1]]) {
    test(`${target.targetType} rejects block ${blocker}->${blocked} using actual visibility SQL`, async (t) => {
      const {db, pool} = fixture(t);
      db.prepare('INSERT INTO user_blocks VALUES(?,?)').run(blocker, blocked);
      await assert.rejects(submitReport(pool, 1, target), {status: 404, code: 'report_target_unavailable'});
      assert.equal(db.prepare('SELECT COUNT(*) AS n FROM content_reports').get().n, 0);
    });
  }
}

test('unpublished user, missing target, inactive reporter, anonymous and self reports are refused', async (t) => {
  const {db, pool} = fixture(t);
  await assert.rejects(submitReport(pool, null, user), {status: 401});
  await assert.rejects(submitReport(pool, 2, user), {code: 'cannot_report_self'});
  await assert.rejects(submitReport(pool, 2, circle), {code: 'cannot_report_self'});
  await assert.rejects(submitReport(pool, 1, {...user, targetUserId: '99'}), {status: 404});
  db.exec("UPDATE users SET public_code='' WHERE id=2");
  await assert.rejects(submitReport(pool, 1, user), {status: 404});
  db.exec("UPDATE users SET account_status='suspended' WHERE id=1");
  await assert.rejects(submitReport(pool, 1, booking), {status: 401});
});

test('private booking needs shared circle; booking identity includes day and event', async (t) => {
  const {db, pool} = fixture(t);
  db.exec("UPDATE users SET booking_visibility='circle' WHERE id=2");
  await assert.rejects(submitReport(pool, 5, booking), {status: 404});
  await assert.rejects(submitReport(pool, 1, {...booking, dayIndex: 2}), {status: 404});
  await assert.rejects(submitReport(pool, 1, {...booking, eventId: 11}), {status: 404});
  await submitReport(pool, 1, booking);
  const row = db.prepare('SELECT * FROM content_reports').get();
  assert.equal(row.target_booking_id, 30);
  assert.deepEqual(Object.keys(JSON.parse(row.target_snapshot)), ['nickname', 'role', 'characterName', 'message', 'outfitImageUrl']);
});

test('suspended targets cannot be reported through hidden public profile or booking content', async (t) => {
  const {db, pool} = fixture(t);
  db.exec("UPDATE users SET account_status='suspended' WHERE id=2");
  await assert.rejects(submitReport(pool, 1, user), {status: 404, code: 'report_target_unavailable'});
  await assert.rejects(submitReport(pool, 1, booking), {status: 404, code: 'report_target_unavailable'});
});

test('circle reports require real membership and never capture invite codes, URLs or member lists', async (t) => {
  const {db, pool} = fixture(t);
  await assert.rejects(submitReport(pool, 5, circle), {status: 404});
  await submitReport(pool, 1, circle);
  assert.deepEqual(JSON.parse(db.prepare('SELECT target_snapshot FROM content_reports').get().target_snapshot),
    {name: 'circle', description: 'description'});
});

test('photo evidence comes only from the public server target, validates HTTPS and is bounded to three other photos', async (t) => {
  const {db, pool} = fixture(t);
  db.prepare('UPDATE users SET avatar_url=?,other_photo_urls_json=? WHERE id=2').run(
    'https://images.invalid/avatar.jpg', JSON.stringify([
      'http://images.invalid/insecure.jpg', 'https://user:password@images.invalid/private.jpg',
      'data:image/png;base64,secret', 'https://images.invalid/' + 'x'.repeat(2048),
      'https://images.invalid/one.jpg', 'https://images.invalid/two.jpg',
      'https://images.invalid/three.jpg', 'https://images.invalid/four.jpg', 42,
    ]));
  await submitReport(pool, 1, user);
  const report = (await listReports(pool, 3)).items[0];
  assert.equal(report.snapshot.avatarUrl, 'https://images.invalid/avatar.jpg');
  assert.deepEqual(report.snapshot.otherPhotoUrls, [
    'https://images.invalid/one.jpg', 'https://images.invalid/two.jpg', 'https://images.invalid/three.jpg',
  ]);
  await assert.rejects(submitReport(pool, 1, {...user, avatarUrl: 'https://forged.invalid/photo.jpg'}), {status: 400});
  await submitReport(pool, 1, booking);
  const photos = (await listReports(pool, 3)).items[0].snapshot;
  assert.equal(photos.outfitImageUrl, 'https://private.invalid/outfit');
  db.exec("UPDATE users SET avatar_url='https://images.invalid/replacement.jpg' WHERE id=2");
  await assert.rejects(reviewReport(pool, 3, report.id, {...resolution, action: 'suspend_user'}), {code: 'report_target_changed'});
  assert.equal((await listReports(pool, 3)).items.find((item) => item.id === report.id).snapshot.avatarUrl,
    'https://images.invalid/avatar.jpg');
});

test('changed booking photo preserves old evidence and refuses removal of the new booking content', async (t) => {
  const {db, pool} = fixture(t);
  const {id} = await submitReport(pool, 1, booking);
  db.exec("UPDATE event_bookings SET outfit_image_url='https://images.invalid/new-outfit.jpg' WHERE id=30");
  await assert.rejects(reviewReport(pool, 3, id, {...resolution, action: 'remove_booking'}), {code: 'report_target_changed'});
  assert.equal((await listReports(pool, 3)).items[0].snapshot.outfitImageUrl, 'https://private.invalid/outfit');
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM event_bookings').get().n, 1);
});

test('malformed photo arrays and credential-bearing avatar or outfit URLs are omitted', async (t) => {
  const {db, pool} = fixture(t);
  db.exec(`UPDATE users SET avatar_url='https://user@images.invalid/avatar', other_photo_urls_json='invalid json' WHERE id=2;
    UPDATE event_bookings SET outfit_image_url='javascript:alert(1)' WHERE id=30;`);
  await submitReport(pool, 1, user);
  await submitReport(pool, 1, booking);
  const page = await listReports(pool, 3);
  assert.equal(page.items[0].snapshot.outfitImageUrl, null);
  assert.equal(page.items[1].snapshot.avatarUrl, null);
  assert.deepEqual(page.items[1].snapshot.otherPhotoUrls, []);
});

test('serialized simultaneous submissions and closed-report cooldown prevent duplicate spam', async (t) => {
  const {db, pool} = fixture(t);
  const results = await Promise.allSettled([submitReport(pool, 1, user), submitReport(pool, 1, user)]);
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal(results.find((result) => result.status === 'rejected').reason.code, 'duplicate_report');
  await reviewReport(pool, 3, '1', resolution);
  await assert.rejects(submitReport(pool, 1, user), {code: 'duplicate_report'});
  db.exec("UPDATE content_reports SET created_at=datetime('now','-25 hours')");
  assert.equal((await submitReport(pool, 1, user)).id, '2');
});

test('admin-only queue filters, bounds and paginates reports with at most twenty reviews per item', async (t) => {
  const {db, pool} = fixture(t);
  await submitReport(pool, 1, user);
  for (let i = 0; i < 31; i++) {
    db.exec(`INSERT INTO content_reports(reporter_user_id,target_type,target_user_id,reason,evidence_expires_at)
      VALUES(1,'user',2,'spam',datetime('now','+1 day'))`);
  }
  for (let i = 0; i < 25; i++) {
    db.exec(`INSERT INTO content_report_reviews(report_id,admin_user_id,from_status,to_status,action,note)
      VALUES(32,3,'pending','reviewing','none','review note')`);
  }
  await assert.rejects(listReports(pool, null), {status: 401});
  await assert.rejects(listReports(pool, 2), {status: 403});
  for (const query of [{status: 'all'}, {status: ['pending']}, {beforeId: '-1'}, {beforeId: ['1']}]) {
    await assert.rejects(listReports(pool, 3, query), {status: 400});
  }
  const page = await listReports(pool, 3);
  assert.equal(page.items.length, 30);
  assert.equal(page.items[0].id, '32');
  assert.equal(page.items[0].reviews.length, 20);
  assert.equal(page.nextBeforeId, '3');
  const next = await listReports(pool, 3, {beforeId: page.nextBeforeId});
  assert.deepEqual(next.items.map((item) => item.id), ['2', '1']);
  assert.equal(next.nextBeforeId, null);
  assert.equal(next.items[1].snapshot.nickname, 'target');
  assert.deepEqual((await listReports(pool, 3, {status: 'dismissed'})).items, []);
});

test('review state/version conflicts and invalid combinations leave the target unchanged', async (t) => {
  const {db, pool} = fixture(t);
  await submitReport(pool, 1, user);
  await assert.rejects(reviewReport(pool, 2, '1', resolution), {status: 403});
  for (const body of [{...resolution, action: 'remove_circle'}, {...resolution, action: 'invalid'},
    {...resolution, status: 'reviewing', action: 'suspend_user'},
    {...resolution, action: 'suspend_user', note: ''}, {...resolution, note: 'x'.repeat(1001)},
    {...resolution, expectedVersion: 0}, {...resolution, expectedVersion: '1'},
    {...resolution, extra: true}]) {
    await assert.rejects(reviewReport(pool, 3, '1', body), {status: 400});
  }
  await assert.rejects(reviewReport(pool, 3, '1', {...resolution, status: 'pending'}), {code: 'stale_report'});
  await reviewReport(pool, 3, '1', {...resolution, status: 'reviewing'});
  await assert.rejects(reviewReport(pool, 3, '1', resolution), {code: 'stale_report'});
  await reviewReport(pool, 3, '1', {...resolution, status: 'dismissed', expectedVersion: 2});
  await assert.rejects(reviewReport(pool, 3, '1', {...resolution, expectedVersion: 3}), {code: 'stale_report'});
  assert.equal(db.prepare('SELECT account_status FROM users WHERE id=2').get().account_status, 'active');
});

for (const [target, action, table] of [[user, 'suspend_user', 'users'],
  [booking, 'remove_booking', 'event_bookings'], [circle, 'remove_circle', 'circles']]) {
  test(`human ${action} happens once and audits atomically`, async (t) => {
    const {db, pool} = fixture(t);
    const {id} = await submitReport(pool, 1, target);
    const body = {...resolution, action};
    const results = await Promise.allSettled([reviewReport(pool, 3, id, body), reviewReport(pool, 3, id, body)]);
    assert.equal(results.filter((result) => result.status === 'fulfilled').length, 1);
    assert.equal(results.find((result) => result.status === 'rejected').reason.code, 'stale_report');
    const row = db.prepare('SELECT * FROM content_reports').get();
    assert.equal(row.status, 'resolved');
    assert.equal(row.version, 2);
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM content_report_reviews').get().n, 1);
    if (action === 'suspend_user') {
      assert.deepEqual({...db.prepare('SELECT account_status,session_token FROM users WHERE id=2').get()},
        {account_status: 'suspended', session_token: null});
    } else {
      assert.equal(db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n, 0);
    }
  });
}

test('any admin account is protected, including another admin, the last admin and suspended admins', async (t) => {
  const {db, pool} = fixture(t);
  for (const [targetId, active] of [['4', true], ['2', false], ['3', true]]) {
    db.exec(`UPDATE users SET is_admin=1 WHERE id=${targetId}`);
    const {id} = await submitReport(pool, 1, {...user, targetUserId: targetId});
    if (!active) db.exec(`UPDATE users SET account_status='suspended' WHERE id=${targetId}`);
    if (targetId === '3') db.exec('UPDATE users SET is_admin=0 WHERE id<>3');
    const before = db.prepare('SELECT account_status,session_token FROM users WHERE id=?').get(targetId);
    await assert.rejects(reviewReport(pool, 3, id, {...resolution, action: 'suspend_user'}),
      {status: 403, code: 'protected_admin_account'});
    assert.deepEqual(db.prepare('SELECT account_status,session_token FROM users WHERE id=?').get(targetId), before);
    assert.equal(db.prepare('SELECT status FROM content_reports WHERE id=?').get(id).status, 'pending');
  }
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM content_report_reviews').get().n, 0);
});

test('changed or recreated content and expired evidence cannot cause destructive moderation', async (t) => {
  const {db, pool} = fixture(t);
  const {id} = await submitReport(pool, 1, booking);
  db.exec("UPDATE event_bookings SET message='new content' WHERE id=30");
  await assert.rejects(reviewReport(pool, 3, id, {...resolution, action: 'remove_booking'}), {code: 'report_target_changed'});
  db.exec(`INSERT INTO event_bookings SELECT 31,user_id,event_id,day_index,role,character_name,'booking message',
    outfit_image_url,interaction_tags,available_time,presence_status,work_id,updated_at FROM event_bookings WHERE id=30;
    DELETE FROM event_bookings WHERE id=30;`);
  await assert.rejects(reviewReport(pool, 3, id, {...resolution, action: 'remove_booking'}), {code: 'report_target_changed'});
  db.exec("UPDATE content_reports SET evidence_expires_at=datetime('now','-1 second')");
  await assert.rejects(reviewReport(pool, 3, id, {...resolution, action: 'suspend_user'}), {code: 'report_evidence_unavailable'});
  await reviewReport(pool, 3, id, {...resolution, status: 'dismissed'});
  assert.equal(db.prepare('SELECT note FROM content_report_reviews').get().note, null);
});

test('failed audit or lost CAS rolls back the moderation action and report transition', async (t) => {
  const {db, pool, setFault} = fixture(t);
  await submitReport(pool, 1, booking);
  for (const failure of ['audit', 'CAS']) {
    setFault((sql) => {
      if (failure === 'audit' && sql.startsWith('INSERT INTO content_report_reviews')) throw new Error('audit failed');
      if (failure === 'CAS' && sql.startsWith('UPDATE content_reports SET status')) return {affectedRows: 0};
    });
    await assert.rejects(reviewReport(pool, 3, '1', {...resolution, action: 'remove_booking'}),
      failure === 'audit' ? /audit failed/ : {code: 'stale_report'});
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM event_bookings').get().n, 1);
    assert.equal(db.prepare('SELECT status FROM content_reports').get().status, 'pending');
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM content_report_reviews').get().n, 0);
  }
});

test('expiry physically clears details, snapshots, fingerprints and review notes', async (t) => {
  const {db, pool} = fixture(t);
  await submitReport(pool, 1, user);
  await reviewReport(pool, 3, '1', {...resolution, status: 'reviewing'});
  db.exec("UPDATE content_reports SET evidence_expires_at=datetime('now','-1 second')");
  await purgeExpiredReportEvidence(pool);
  const report = db.prepare('SELECT * FROM content_reports').get();
  for (const key of ['details', 'target_snapshot', 'target_fingerprint']) assert.equal(report[key], null);
  assert.equal(db.prepare('SELECT note FROM content_report_reviews').get().note, null);
  assert.equal((await listReports(pool, 3, {status: 'reviewing'})).items[0].snapshot, null);
});

for (const deletedId of [1, 2, 3]) {
  test(`account deletion ${deletedId} clears related personal evidence and FK identities`, async (t) => {
    const {db, pool} = fixture(t);
    await submitReport(pool, 1, user);
    await reviewReport(pool, 3, '1', {...resolution, status: 'reviewing'});
    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      await eraseReportPersonalData(connection, deletedId);
      await connection.execute('DELETE FROM users WHERE id=?', [deletedId]);
      await connection.commit();
    } finally {connection.release();}
    const row = db.prepare('SELECT * FROM content_reports').get();
    assert.equal(db.prepare('SELECT note FROM content_report_reviews').get().note, null);
    if (deletedId === 3) {
      assert.equal(db.prepare('SELECT admin_user_id FROM content_report_reviews').get().admin_user_id, null);
      assert.notEqual(row.target_snapshot, null);
    } else {
      for (const key of ['details', 'target_snapshot', 'target_fingerprint']) assert.equal(row[key], null);
      assert.equal(row[deletedId === 1 ? 'reporter_user_id' : 'target_user_id'], null);
    }
  });
}

test('private and admin routes register separately, forbid targets from queue access and return safe errors', async (t) => {
  const {pool, setFault} = fixture(t);
  const routes = new Map();
  const app = {post(path, handler) {routes.set(`POST ${path}`, handler);}, get(path, handler) {routes.set(`GET ${path}`, handler);}};
  registerReportRoutes(app, pool);
  assert.deepEqual([...routes.keys()], ['POST /api/reports']);
  registerReportAdminRoutes(app, pool);
  assert.equal(routes.size, 3);
  const invoke = async (route, req) => {
    const res = {code: 200, headers: {}, set(key, value) {this.headers[key] = value;},
      status(code) {this.code = code; return this;}, json(body) {this.body = body;}};
    await routes.get(route)({get: () => 'Bearer token', ...req}, res, (error) => {res.forwarded = error;});
    assert.equal(res.headers['Cache-Control'], 'private, no-store');
    return res;
  };
  const created = await invoke('POST /api/reports', {userId: 1, body: user});
  assert.equal(created.code, 201);
  assert.deepEqual(Object.keys(created.body), ['id', 'status']);
  const forbidden = await invoke('GET /api/admin/reports', {userId: 2, query: {}});
  assert.equal(forbidden.code, 403);
  assert.deepEqual(forbidden.body, {error: 'admin_required'});
  const reviewed = await invoke('POST /api/admin/reports/:id/review', {userId: 3, params: {id: '1'}, body: resolution});
  assert.equal(reviewed.body.status, 'resolved');
  setFault(() => {throw new Error('database unavailable');});
  const failed = await invoke('POST /api/reports', {userId: 1, body: user});
  assert.equal(failed.forwarded.message, 'database unavailable');
});

test('a previously authorized admin cannot review or list after its bearer session rotates', async t => {
  const {pool, db} = fixture(t);
  const report = await submitReport(pool, 1, user);
  const routes = new Map();
  registerReportAdminRoutes({get(path, handler){routes.set('get', handler);}, post(path, handler){routes.set('post', handler);}}, pool);
  const request = {userId: 3, get:()=> 'Bearer token', params:{id:report.id}, query:{}, body:{...resolution,action:'suspend_user',note:'verified spam'}};
  db.exec("UPDATE users SET session_token='replacement-session' WHERE id=3");
  for (const handler of routes.values()) {
    const res = {set(){},status(code){this.code=code;return this;},json(body){this.body=body;}};
    await handler(request,res,error=>{throw error;});
    assert.equal(res.code,401);
    assert.equal(res.body.error,'unauthorized');
  }
  assert.equal(db.prepare('SELECT account_status FROM users WHERE id=2').get().account_status,'active');
  assert.equal(db.prepare('SELECT status FROM content_reports').get().status,'pending');
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM content_report_reviews').get().count,0);
});
