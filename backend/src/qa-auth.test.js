import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {linkLineIdentity} from './auth-identities.js';
import {normalizeAccountEmail, registerEmailAccountRoutes} from './email-account-service.js';

const source = fs.readFileSync(new URL('./server.js', import.meta.url), 'utf8');
function actualPost(path, dependencies) {
  const start = source.indexOf(`app.post('${path}', `);
  const body = source.indexOf('async (req, res, next) => {', start);
  const end = source.indexOf('\n});', body);
  assert.ok(start >= 0 && body >= start && end > body);
  return vm.runInNewContext(`(${source.slice(body, end + 2)})`, dependencies);
}
function response() {
  return {code: 200, body: null, status(code) {this.code = code; return this;},
    json(body) {this.body = body; return this;}};
}

test('Q04 actual registration rejects malformed email before hashing or DB access', async () => {
  const register = actualPost('/api/auth/register', {
    normalizeAccountEmail, console: {warn() {}},
    hashPassword() {assert.fail('must validate before hashing');},
  });
  const res = response();
  await register({body: {email: 'qa@host', password: 'password'}}, res, error => {throw error;});
  assert.equal(res.code, 400);
  assert.equal(res.body.error, 'invalid_email_or_password');
});

for (const password of ['', 'a'.repeat(1025), 'ordinary-password']) {
  test(`Q03 binding input or LINE token refusal is not a local session 401 (${password.length})`, async () => {
    const bind = actualPost('/api/me/auth-identities/line', {
      isProduction: true,
      fetchLineProfile: async () => {throw Object.assign(new Error('bad LINE token'), {code: 'invalid_social_token', status: 401});},
    });
    const res = response();
    await bind({secure: true, body: {password}}, res, error => {throw error;});
    assert.equal(res.code, 403);
    assert.equal(res.body.error, password.length === 0 || password.length > 1024
      ? 'reauthentication_required' : 'invalid_social_token');
  });
}

test('Q03 a rejected binding password is forbidden without writing an identity', async () => {
  const writes = [];
  const connection = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
    execute: async (sql) => {
      if (sql.startsWith('SELECT id, account_status')) return [[{id: 1, accountStatus: 'active'}]];
      if (sql.includes('SELECT password_hash')) return [[{passwordHash: 'fixture-hash'}]];
      writes.push(sql);
      assert.fail('A rejected password must stop before identity lookup/write');
    },
  };
  await assert.rejects(linkLineIdentity({getConnection: async () => connection}, {
    userId: 1, lineUserId: 'line-subject', password: 'incorrect', verifyPassword: async () => false,
  }), {code: 'reauthentication_required', status: 403});
  assert.deepEqual(writes, []);
});

test('Q04 the shared account email contract rejects unrecoverable addresses', () => {
  for (const value of [null, 12, '', 'qa@host', 'qa @host.test', 'qa@host.test extra',
    '<qa>@host.test', 'qa@@host.test', `${'a'.repeat(182)}@host.test`]) {
    assert.equal(normalizeAccountEmail(value), null, String(value));
  }
  assert.equal(normalizeAccountEmail(' QA+Tag@Host.Test '), 'qa+tag@host.test');
  assert.equal(normalizeAccountEmail(`${'a'.repeat(181)}@host.test`).length, 191);
});

test('Q04 recovery uses the shared predicate before requesting any mail', async () => {
  const routes = new Map();
  let requests = 0;
  registerEmailAccountRoutes({post: (path, handler) => routes.set(path, handler)}, {
    ready: () => {}, requestReset: async () => { requests += 1; },
  });
  const handler = routes.get('/api/auth/forgot-password');
  const response = () => ({code: 200, body: null, set() {}, status(code) {this.code = code; return this;},
    json(body) {this.body = body; return this;}});
  const invalid = response();
  await handler({body: {email: 'qa@host'}}, invalid);
  assert.equal(invalid.code, 400);
  assert.equal(invalid.body.error, 'invalid_email');
  assert.equal(requests, 0);
  const valid = response();
  await handler({body: {email: 'QA@Host.Test'}}, valid);
  assert.equal(valid.code, 202);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(requests, 1);
});
