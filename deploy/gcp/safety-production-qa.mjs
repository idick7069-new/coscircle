import 'dotenv/config';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import {createPool} from '../src/db.js';

if (!process.argv.includes('--run-production-qa')) throw new Error('explicit_qa_flag_required');
const pool = createPool();
const marker = `safety-qa-${crypto.randomUUID()}`;
const provider = 'qa_safety_deploy';
const users = [];
const reportIds = [];
const uploads = [];
let eventId;
let circleId;
const scrypt = promisify(crypto.scrypt);
const uploadDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../uploads');
const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=';
async function api(method, endpoint, user, body, expected) {
  const response = await fetch(`http://127.0.0.1:8080/api${endpoint}`, {
    method, headers: {'Content-Type': 'application/json', 'X-Forwarded-Proto': 'https',
      ...(user ? {Authorization: `Bearer ${user.token}`} : {})},
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  assert.equal(response.status, expected, `${method} ${endpoint}: expected ${expected}, received ${response.status}`);
  return response.status === 204 ? null : response.json();
}
async function seedUser(label, admin = false) {
  const token = crypto.randomBytes(32).toString('hex');
  const password = crypto.randomBytes(24).toString('hex');
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = `${salt}:${(await scrypt(password, salt, 64)).toString('hex')}`;
  const subject = `${marker}-${label}`;
  const [row] = await pool.execute(`INSERT INTO users
    (provider,provider_user_id,public_code,nickname,session_token,is_admin,bio,onboarding_completed)
    VALUES (?,?,?,?,?,?,?,TRUE)`, [provider, subject, subject, `QA-${label}`, token, Number(admin), marker]);
  const user = {id: String(row.insertId), token, password};
  users.push(user);
  await pool.execute(`INSERT INTO user_auth_identities
    (user_id,provider,provider_user_id,password_hash,verified_at) VALUES (?,'email',?,?,UTC_TIMESTAMP())`,
  [user.id, `${subject}@example.invalid`, hash]);
  return user;
}
const pass = message => console.log(`PASS ${message}`);
try {
  const reporter = await seedUser('reporter');
  const target = await seedUser('target');
  const admin = await seedUser('admin', true);
  await api('POST', '/me/delete-account', null, {confirmation: 'DELETE'}, 401);
  await api('POST', '/reports', null, {}, 401);
  pass('anonymous deletion/report requests rejected');

  const legal = await api('GET', '/me/legal', target, undefined, 200);
  await api('POST', '/me/legal', target, {version: legal.version, accepted: true}, 200);
  const [event] = await pool.execute(`INSERT INTO events
    (source_key,source_type,source_name,category,name,start_date,end_date,venue,status)
    VALUES (?,3,'QA','QA',?,UTC_DATE(),UTC_DATE(),'QA','pending')`, [marker, marker]);
  eventId = String(event.insertId);
  const [circle] = await pool.execute(`INSERT INTO circles
    (owner_user_id,name,description,invite_code,invite_url) VALUES (?,?,?,?,?)`,
  [target.id, marker, 'QA circle', marker.slice(-32), 'https://coscircle.app/app']);
  circleId = String(circle.insertId);
  await pool.execute('INSERT INTO circle_members (circle_id,user_id) VALUES (?,?),(?,?)',
    [circleId, target.id, circleId, reporter.id]);
  await pool.execute(`INSERT INTO event_bookings (event_id,user_id,day_index,role,character_name,message)
    VALUES (?,?,1,'coser','QA','QA booking')`, [eventId, target.id]);
  await pool.execute(`INSERT INTO event_submissions
    (submitter_user_id,name,start_date,end_date,venue) VALUES (?,?,UTC_DATE(),UTC_DATE(),'QA')`, [target.id, marker]);
  await pool.execute('INSERT INTO follows (follower_user_id,followed_user_id) VALUES (?,?)', [reporter.id, target.id]);

  for (const user of [reporter, target]) {
    const uploaded = await api('POST', '/uploads/image', user, {bytesBase64: png, mimeType: 'image/png'}, 201);
    const name = new URL(uploaded.url).pathname.split('/').at(-1);
    assert.match(name, /^[a-f0-9-]{36}\.png$/);
    uploads.push(name);
    const [[owner]] = await pool.execute('SELECT user_id FROM account_uploads WHERE file_name=?', [name]);
    assert.equal(String(owner.user_id), user.id);
    await fs.access(path.join(uploadDir, name));
    await pool.execute('UPDATE users SET avatar_url=? WHERE id=?', [uploaded.url, user.id]);
  }
  pass('uploads record ownership and files exist');
  const ownReport = {targetType: 'user', targetUserId: reporter.id, reason: 'other'};
  await api('POST', '/reports', reporter, ownReport, 400);
  const body = {targetType: 'user', targetUserId: target.id, reason: 'harassment', details: marker};
  const report = await api('POST', '/reports', reporter, body, 201);
  reportIds.push(report.id);
  await api('POST', '/reports', reporter, body, 409);
  await api('GET', '/admin/reports', reporter, undefined, 403);
  pass('report creation, self-report protection, deduplication and admin access control');

  await pool.execute('INSERT INTO user_blocks (blocker_user_id,blocked_user_id) VALUES (?,?)', [target.id, reporter.id]);
  await api('POST', '/reports', reporter, body, 404);
  await pool.execute('DELETE FROM user_blocks WHERE blocker_user_id=? AND blocked_user_id=?', [target.id, reporter.id]);
  const bookingReport = await api('POST', '/reports', reporter,
    {targetType: 'booking', targetUserId: target.id, eventId, dayIndex: 1, reason: 'other', details: marker}, 201);
  reportIds.push(bookingReport.id);
  const circleReport = await api('POST', '/reports', reporter,
    {targetType: 'circle', circleId, reason: 'spam', details: marker}, 201);
  reportIds.push(circleReport.id);
  await api('POST', '/reports', reporter,
    {targetType: 'booking', targetUserId: target.id, eventId, dayIndex: 2, reason: 'other'}, 404);
  await pool.execute('DELETE FROM circle_members WHERE circle_id=? AND user_id=?', [circleId, reporter.id]);
  await pool.execute("UPDATE users SET booking_visibility='circle' WHERE id=?", [target.id]);
  await api('POST', '/reports', reporter,
    {targetType: 'booking', targetUserId: target.id, eventId, dayIndex: 1, reason: 'other'}, 404);
  pass('user/booking/circle reports respect blocking, event day and circle privacy');

  const queue = await api('GET', '/admin/reports', admin, undefined, 200);
  const item = queue.items.find(row => row.id === report.id);
  assert(item && item.snapshot);
  await api('POST', `/admin/reports/${report.id}/review`, admin,
    {status: 'reviewing', action: 'none', expectedVersion: item.version, note: marker}, 200);
  await api('POST', `/admin/reports/${report.id}/review`, admin,
    {status: 'resolved', action: 'none', expectedVersion: item.version, note: marker}, 409);
  await api('POST', `/admin/reports/${report.id}/review`, admin,
    {status: 'resolved', action: 'none', expectedVersion: item.version + 1, note: marker}, 200);
  // Exercise list-with-review-history SQL on the actual production MySQL engine.
  const reviewed = await api('GET', '/admin/reports?status=resolved', admin, undefined, 200);
  assert.equal(reviewed.items.find(row => row.id === report.id)?.reviews.length, 2);
  pass('admin queue, review history and stale-version protection');

  const invalid = await api('POST', '/me/delete-account', target,
    {confirmation: 'wrong', password: target.password}, 400);
  assert.equal(invalid.error, 'invalid_confirmation');
  const wrong = await api('POST', '/me/delete-account', target,
    {confirmation: 'DELETE', password: 'incorrect'}, 403);
  assert.equal(wrong.error, 'reauthentication_required');
  const [[stillThere]] = await pool.execute('SELECT id FROM users WHERE id=?', [target.id]);
  assert(stillThere);
  await api('POST', '/me/delete-account', target,
    {confirmation: 'DELETE', password: target.password}, 204);
  await api('GET', '/me', target, undefined, 401);
  pass('deletion requires explicit confirmation and password; deleted session revoked');

  for (const [table, field] of [['users', 'id'], ['user_auth_identities', 'user_id'],
    ['event_bookings', 'user_id'], ['circle_members', 'user_id'], ['circles', 'owner_user_id'],
    ['event_submissions', 'submitter_user_id'], ['user_legal_consents', 'user_id']]) {
    const [[row]] = await pool.execute(`SELECT COUNT(*) AS count FROM ${table} WHERE ${field}=?`, [target.id]);
    assert.equal(row.count, 0, `${table} cleanup`);
  }
  const [[follow]] = await pool.execute('SELECT COUNT(*) AS count FROM follows WHERE followed_user_id=?', [target.id]);
  assert.equal(follow.count, 0);
  const [[scrubbed]] = await pool.execute('SELECT target_user_id,details,target_snapshot,target_fingerprint FROM content_reports WHERE id=?', [report.id]);
  assert.deepEqual(scrubbed, {target_user_id: null, details: null, target_snapshot: null, target_fingerprint: null});
  const [[notes]] = await pool.execute('SELECT COUNT(*) AS count FROM content_report_reviews WHERE report_id=? AND note IS NOT NULL', [report.id]);
  assert.equal(notes.count, 0);
  await assert.rejects(fs.access(path.join(uploadDir, uploads[1])), {code: 'ENOENT'});
  await fs.access(path.join(uploadDir, uploads[0]));
  pass('dependent data and owned file erased; evidence anonymized; other QA file preserved');
} finally {
  try {
    for (const id of reportIds) {
      await pool.execute('DELETE FROM content_reports WHERE id=? AND reporter_user_id IN (SELECT id FROM users WHERE provider=? AND provider_user_id LIKE ?)',
        [id, provider, `${marker}%`]);
    }
    await pool.execute('DELETE FROM users WHERE provider=? AND provider_user_id LIKE ?', [provider, `${marker}%`]);
    if (eventId) await pool.execute('DELETE FROM events WHERE id=? AND source_key=?', [eventId, marker]);
    for (const name of uploads) {
      // Only names returned by this run's own authenticated upload requests are eligible.
      await fs.unlink(path.join(uploadDir, name)).catch(error => {if (error.code !== 'ENOENT') throw error;});
      await pool.execute('DELETE FROM account_upload_cleanup WHERE file_name=?', [name]);
      await pool.execute('DELETE FROM account_uploads WHERE file_name=? AND user_id IS NULL', [name]);
    }
    const [[left]] = await pool.execute('SELECT COUNT(*) AS count FROM users WHERE provider=? AND provider_user_id LIKE ?', [provider, `${marker}%`]);
    assert.equal(left.count, 0);
    pass('QA accounts, pending event, reports and uploaded fixtures cleaned');
  } finally {await pool.end();}
}
