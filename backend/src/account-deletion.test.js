import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import path from 'node:path';
import {accountDeletionTableSql, createAccountDeletionService,
  ensureAccountDeletionTables, registerAccountDeletionRoutes} from './account-deletion.js';

const uploadDir = '/virtual/coscircle-uploads';
const ownFile = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.png';
const otherFile = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.jpg';
const orphanFile = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc.webp';

function sqliteSchema(sql) {
  return sql.replace(/ENUM\([^)]*\)/g, 'TEXT')
    .replace(/\bBIGINT UNSIGNED\b|\bINT UNSIGNED\b|\bTINYINT UNSIGNED\b/g, 'INTEGER')
    .replace(/\bAUTO_INCREMENT\b/g, '')
    .replace(/ CHARACTER SET \w+| COLLATE \w+/g, '')
    .replace(/ ON UPDATE CURRENT_TIMESTAMP/g, '')
    .replace(/UNIQUE KEY \w+\s*\(/g, 'UNIQUE (')
    .replace(/^\s*KEY \w+[^\n]*\n/gm, '')
    .replace(/,\s*\)/g, ')').replace(/ ENGINE=InnoDB/g, '');
}

function fixture(options = {}) {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys=ON');
  db.exec(sqliteSchema(readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8')));
  db.exec(`CREATE TABLE IF NOT EXISTS admin_audit_logs (id INTEGER PRIMARY KEY, admin_user_id INTEGER NOT NULL,
    action TEXT NOT NULL, target_id TEXT, payload_json TEXT, ip_address TEXT,
    FOREIGN KEY (admin_user_id) REFERENCES users(id) ON DELETE CASCADE)`);
  for (const sql of accountDeletionTableSql) db.exec(sqliteSchema(sql));
  db.exec(`INSERT INTO users (id,provider,provider_user_id,public_code,nickname,session_token,is_admin,account_status)
    VALUES (1,'email','one@example.invalid','one','Owner','session-1',0,'active'),
      (2,'line','LINE-2','two','Other','session-2',0,'active'),
      (3,'email','admin@example.invalid','three','Admin','session-3',1,'active');
    INSERT INTO user_auth_identities (id,user_id,provider,provider_user_id,password_hash)
      VALUES (11,1,'email','one@example.invalid','hash-1'),(12,1,'line','LINE-1',NULL),
        (20,2,'line','LINE-2',NULL),(30,3,'email','admin@example.invalid','hash-3');
    INSERT INTO events (id,category,name,start_date,end_date,venue)
      VALUES (10,'event','Shared event','2026-10-29','2026-10-30','Venue');
    INSERT INTO works (id,name) VALUES (10,'Shared work');
    INSERT INTO user_pit_works (user_id,work_id) VALUES (1,10),(2,10);
    INSERT INTO email_action_tokens (identity_id,kind,token_hash,email_snapshot,created_at_ms,expires_at_ms)
      VALUES (11,'reset-password','hash','one@example.invalid',1,99999);
    INSERT INTO device_push_tokens (user_id,platform,token) VALUES (1,'android','push-1'),(2,'ios','push-2');
    INSERT INTO event_bookings (event_id,user_id,role,outfit_image_url)
      VALUES (10,1,'coser','https://coscircle.invalid/uploads/${otherFile}'),(10,2,'self',NULL);
    INSERT INTO friendships (user_low_id,user_high_id,requester_id,recipient_id,introduction)
      VALUES (1,2,1,2,'Private introduction');
    INSERT INTO follows (follower_user_id,followed_user_id) VALUES (1,2),(2,1),(2,3);
    INSERT INTO user_blocks (blocker_user_id,blocked_user_id) VALUES (1,3),(2,1);
    INSERT INTO circles (id,owner_user_id,name,invite_code,invite_url)
      VALUES (10,1,'Private circle','private','private-url'),(20,2,'Other circle','other','other-url');
    INSERT INTO circle_members (circle_id,user_id) VALUES (10,1),(10,2),(20,1),(20,2);
    INSERT INTO shared_locations (event_id,user_id,latitude,longitude) VALUES (10,1,25,121),(10,2,25,121);
    INSERT INTO event_meeting_points (event_id,circle_id,creator_user_id,latitude,longitude,meet_at)
      VALUES (10,10,2,25,121,'2026-10-29'),(10,20,1,25,121,'2026-10-29'),(10,20,2,25,121,'2026-10-29');
    INSERT INTO event_recognition_requests (event_id,requester_user_id,target_user_id)
      VALUES (10,1,2),(10,2,1),(10,2,3);
    INSERT INTO event_submissions (submitter_user_id,name,start_date,end_date,venue,description)
      VALUES (1,'Mine','2026-10-29','2026-10-30','Venue','Personal data'),
        (2,'Other','2026-10-29','2026-10-30','Venue','Other data');
    INSERT INTO admin_audit_logs (admin_user_id,action,target_id,payload_json,ip_address)
      VALUES (3,'user.suspended','1','sensitive','127.0.0.1'),(3,'user.active','2','other','127.0.0.1'),
        (1,'event.edit','10','mine','127.0.0.1');
    INSERT INTO account_uploads (file_name,user_id) VALUES ('${ownFile}',1),('${otherFile}',2);
    UPDATE users SET avatar_url='https://coscircle.invalid/uploads/${otherFile}',
      other_photo_urls_json='["/uploads/../../foreign","https://foreign.invalid/photo"]' WHERE id=1;`);
  const files = new Map([[path.join(uploadDir, ownFile), 'mine'], [path.join(uploadDir, otherFile), 'other']]);
  const unlinked = [];
  const statements = [];
  let diskFailure = false;
  let beforeBegin;
  let failSql;
  let failCommit = false;
  let commitCount = 0;
  // SQLite serializes writers. This gate models the shared admin lock for overlapping calls.
  let tail = Promise.resolve();
  const pool = {
    execute: async (sql, params = []) => {
      statements.push({sql, params});
      if (failSql?.(sql)) throw new Error('SQL failure contains a secret');
      const statement = db.prepare(sql.replaceAll(' FOR UPDATE', '').replaceAll('INSERT IGNORE', 'INSERT OR IGNORE'));
      if (sql.trim().startsWith('SELECT')) return [statement.all(...params)];
      const result = statement.run(...params);
      return [{affectedRows: Number(result.changes), insertId: Number(result.lastInsertRowid)}];
    },
    getConnection: async () => {
      let releaseGate;
      const previous = tail;
      tail = new Promise(resolve => {releaseGate = resolve;});
      await previous;
      return {execute: pool.execute,
        beginTransaction: async () => {beforeBegin?.(); beforeBegin = undefined; db.exec('BEGIN');},
        commit: async () => {
          commitCount++;
          if (failCommit) {failCommit = false; throw new Error('commit unavailable');}
          db.exec('COMMIT');
        },
        rollback: async () => db.exec('ROLLBACK'), release: releaseGate};
    },
  };
  const fileSystem = {
    mkdir: async () => {},
    writeFile: async (file, bytes, flags) => {
      assert.deepEqual(flags, {flag: 'wx'});
      if (files.has(file)) throw Object.assign(new Error('exists'), {code: 'EEXIST'});
      files.set(file, bytes.toString());
    },
    unlink: async file => {
      unlinked.push(file);
      if (diskFailure) throw Object.assign(new Error('disk unavailable'), {code: 'EACCES'});
      if (!files.delete(file)) throw Object.assign(new Error('missing'), {code: 'ENOENT'});
    },
  };
  const serviceOptions = {uploadDir, fileSystem, publicUploadOrigins: ['https://coscircle.invalid', 'https://34.187.168.222'],
    verifyPassword: async (password, hash) => password === 'correct' && hash === 'hash-1',
    fetchLineProfile: async token => ({id: token === 'line-token-one' ? 'LINE-1' : 'LINE-2'}), ...options};
  const service = createAccountDeletionService(pool, serviceOptions);
  return {db, service, pool, files, unlinked, statements, fileSystem, serviceOptions,
    delete: overrides => service.deleteAccount({sessionToken: 'session-1', confirmation: 'DELETE', password: 'correct', ...overrides}),
    admin: {userId: 1, adminUserId: 3, sessionToken: 'session-3'},
    failDisk: value => {diskFailure = value;},
    beforeBegin: fn => {beforeBegin = fn;}, failSql: fn => {failSql = fn;},
    failCommit: () => {failCommit = true;}, commits: () => commitCount,
    count: table => db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n,
    user: id => db.prepare('SELECT * FROM users WHERE id=?').get(id)};
}

test('self deletion removes private data and owned media while preserving other accounts and shared content', async () => {
  const f = fixture();
  try {
    await f.delete({userId: 2});
    assert.equal(f.user(1), undefined);
    assert.ok(f.user(2));
    assert.ok(f.user(3));
    for (const table of ['email_action_tokens', 'friendships', 'user_blocks']) assert.equal(f.count(table), 0, table);
    for (const table of ['user_pit_works', 'event_bookings', 'follows', 'circle_members', 'shared_locations',
      'event_meeting_points', 'event_recognition_requests', 'event_submissions', 'admin_audit_logs', 'device_push_tokens']) {
      assert.equal(f.count(table), 1, table);
    }
    assert.equal(f.count('user_auth_identities'), 2);
    assert.equal(f.count('events'), 1);
    assert.equal(f.count('works'), 1);
    assert.equal(f.count('circles'), 1);
    assert.deepEqual(f.unlinked, [path.join(uploadDir, ownFile)]);
    assert.equal(f.files.has(path.join(uploadDir, otherFile)), true);
    assert.equal(f.count('account_upload_cleanup'), 0);
    assert.equal(f.count('account_uploads'), 1);
  } finally {f.db.close();}
});

test('confirmation, credential types and missing bearer tokens fail before deletion', async () => {
  const f = fixture();
  try {
    for (const confirmation of [undefined, '', 'delete', true]) {
      await assert.rejects(f.delete({confirmation}), {code: 'invalid_confirmation'});
    }
    for (const password of [undefined, '', {}, true, 'x'.repeat(1025)]) {
      await assert.rejects(f.delete({password}), {code: 'reauthentication_required'});
    }
    for (const sessionToken of [undefined, '', {}, 'x'.repeat(192)]) {
      await assert.rejects(f.delete({sessionToken}), {code: 'authentication_required'});
    }
    await assert.rejects(f.delete({lineAccessToken: 'line-token-one'}), {code: 'reauthentication_required'});
    await assert.rejects(f.delete({password: 'wrong'}), {code: 'reauthentication_required'});
    assert.ok(f.user(1));
    assert.equal(f.unlinked.length, 0);
  } finally {f.db.close();}
});

test('session rotation or suspension before the transaction invalidates a previously authenticated request', async () => {
  for (const update of ["session_token='new-session'", "session_token=NULL", "account_status='suspended'"]) {
    const f = fixture();
    try {
      f.beforeBegin(() => f.db.exec(`UPDATE users SET ${update} WHERE id=1`));
      await assert.rejects(f.delete(), {code: 'authentication_required'});
      assert.ok(f.user(1));
      assert.equal(f.count('account_upload_cleanup'), 0);
    } finally {f.db.close();}
  }
});

test('password reauthentication uses the current locked identity after a password change', async () => {
  const f = fixture();
  try {
    f.beforeBegin(() => f.db.exec("UPDATE user_auth_identities SET password_hash='changed-hash' WHERE id=11"));
    await assert.rejects(f.delete(), {code: 'reauthentication_required'});
    assert.ok(f.user(1));
    assert.equal(f.unlinked.length, 0);
  } finally {f.db.close();}
});

test('session tokens are compared exactly even when a database collation matches case insensitively', async () => {
  const f = fixture();
  try {
    const original = f.pool.execute;
    f.pool.execute = async (sql, params) => original(sql.includes('WHERE session_token=?')
      ? sql.replace('session_token=?', 'session_token=? COLLATE NOCASE') : sql, params);
    await assert.rejects(f.delete({sessionToken: 'SESSION-1'}), {code: 'authentication_required'});
    assert.ok(f.user(1));
  } finally {f.db.close();}
});

test('LINE reauthentication requires the provider subject linked to the same user', async () => {
  for (const token of ['line-token-one', 'line-token-two']) {
    const f = fixture();
    try {
      if (token === 'line-token-one') {
        await f.delete({password: undefined, lineAccessToken: token});
        assert.equal(f.user(1), undefined);
      } else {
        await assert.rejects(f.delete({password: undefined, lineAccessToken: token}), {code: 'reauthentication_required'});
        assert.ok(f.user(1));
      }
    } finally {f.db.close();}
  }
});

test('LINE verification runs without database locks and rechecks session and identity after the response', async () => {
  for (const change of [null, "UPDATE users SET session_token='rotated' WHERE id=1",
    "UPDATE user_auth_identities SET provider_user_id='new-subject' WHERE id=12"]) {
    let f;
    f = fixture({fetchLineProfile: async () => {
      assert.equal(f.statements.length, 0);
      assert.equal(f.commits(), 0);
      if (change) f.db.exec(change);
      return {id: 'LINE-1'};
    }});
    try {
      const deletion = f.delete({password: undefined, lineAccessToken: 'line-token-one'});
      if (!change) {
        await deletion;
        assert.equal(f.user(1), undefined);
      } else {
        await assert.rejects(deletion, {code: change.includes('session_token')
          ? 'authentication_required' : 'reauthentication_required'});
        assert.ok(f.user(1));
      }
    } finally {f.db.close();}
  }
});

test('a linked email password works for LINE-first users without trusting the legacy password column', async () => {
  const f = fixture();
  try {
    f.db.exec("UPDATE users SET provider='line',password_hash='wrong-legacy' WHERE id=1");
    await f.delete();
    assert.equal(f.user(1), undefined);
  } finally {f.db.close();}
});

test('unlinked providers and provider outages cannot delete an account', async () => {
  for (const mode of ['unlinked', 'unavailable', 'invalid', 'empty-profile']) {
    const f = fixture({fetchLineProfile: async () => {
      if (mode === 'empty-profile') return {};
      throw Object.assign(new Error('secret provider response'), {code: mode === 'unavailable' ? 'line_login_unavailable' : 'invalid_social_token'});
    }});
    try {
      if (mode === 'unlinked') f.db.exec("DELETE FROM user_auth_identities WHERE user_id=1 AND provider='line'");
      await assert.rejects(f.delete({password: undefined, lineAccessToken: 'line-token-one'}),
        {code: mode === 'unavailable' ? 'line_login_unavailable' : 'reauthentication_required'});
      assert.ok(f.user(1));
    } finally {f.db.close();}
  }
});

test('last active admin is protected and suspended admins do not count as replacements', async () => {
  const f = fixture({verifyPassword: async () => true});
  try {
    f.db.exec("UPDATE users SET is_admin=1,account_status='suspended' WHERE id=2");
    await assert.rejects(f.delete({sessionToken: 'session-3'}), {code: 'last_admin'});
    assert.ok(f.user(3));
    f.db.exec("UPDATE users SET is_admin=1 WHERE id=1");
    await f.delete({sessionToken: 'session-3'});
    assert.equal(f.user(3), undefined);
    assert.ok(f.user(1));
  } finally {f.db.close();}
});

test('concurrent admin self deletion leaves one active administrator', async () => {
  const f = fixture({verifyPassword: async () => true});
  try {
    f.db.exec('UPDATE users SET is_admin=1 WHERE id=1');
    const results = await Promise.allSettled([f.delete(), f.delete({sessionToken: 'session-3'})]);
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal(results.find(r => r.status === 'rejected').reason.code, 'last_admin');
    assert.equal(f.db.prepare("SELECT COUNT(*) AS n FROM users WHERE is_admin=1 AND account_status='active'").get().n, 1);
    const first = f.statements[0].sql;
    assert.match(first, /is_admin=TRUE AND account_status='active' ORDER BY id FOR UPDATE/);
  } finally {f.db.close();}
});

test('admin deletion uses the same data and durable media cleanup', async () => {
  const f = fixture();
  try {
    await f.service.adminDelete(f.admin);
    assert.equal(f.user(1), undefined);
    assert.equal(f.count('event_submissions'), 1);
    assert.deepEqual(f.unlinked, [path.join(uploadDir, ownFile)]);
    assert.ok(f.user(3));
  } finally {f.db.close();}
});

test('admin operations recheck current actor session, status and role inside the transaction', async () => {
  for (const update of ["session_token='rotated'", "account_status='suspended'", 'is_admin=0']) {
    for (const operation of ['adminDelete', 'updateAdminAccount']) {
      const f = fixture();
      try {
        f.beforeBegin(() => f.db.exec(`UPDATE users SET ${update} WHERE id=3`));
        await assert.rejects(f.service[operation]({...f.admin, status: 'suspended'}),
          {code: update === 'is_admin=0' ? 'admin_required' : 'authentication_required'});
        assert.equal(f.user(1).account_status, 'active');
        assert.equal(f.unlinked.length, 0);
      } finally {f.db.close();}
    }
  }
});

test('admin endpoints retain all self guards and reject malformed updates', async () => {
  const f = fixture();
  try {
    const actor = {...f.admin, userId: 3};
    await assert.rejects(f.service.adminDelete(actor), {code: 'cannot_delete_self'});
    await assert.rejects(f.service.updateAdminAccount({...actor, status: 'suspended'}), {code: 'cannot_suspend_self'});
    await assert.rejects(f.service.updateAdminAccount({...actor, isAdmin: false}), {code: 'cannot_revoke_self_admin'});
    for (const changes of [{}, {isAdmin: 1}, {isAdmin: false, status: 'active'}]) {
      await assert.rejects(f.service.updateAdminAccount({...f.admin, ...changes}), {code: 'invalid_account_update'});
    }
    await assert.rejects(f.service.updateAdminAccount({...f.admin, status: 'invalid'}), {code: 'invalid_account_status'});
    for (const userId of [null, 0, -1, 1.5, '1 OR 1=1', {}, Number.MAX_SAFE_INTEGER + 1]) {
      await assert.rejects(f.service.adminDelete({...f.admin, userId}), {code: 'invalid_user_id'});
    }
    await assert.rejects(f.service.adminDelete({...f.admin, userId: 999}), {code: 'user_not_found'});
  } finally {f.db.close();}
});

test('suspension revokes the session and push tokens while role changes preserve identity', async () => {
  const f = fixture();
  try {
    await f.service.updateAdminAccount({...f.admin, isAdmin: true});
    assert.equal(f.user(1).is_admin, 1);
    assert.equal(f.user(1).session_token, 'session-1');
    await f.service.updateAdminAccount({...f.admin, isAdmin: false});
    assert.equal(f.user(1).is_admin, 0);
    await f.service.updateAdminAccount({...f.admin, status: 'suspended'});
    assert.equal(f.user(1).session_token, null);
    assert.equal(f.count('device_push_tokens'), 1);
    await f.service.updateAdminAccount({...f.admin, status: 'active'});
    assert.equal(f.user(1).account_status, 'active');
    assert.equal(f.user(1).session_token, null);
  } finally {f.db.close();}
});

test('admin revocation or suspension racing self deletion cannot remove the final active admin', async () => {
  for (const changes of [{isAdmin: false}, {status: 'suspended'}]) {
    for (const deletionFirst of [true, false]) {
      const f = fixture();
      try {
        f.db.exec('UPDATE users SET is_admin=1 WHERE id=1');
        const deletion = () => f.delete();
        const update = () => f.service.updateAdminAccount({userId: 3, adminUserId: 1, sessionToken: 'session-1', ...changes});
        const results = await Promise.allSettled(deletionFirst ? [deletion(), update()] : [update(), deletion()]);
        assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
        assert.equal(results.find(r => r.status === 'rejected').reason.code,
          deletionFirst ? 'authentication_required' : 'last_admin');
        assert.equal(f.db.prepare("SELECT COUNT(*) AS n FROM users WHERE is_admin=1 AND account_status='active'").get().n, 1);
      } finally {f.db.close();}
    }
  }
});

test('SQL or report cleanup failure rolls back all user data and pending media work', async () => {
  for (const mode of ['sql', 'reports', 'commit']) {
    const f = fixture({deleteAdditionalUserData: async db => {
      await db.execute('DELETE FROM deletion_hook_reports WHERE subject_user_id=?', [1]);
      if (mode === 'reports') throw new Error('report cleanup failed');
    }});
    try {
      f.db.exec('CREATE TABLE deletion_hook_reports (subject_user_id INTEGER, snapshot TEXT)');
      f.db.exec("INSERT INTO deletion_hook_reports VALUES (1,'personal data'),(2,'other data')");
      if (mode === 'sql') f.failSql(sql => sql === 'DELETE FROM users WHERE id=?');
      if (mode === 'commit') f.failCommit();
      await assert.rejects(f.delete());
      assert.ok(f.user(1));
      assert.equal(f.count('deletion_hook_reports'), 2);
      assert.equal(f.count('event_submissions'), 2);
      assert.equal(f.count('account_upload_cleanup'), 0);
      assert.equal(f.unlinked.length, 0);
    } finally {f.db.close();}
  }
});

test('main can scrub reports and legal acceptance in the same deletion transaction', async () => {
  const f = fixture({deleteAdditionalUserData: async (db, userId) => {
    await db.execute('DELETE FROM deletion_hook_reports WHERE subject_user_id=?', [userId]);
    await db.execute('DELETE FROM deletion_hook_legal WHERE user_id=?', [userId]);
  }});
  try {
    f.db.exec(`CREATE TABLE deletion_hook_reports (subject_user_id INTEGER, snapshot TEXT);
      CREATE TABLE deletion_hook_legal (user_id INTEGER);
      INSERT INTO deletion_hook_reports VALUES (1,'mine'),(2,'other'); INSERT INTO deletion_hook_legal VALUES (1),(2)`);
    await f.delete();
    assert.equal(f.count('deletion_hook_reports'), 1);
    assert.equal(f.count('deletion_hook_legal'), 1);
  } finally {f.db.close();}
});

test('cleanup failures keep deletion successful and durable retries survive a new service', async () => {
  const f = fixture();
  try {
    f.failDisk(true);
    await f.delete();
    assert.equal(f.user(1), undefined);
    assert.equal(f.db.prepare('SELECT user_id FROM account_uploads WHERE file_name=?').get(ownFile).user_id, null);
    assert.equal(f.db.prepare('SELECT attempts FROM account_upload_cleanup').get().attempts, 1);
    f.failDisk(false);
    const restarted = createAccountDeletionService(f.pool, f.serviceOptions);
    assert.deepEqual(await restarted.cleanupUploads(), {cleaned: 1, failed: 0});
    assert.deepEqual(await restarted.cleanupUploads(), {cleaned: 0, failed: 0});
    assert.equal(f.files.has(path.join(uploadDir, otherFile)), true);
  } finally {f.db.close();}
});

test('missing files are successful cleanup and failed cleanup commits can be retried', async () => {
  const f = fixture();
  try {
    f.failDisk(true);
    await f.delete();
    f.failDisk(false);
    f.failCommit();
    assert.deepEqual(await f.service.cleanupUploads(), {cleaned: 0, failed: 1});
    assert.equal(f.files.has(path.join(uploadDir, ownFile)), false);
    assert.equal(f.count('account_upload_cleanup'), 1);
    assert.deepEqual(await f.service.cleanupUploads(), {cleaned: 1, failed: 0});
    assert.equal(f.count('account_upload_cleanup'), 0);
  } finally {f.db.close();}
});

test('concurrent cleanup workers do not unlink or count the same file twice', async () => {
  const f = fixture();
  try {
    f.failDisk(true);
    await f.delete();
    f.failDisk(false);
    f.unlinked.length = 0;
    const results = await Promise.all([f.service.cleanupUploads(), f.service.cleanupUploads()]);
    assert.equal(results.reduce((n, result) => n + result.cleaned, 0), 1);
    assert.equal(f.unlinked.length, 1);
    assert.equal(f.count('account_upload_cleanup'), 0);
  } finally {f.db.close();}
});

test('cleanup cannot unlink active ownership, untracked files, URL paths or traversal', async () => {
  const f = fixture();
  try {
    for (const name of [otherFile, orphanFile, '../other.jpg', `/uploads/${ownFile}`, 'https://evil.invalid/file.png',
      ownFile.toUpperCase(), 'not-a-uuid.png']) {
      f.db.prepare('INSERT INTO account_upload_cleanup (file_name) VALUES (?)').run(name);
      if (name !== otherFile) f.db.prepare('INSERT INTO account_uploads (file_name,user_id) VALUES (?,NULL)').run(name);
    }
    f.db.prepare('DELETE FROM account_uploads WHERE file_name=?').run(orphanFile);
    assert.deepEqual(await f.service.cleanupUploads(), {cleaned: 0, failed: 7});
    assert.deepEqual(f.unlinked, []);
    assert.equal(f.files.has(path.join(uploadDir, otherFile)), true);
  } finally {f.db.close();}
});

test('unreferenced legacy files cannot be claimed by account deletion', async () => {
  const f = fixture();
  try {
    f.db.prepare('DELETE FROM account_uploads WHERE file_name=?').run(ownFile);
    await f.delete();
    assert.equal(f.unlinked.length, 0);
    assert.equal(f.files.size, 2);
  } finally {f.db.close();}
});

test('untracked legacy references require ownership review even when only one account uses the URL', async () => {
  const f = fixture();
  const avatar = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd.jpg';
  const photo = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee.png';
  const outfit = 'ffffffff-ffff-4fff-8fff-ffffffffffff.webp';
  try {
    f.db.prepare('UPDATE users SET avatar_url=?,other_photo_urls_json=? WHERE id=1')
      .run(`https://coscircle.invalid/uploads/${avatar}`, JSON.stringify([
        `https://34.187.168.222/uploads/${photo}`, `https://coscircle.invalid/uploads/${avatar}`]));
    f.db.prepare('UPDATE event_bookings SET outfit_image_url=? WHERE user_id=1')
      .run(`https://coscircle.invalid/uploads/${outfit}`);
    for (const file of [avatar, photo, outfit]) f.files.set(path.join(uploadDir, file), 'legacy image');
    const result = await f.delete();
    assert.deepEqual(result, {legacyUploads: {adopted: 0, review: 3, unreadableReferences: 0}});
    assert.deepEqual(f.unlinked, [path.join(uploadDir, ownFile)]);
    assert.equal(f.files.size, 4);
    assert.equal(f.count('account_legacy_upload_review'), 3);
  } finally {f.db.close();}
});

test('query and fragment variants cannot let one user claim another users legacy image', async () => {
  const f = fixture();
  try {
    f.db.prepare('DELETE FROM account_uploads WHERE file_name=?').run(otherFile);
    f.db.prepare('UPDATE users SET avatar_url=? WHERE id=2').run(`https://coscircle.invalid/uploads/${otherFile}?v=1#preview`);
    const result = await f.delete();
    assert.equal(result.legacyUploads.adopted,0);
    assert.equal(result.legacyUploads.review,1);
    assert.equal(f.files.has(path.join(uploadDir,otherFile)),true);
    assert.ok(f.user(2));
    assert.equal(f.db.prepare('SELECT reason FROM account_legacy_upload_review').get().reason,'shared_references');
  } finally { f.db.close(); }
});

test('ambiguous legacy media is retained with a durable review record and a returned report', async () => {
  const f = fixture();
  try {
    f.files.set(path.join(uploadDir, orphanFile), 'shared legacy image');
    f.db.prepare('UPDATE users SET avatar_url=? WHERE id=1').run(`https://coscircle.invalid/uploads/${orphanFile}`);
    f.db.prepare('UPDATE event_bookings SET outfit_image_url=? WHERE user_id=2').run(`https://34.187.168.222/uploads/${orphanFile}`);
    const result = await f.delete();
    assert.deepEqual(result.legacyUploads, {adopted: 0, review: 1, unreadableReferences: 0});
    assert.equal(f.files.get(path.join(uploadDir, orphanFile)), 'shared legacy image');
    assert.equal(f.db.prepare('SELECT reason FROM account_legacy_upload_review').get().reason, 'shared_references');
    assert.equal(f.db.prepare('SELECT outfit_image_url FROM event_bookings WHERE user_id=2').get().outfit_image_url,
      `https://34.187.168.222/uploads/${orphanFile}`);
  } finally {f.db.close();}
});

test('known ownership redacts copied local references from other users before unlinking', async () => {
  const f = fixture();
  try {
    const copied = `https://coscircle.invalid/uploads/${ownFile}`;
    const preserved = `https://coscircle.invalid/uploads/${otherFile}`;
    const external = `https://external.invalid/uploads/${ownFile}`;
    f.db.prepare('UPDATE users SET avatar_url=?,other_photo_urls_json=? WHERE id=2')
      .run(copied, JSON.stringify([copied, preserved, external]));
    f.db.prepare('UPDATE event_bookings SET outfit_image_url=? WHERE user_id=2').run(copied);
    const unlink = f.fileSystem.unlink;
    f.fileSystem.unlink = async file => {
      assert.equal(f.user(2).avatar_url, null);
      assert.deepEqual(JSON.parse(f.user(2).other_photo_urls_json), [preserved, external]);
      assert.equal(f.db.prepare('SELECT outfit_image_url FROM event_bookings WHERE user_id=2').get().outfit_image_url, null);
      return unlink(file);
    };
    await f.delete();
    assert.equal(f.files.get(path.join(uploadDir, otherFile)), 'other');
    assert.equal(f.user(2).nickname, 'Other');
  } finally {f.db.close();}
});

test('legacy references cannot steal an upload already owned by another account', async () => {
  const f = fixture();
  try {
    f.db.prepare('UPDATE users SET avatar_url=?,other_photo_urls_json=? WHERE id=1')
      .run(`https://coscircle.invalid/uploads/${otherFile}`, JSON.stringify([`https://34.187.168.222/uploads/${otherFile}`]));
    const result = await f.delete();
    assert.equal(result.legacyUploads.adopted, 0);
    assert.equal(f.files.get(path.join(uploadDir, otherFile)), 'other');
    assert.equal(f.db.prepare('SELECT user_id FROM account_uploads WHERE file_name=?').get(otherFile).user_id, 2);
  } finally {f.db.close();}
});

test('legacy parsing rejects external origins, userinfo, query, fragments and normalized traversal', async () => {
  const f = fixture();
  try {
    const invalid = [
      `https://external.invalid/uploads/${orphanFile}`,
      `https://coscircle.invalid.evil.invalid/uploads/${orphanFile}`,
      `https://user:password@coscircle.invalid/uploads/${orphanFile}`,
      `https://coscircle.invalid/uploads/${orphanFile}?token=private`,
      `https://coscircle.invalid/uploads/${orphanFile}#fragment`,
      `https://coscircle.invalid/uploads/x/../${orphanFile}`,
      `https://coscircle.invalid/uploads/%2e%2e/uploads/${orphanFile}`,
      `https://coscircle.invalid/uploads/%63${orphanFile.slice(1)}`,
      `https://coscircle.invalid\\uploads\\${orphanFile}`,
      `/uploads/${orphanFile}`,
      `http://coscircle.invalid/uploads/${orphanFile}`,
      `https://coscircle.invalid:8443/uploads/${orphanFile}`,
    ];
    f.db.prepare('UPDATE users SET avatar_url=NULL,other_photo_urls_json=? WHERE id=1').run(JSON.stringify(invalid));
    f.db.prepare('UPDATE event_bookings SET outfit_image_url=NULL WHERE user_id=1').run();
    f.files.set(path.join(uploadDir, orphanFile), 'unowned image');
    const result = await f.delete();
    assert.equal(result.legacyUploads.adopted, 0);
    assert.equal(f.files.get(path.join(uploadDir, orphanFile)), 'unowned image');
    assert.deepEqual(f.unlinked, [path.join(uploadDir, ownFile)]);
  } finally {f.db.close();}
});

test('unreadable photo lists prevent legacy ownership inference and remain visible in the report', async () => {
  for (const invalid of ['{bad-json', '{}', '["url",1]']) {
    const f = fixture();
    try {
      f.db.prepare('UPDATE users SET avatar_url=? WHERE id=1').run(`https://coscircle.invalid/uploads/${orphanFile}`);
      f.db.prepare('UPDATE users SET other_photo_urls_json=? WHERE id=2').run(invalid);
      f.files.set(path.join(uploadDir, orphanFile), 'unowned image');
      const result = await f.delete();
      assert.deepEqual(result.legacyUploads, {adopted: 0, review: 1, unreadableReferences: 1});
      assert.equal(f.db.prepare('SELECT reason FROM account_legacy_upload_review').get().reason, 'unreadable_references');
      assert.equal(f.files.get(path.join(uploadDir, orphanFile)), 'unowned image');
    } finally {f.db.close();}
  }
});

test('legacy adoption and copied-reference redaction roll back if account deletion fails', async () => {
  const f = fixture();
  try {
    const copied = `https://coscircle.invalid/uploads/${ownFile}`;
    f.db.prepare('UPDATE users SET avatar_url=? WHERE id=1').run(`https://coscircle.invalid/uploads/${orphanFile}`);
    f.db.prepare('UPDATE users SET avatar_url=? WHERE id=2').run(copied);
    f.failSql(sql => sql === 'DELETE FROM users WHERE id=?');
    await assert.rejects(f.delete());
    assert.equal(f.user(2).avatar_url, copied);
    assert.equal(f.db.prepare('SELECT * FROM account_uploads WHERE file_name=?').get(orphanFile), undefined);
    assert.equal(f.count('account_upload_cleanup'), 0);
    assert.equal(f.unlinked.length, 0);
  } finally {f.db.close();}
});

test('configured public upload origins reject credentials, paths and non-HTTPS URLs', () => {
  for (const origin of ['http://coscircle.invalid', 'https://user@coscircle.invalid',
    'https://coscircle.invalid/uploads', 'https://coscircle.invalid?query=1', 'https://coscircle.invalid/#fragment']) {
    assert.throws(() => createAccountDeletionService({}, {publicUploadOrigins: [origin]}));
  }
});

test('uploads commit ownership before writing and account deletion cleans unused uploads', async () => {
  const f = fixture();
  try {
    const original = f.fileSystem.writeFile;
    f.fileSystem.writeFile = async (...args) => {
      assert.equal(f.commits(), 1);
      assert.equal(f.count('account_uploads'), 3);
      return original(...args);
    };
    const {fileName} = await f.service.storeUpload({userId: 1, bytes: Buffer.from('new image'), extension: 'png'});
    assert.match(fileName, /^[a-f0-9-]{36}\.png$/);
    assert.equal(f.files.get(path.join(uploadDir, fileName)), 'new image');
    await f.delete();
    assert.equal(f.files.has(path.join(uploadDir, fileName)), false);
    assert.equal(f.files.size, 1);
  } finally {f.db.close();}
});

test('an upload whose final commit fails retains durable ownership for later cleanup', async () => {
  const f = fixture();
  try {
    const original = f.fileSystem.writeFile;
    f.fileSystem.writeFile = async (...args) => {await original(...args); f.failCommit();};
    await assert.rejects(f.service.storeUpload({userId: 1, bytes: Buffer.from('image'), extension: 'webp'}));
    assert.equal(f.count('account_uploads'), 3);
    assert.equal(f.files.size, 3);
    await f.delete();
    assert.equal(f.files.size, 1);
  } finally {f.db.close();}
});

test('account deletion between upload reservation and disk writing never creates a late orphan', async () => {
  const f = fixture();
  try {
    const getConnection = f.pool.getConnection;
    let acquisitions = 0;
    f.pool.getConnection = async () => {
      acquisitions++;
      if (acquisitions === 2) await f.delete();
      return getConnection();
    };
    await assert.rejects(f.service.storeUpload({userId: 1, bytes: Buffer.from('image'), extension: 'webp'}),
      {code: 'authentication_required'});
    assert.equal(f.user(1), undefined);
    assert.equal(f.files.size, 1);
    assert.equal(f.count('account_uploads'), 1);
    assert.equal(f.count('account_upload_cleanup'), 0);
  } finally {f.db.close();}
});

test('upload collisions release ownership without unlinking the pre-existing file', async () => {
  const f = fixture();
  try {
    let collisionName;
    f.fileSystem.writeFile = async file => {
      collisionName = path.basename(file);
      f.files.set(file, 'pre-existing file');
      throw Object.assign(new Error('exists'), {code: 'EEXIST'});
    };
    await assert.rejects(f.service.storeUpload({userId: 1, bytes: Buffer.from('image'), extension: 'jpg'}), {code: 'EEXIST'});
    assert.equal(f.db.prepare('SELECT * FROM account_uploads WHERE file_name=?').get(collisionName), undefined);
    await f.delete();
    assert.equal(f.files.get(path.join(uploadDir, collisionName)), 'pre-existing file');
  } finally {f.db.close();}
});

test('upload validation, missing users and suspended users never write a file', async () => {
  const f = fixture();
  try {
    for (const extension of ['../png', 'gif', {}, 'PNG']) {
      await assert.rejects(f.service.storeUpload({userId: 1, bytes: Buffer.from('image'), extension}));
    }
    for (const bytes of [Buffer.alloc(0), 'image']) {
      await assert.rejects(f.service.storeUpload({userId: 1, bytes, extension: 'png'}));
    }
    f.db.exec("UPDATE users SET account_status='suspended' WHERE id=1");
    for (const userId of [1, 999]) {
      await assert.rejects(f.service.storeUpload({userId, bytes: Buffer.from('image'), extension: 'png'}), {code: 'authentication_required'});
    }
    assert.equal(f.files.size, 2);
    assert.equal(f.count('account_uploads'), 2);
  } finally {f.db.close();}
});

function response() {
  return {headers: {}, set(name, value) {this.headers[name] = value; return this;},
    status(code) {this.code = code; return this;}, json(body) {this.body = body; return this;},
    end() {this.ended = true; return this;}};
}

test('route returns 204 and forwards only credentials and the bearer token, never body or middleware user IDs', async () => {
  const routes = new Map();
  let actual;
  registerAccountDeletionRoutes({post: (name, handler) => routes.set(name, handler)}, {
    deleteAccount: async input => {actual = input;},
  });
  const res = response();
  await routes.get('/api/me/delete-account')({get: () => 'Bearer session-1', userId: 999,
    body: {userId: 2, sessionToken: 'forged', confirmation: 'DELETE', password: 'correct'}}, res);
  assert.equal(res.code, 204);
  assert.equal(res.ended, true);
  assert.equal(res.body, undefined);
  assert.equal(res.headers['Cache-Control'], 'no-store');
  assert.deepEqual(actual, {sessionToken: 'session-1', confirmation: 'DELETE', password: 'correct', lineAccessToken: undefined});
});

test('route enforces production HTTPS and sanitizes unknown errors', async () => {
  let handler;
  let called = false;
  const service = {deleteAccount: async () => {called = true; throw new Error('password=session-secret SQL');}};
  registerAccountDeletionRoutes({post: (name, work) => {handler = work;}}, service, {production: true});
  const insecure = response();
  await handler({}, insecure);
  assert.equal(insecure.code, 426);
  assert.equal(called, false);
  const secure = response();
  await handler({secure: true, get: () => 'Bearer session-1', body: {}}, secure);
  assert.equal(secure.code, 503);
  assert.deepEqual(secure.body, {error: 'account_deletion_unavailable'});
});

test('route reports authentication errors without accepting body tokens or dev user middleware', async () => {
  const f = fixture();
  try {
    let handler;
    registerAccountDeletionRoutes({post: (name, work) => {handler = work;}}, f.service);
    const res = response();
    await handler({get: () => undefined, userId: 1,
      body: {sessionToken: 'session-1', confirmation: 'DELETE', password: 'correct'}}, res);
    assert.equal(res.code, 401);
    assert.deepEqual(res.body, {error: 'authentication_required'});
    assert.ok(f.user(1));
  } finally {f.db.close();}
});

test('migration and exported startup table definitions are identical', async () => {
  const migration = readFileSync(new URL('../db/migrate_account_deletion.sql', import.meta.url), 'utf8');
  const normalize = sql => sql.replace(/\s+/g, ' ').trim();
  assert.deepEqual(migration.split(';').map(normalize).filter(Boolean), accountDeletionTableSql.map(normalize));
  const executed = [];
  await ensureAccountDeletionTables({execute: async sql => {executed.push(sql);}});
  assert.deepEqual(executed, accountDeletionTableSql);
});
