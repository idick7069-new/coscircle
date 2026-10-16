import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {linkLineIdentity, ensureAuthIdentities, authIdentitiesTableSql, legacyIdentityBackfillSql, authIdentityUserQuery} from './auth-identities.js';

function fixture({active = true, email = true, existing, own = false, duplicate = false} = {}) {
  const calls = [];
  const db = {
    beginTransaction: async () => calls.push('begin'),
    commit: async () => calls.push('commit'),
    rollback: async () => calls.push('rollback'),
    release: () => calls.push('release'),
    execute: async (sql, params) => {
      calls.push({sql, params});
      if (sql.startsWith('SELECT id, account_status')) return [[{id: 5, accountStatus: active ? 'active' : 'suspended'}]];
      if (sql.includes('SELECT password_hash')) return [email ? [{passwordHash: 'hash'}] : []];
      if (sql.includes('SELECT user_id')) return [existing == null ? [] : [{userId: existing}]];
      if (sql.includes('SELECT id FROM user_auth')) return [own ? [{id: 1}] : []];
      if (sql.startsWith('INSERT')) {
        if (duplicate) throw Object.assign(new Error('duplicate'), {code: 'ER_DUP_ENTRY'});
        return [{insertId: 9}];
      }
      assert.fail(sql);
    },
  };
  return {pool: {getConnection: async () => db}, calls};
}
const options = {userId: 5, lineUserId: 'verified-line-subject', password: 'correct',
  verifyPassword: async (password, hash) => password === 'correct' && hash === 'hash'};

test('Email and bound LINE login resolve the same user; same subject from another provider remains distinct', () => {
  const db = new DatabaseSync(':memory:');
  try {
    db.exec(`CREATE TABLE users (id INTEGER PRIMARY KEY, account_status TEXT);
      CREATE TABLE user_auth_identities (user_id INTEGER, provider TEXT, provider_user_id TEXT, password_hash TEXT,
        UNIQUE(provider, provider_user_id), UNIQUE(user_id, provider));
      INSERT INTO users VALUES (5,'active'),(7,'active');
      INSERT INTO user_auth_identities VALUES (5,'email','qa@example.invalid','hash'),
        (5,'line','LINE-5',NULL),(7,'facebook','LINE-5',NULL);`);
    const query = db.prepare(authIdentityUserQuery);
    assert.equal(query.get('email', 'qa@example.invalid').id, 5);
    assert.equal(query.get('line', 'LINE-5').id, 5);
    assert.equal(query.get('facebook', 'LINE-5').id, 7);
    assert.equal(query.get('line', 'unknown'), undefined);
  } finally {db.close();}
});

test('linking adds one identity to the original user and does not touch sessions or social data', async () => {
  const {pool, calls} = fixture();
  assert.deepEqual(await linkLineIdentity(pool, options), {linked: true});
  assert.ok(calls.includes('commit'));
  const writes = calls.filter((call) => call.sql?.startsWith('INSERT'));
  assert.equal(writes.length, 1);
  assert.deepEqual(writes[0].params, [5, 'verified-line-subject']);
  assert.ok(!calls.some((call) => /^(UPDATE|DELETE)/.test(call.sql ?? '')));
});

test('wrong password and absent email identity cannot bind LINE', async () => {
  for (const config of [{}, {email: false}]) {
    const {pool, calls} = fixture(config);
    await assert.rejects(linkLineIdentity(pool, {...options, password: 'wrong'}), {code: 'reauthentication_required'});
    assert.ok(calls.includes('rollback'));
    assert.ok(!calls.some((call) => call.sql?.startsWith('INSERT')));
  }
});

test('LINE owned by another account is never transferred or merged', async () => {
  const {pool, calls} = fixture({existing: 7});
  await assert.rejects(linkLineIdentity(pool, options), {code: 'line_identity_already_linked'});
  assert.ok(calls.includes('rollback'));
});

test('repeating an already completed binding is idempotent', async () => {
  const {pool, calls} = fixture({existing: 5});
  await linkLineIdentity(pool, options);
  assert.ok(!calls.some((call) => call.sql?.startsWith('INSERT')));
});

test('an existing different LINE, racing duplicate and suspended user are rejected', async () => {
  for (const config of [{own: true}, {duplicate: true}, {active: false}]) {
    const {pool, calls} = fixture(config);
    await assert.rejects(linkLineIdentity(pool, options),
      {code: config.active === false ? 'account_suspended' : 'line_identity_already_linked'});
    assert.ok(calls.includes('rollback'));
    assert.ok(calls.includes('release'));
  }
});

test('migration preserves IDs and does not pretend legacy email was verified', async () => {
  const statements = [];
  await ensureAuthIdentities({execute: async (sql) => statements.push(sql)});
  assert.deepEqual(statements, [authIdentitiesTableSql, legacyIdentityBackfillSql]);
  assert.match(legacyIdentityBackfillSql, /SELECT id, provider, provider_user_id/);
  assert.doesNotMatch(legacyIdentityBackfillSql, /verified_at|UPDATE|DELETE/);
  assert.match(authIdentitiesTableSql, /UNIQUE KEY uniq_auth_provider_subject/);
});
