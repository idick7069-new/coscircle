import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {createEmailAccountService, registerEmailAccountRoutes} from './email-account-service.js';

function fixture() {
  const db = new DatabaseSync(':memory:');
  db.exec(`CREATE TABLE users (id INTEGER PRIMARY KEY, provider TEXT, account_status TEXT, password_hash TEXT, session_token TEXT);
    CREATE TABLE user_auth_identities (id INTEGER PRIMARY KEY, user_id INTEGER, provider TEXT, provider_user_id TEXT, password_hash TEXT, verified_at TEXT);
    CREATE TABLE email_action_tokens (id INTEGER PRIMARY KEY, identity_id INTEGER, kind TEXT, token_hash TEXT UNIQUE, email_snapshot TEXT,
      created_at_ms INTEGER, expires_at_ms INTEGER, consumed_at_ms INTEGER);
    CREATE TABLE device_push_tokens (user_id INTEGER, token TEXT);
    INSERT INTO users VALUES (1,'email','active','old-hash','old-session'),(2,'line','active',NULL,'line-session');
    INSERT INTO user_auth_identities VALUES (10,1,'email','owner@example.invalid','old-hash',NULL),
      (11,1,'line','LINE-1',NULL,'verified'),(20,2,'line','LINE-2',NULL,'verified');
    INSERT INTO device_push_tokens VALUES (1,'push-1'),(2,'push-2');`);
  const connection = {
    beginTransaction: async () => db.exec('BEGIN'), commit: async () => db.exec('COMMIT'),
    rollback: async () => db.exec('ROLLBACK'), release: () => {},
    execute: async (sql, params = []) => {
      sql = sql.replaceAll(' FOR UPDATE', '').replaceAll('UTC_TIMESTAMP()', 'CURRENT_TIMESTAMP');
      const statement = db.prepare(sql);
      if (sql.trim().startsWith('SELECT')) return [statement.all(...params)];
      const result = statement.run(...params);
      return [{insertId: Number(result.lastInsertRowid), affectedRows: Number(result.changes)}];
    },
  };
  const pool = {...connection, getConnection: async () => connection};
  let time = 1800000000000;
  const sent = [];
  let failure;
  const send = async (kind, options) => {
    sent.push({kind, ...options});
    if (failure) throw Object.assign(new Error('sanitized'), {code: failure});
    return {accepted: true};
  };
  const mail = {status: () => ({enabled: true, configured: true}),
    sendVerification: opts => send('verify-email', opts), sendPasswordReset: opts => send('reset-password', opts),
    sendPasswordChanged: opts => send('changed', opts)};
  const service = createEmailAccountService(pool, {mail, publicAppUrl: 'https://coscircle.app/app',
    now: () => time, hashPassword: async password => `hashed-${password}`});
  const token = () => new URLSearchParams(sent.at(-1).actionUrl.split('?')[1]).get('token');
  return {db, service, sent, token, advance: ms => {time += ms;}, failMail: code => {failure = code;}};
}

test('verification stores only a hash, sends a trusted URL and does not revoke sessions', async () => {
  const f = fixture();
  try {
    await f.service.requestVerification(1);
    const token = f.token();
    const row = f.db.prepare('SELECT * FROM email_action_tokens').get();
    assert.equal(row.token_hash, crypto.createHash('sha256').update(token).digest('hex'));
    assert.notEqual(row.token_hash, token);
    assert.ok(f.sent[0].actionUrl.startsWith('https://coscircle.app/app/#/verify-email?token='));
    assert.equal(row.expires_at_ms - row.created_at_ms, 3600000);
    assert.deepEqual(await f.service.verify(token), {completed: true});
    assert.equal((await f.service.status(1)).verified, true);
    assert.equal(f.db.prepare('SELECT session_token FROM users WHERE id=1').get().session_token, 'old-session');
    await assert.rejects(f.service.verify(token), {code: 'invalid_or_expired_email_link'});
  } finally {f.db.close();}
});

test('reset changes only the target password, revokes sessions/push and all pending links', async () => {
  const f = fixture();
  try {
    await f.service.requestVerification(1);
    const verification = f.token();
    f.advance(61000);
    await f.service.requestReset('owner@example.invalid');
    const token = f.token();
    assert.equal(f.db.prepare("SELECT expires_at_ms-created_at_ms AS lifetime FROM email_action_tokens WHERE kind='reset-password'").get().lifetime, 900000);
    await f.service.reset(token, 'new-password');
    const user = f.db.prepare('SELECT * FROM users WHERE id=1').get();
    assert.equal(user.password_hash, 'hashed-new-password');
    assert.equal(user.session_token, null);
    assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM device_push_tokens WHERE user_id=1').get().n, 0);
    assert.equal(f.db.prepare('SELECT session_token FROM users WHERE id=2').get().session_token, 'line-session');
    assert.equal(f.db.prepare("SELECT provider_user_id FROM user_auth_identities WHERE id=11").get().provider_user_id, 'LINE-1');
    assert.equal(f.sent.at(-1).kind, 'changed');
    await assert.rejects(f.service.reset(token, 'new-password'), {code: 'invalid_or_expired_email_link'});
    await assert.rejects(f.service.verify(verification), {code: 'invalid_or_expired_email_link'});
  } finally {f.db.close();}
});

test('wrong purpose, expired token, changed email and suspended account cannot reset', async () => {
  for (const mode of ['purpose', 'expired', 'email', 'suspended']) {
    const f = fixture();
    try {
      if (mode === 'purpose') await f.service.requestVerification(1);
      else await f.service.requestReset('owner@example.invalid');
      const token = f.token();
      if (mode === 'expired') f.advance(900000);
      if (mode === 'email') f.db.exec("UPDATE user_auth_identities SET provider_user_id='changed@example.invalid' WHERE id=10");
      if (mode === 'suspended') f.db.exec("UPDATE users SET account_status='suspended' WHERE id=1");
      await assert.rejects(f.service.reset(token, 'new-password'), {code: 'invalid_or_expired_email_link'});
      assert.equal(f.db.prepare('SELECT session_token FROM users WHERE id=1').get().session_token, 'old-session');
      assert.equal(f.db.prepare('SELECT password_hash FROM user_auth_identities WHERE id=10').get().password_hash, 'old-hash');
    } finally {f.db.close();}
  }
});

test('unknown and LINE-only accounts never send reset mail or create identities', async () => {
  const f = fixture();
  try {
    assert.deepEqual(await f.service.requestReset('unknown@example.invalid'), {requested: true});
    assert.deepEqual(await f.service.requestVerification(2), {requested: true});
    assert.equal(f.sent.length, 0);
    assert.equal((await f.service.status(2)).email, null);
    assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM user_auth_identities').get().n, 3);
  } finally {f.db.close();}
});

test('per-account cooldown and daily limit survive service instances and do not revoke links', async () => {
  const f = fixture();
  try {
    await f.service.requestReset('owner@example.invalid');
    const original = f.token();
    await f.service.requestReset('owner@example.invalid');
    assert.equal(f.sent.length, 1);
    await assert.rejects(f.service.requestVerification(1), {code: 'email_resend_cooldown'});
    for (let i = 0; i < 5; i++) {f.advance(61000); await f.service.requestReset('owner@example.invalid');}
    f.advance(61000);
    await f.service.requestReset('owner@example.invalid');
    assert.equal(f.sent.length, 6);
    await f.service.reset(original, 'new-password');
  } finally {f.db.close();}
});

test('definitive mail rejection revokes its link; uncertain delivery does not', async () => {
  for (const code of ['mail_provider_rejected', 'mail_delivery_unknown']) {
    const f = fixture();
    try {
      f.failMail(code);
      await assert.rejects(f.service.requestVerification(1), {code: 'account_mail_unavailable'});
      if (code === 'mail_provider_rejected') await assert.rejects(f.service.verify(f.token()), {code: 'invalid_or_expired_email_link'});
      else assert.deepEqual(await f.service.verify(f.token()), {completed: true});
    } finally {f.db.close();}
  }
});

test('malformed token/password fails without changing state', async () => {
  const f = fixture();
  try {
    await f.service.requestReset('owner@example.invalid');
    await assert.rejects(f.service.reset('wrong', 'new-password'), {code: 'invalid_or_expired_email_link'});
    for (const password of ['', 'short', 'x'.repeat(1025)]) {
      await assert.rejects(f.service.reset(f.token(), password), {code: 'invalid_new_password'});
    }
    assert.equal(f.db.prepare('SELECT consumed_at_ms FROM email_action_tokens').get().consumed_at_ms, null);
  } finally {f.db.close();}
});

test('public reset requests respond identically without waiting for account/provider lookups', async () => {
  const routes = new Map();
  let calls = 0;
  registerEmailAccountRoutes({post: (path, handler) => routes.set(path, handler)}, {
    ready: () => {}, requestReset: async () => {calls++;},
  });
  for (const email of ['unknown@example.invalid', 'owner@example.invalid']) {
    const response = {set: () => response, status: status => {response.code = status; return response;},
      json: body => {response.body = body;}};
    await routes.get('/api/auth/forgot-password')({body: {email}}, response);
    assert.equal(response.code, 202);
    assert.deepEqual(response.body, {requested: true});
  }
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls, 2);
});
