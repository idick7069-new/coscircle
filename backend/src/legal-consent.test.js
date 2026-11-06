import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {createLegalService, registerLegalRoutes, requireLegalAcceptance,
  LEGAL_VERSION, legalConsentTableSql} from './legal-consent.js';

const read = path => readFileSync(new URL(path, import.meta.url), 'utf8');

function fixture(t) {
  const db = new DatabaseSync(':memory:');
  t.after(() => db.close());
  db.exec(`PRAGMA foreign_keys = ON;
    CREATE TABLE users (id INTEGER PRIMARY KEY, session_token TEXT, account_status TEXT);
    CREATE TABLE user_legal_consents (user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
      version TEXT NOT NULL, accepted_at TEXT DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(user_id,version));
    INSERT INTO users VALUES (1,'session-a','active'),(2,'session-b','active'),(3,'suspended','suspended');`);
  const pool = {execute: async (sql, params) => {
    sql = sql.replace('ON DUPLICATE KEY UPDATE user_id = user_legal_consents.user_id',
      'ON CONFLICT(user_id,version) DO NOTHING');
    const statement = db.prepare(sql);
    if (sql.trim().startsWith('SELECT')) return [statement.all(...params)];
    return [{affectedRows: statement.run(...params).changes}];
  }};
  return {db, service: createLegalService(pool)};
}

const acceptance = {version: LEGAL_VERSION, accepted: true};

test('GET is read-only; explicit acceptance is versioned and separate for every account', async t => {
  const {db, service} = fixture(t);
  assert.deepEqual(await service.status(1, 'session-a'), {version: LEGAL_VERSION, accepted: false});
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM user_legal_consents').get().n, 0);
  assert.deepEqual(await service.accept(1, acceptance, 'session-a'), acceptance);
  assert.deepEqual(await service.status(2, 'session-b'), {version: LEGAL_VERSION, accepted: false});
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM user_legal_consents').get().n, 1);
});

test('retries preserve the first acceptance timestamp and old versions do not satisfy the gate', async t => {
  const {db, service} = fixture(t);
  db.prepare('INSERT INTO user_legal_consents VALUES (?,?,?)').run(1, '2025-01-01', 'old');
  assert.equal((await service.status(1, 'session-a')).accepted, false);
  await service.accept(1, acceptance, 'session-a');
  db.prepare('UPDATE user_legal_consents SET accepted_at=? WHERE version=?').run('first', LEGAL_VERSION);
  await service.accept(1, acceptance, 'session-a');
  assert.equal(db.prepare('SELECT accepted_at FROM user_legal_consents WHERE version=?').get(LEGAL_VERSION).accepted_at, 'first');
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM user_legal_consents').get().n, 2);
});

test('missing, implicit, false, numeric and stale consent never writes', async t => {
  const {db, service} = fixture(t);
  for (const body of [undefined, null, [], {}, {version: LEGAL_VERSION},
    {version: LEGAL_VERSION, accepted: false}, {version: LEGAL_VERSION, accepted: 1},
    {version: LEGAL_VERSION, accepted: 'true'}, {accepted: true, version: 20261028}]) {
    await assert.rejects(service.accept(1, body, 'session-a'), {code: 'invalid_legal_acceptance', status: 400});
  }
  await assert.rejects(service.accept(1, {version: '2025-01-01', accepted: true}, 'session-a'),
    {code: 'legal_version_mismatch', status: 409});
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM user_legal_consents').get().n, 0);
});

test('revoked sessions, cross-account tokens, missing and suspended accounts cannot read or accept', async t => {
  const {db, service} = fixture(t);
  for (const [userId, token] of [[1, 'session-b'], [1, 'revoked'], [3, 'suspended'], [99, 'unknown'],
    [undefined, 'session-a'], [0, 'session-a'], [1, ''], ['1 OR 1=1', 'session-a']]) {
    await assert.rejects(service.status(userId, token), {code: 'authentication_required', status: 401});
    await assert.rejects(service.accept(userId, acceptance, token), {code: 'authentication_required', status: 401});
  }
  await service.accept(1, acceptance, 'session-a');
  db.exec("UPDATE users SET session_token='replacement' WHERE id=1");
  await assert.rejects(service.status(1, 'session-a'), {code: 'authentication_required'});
  assert.equal((await service.status(1, 'replacement')).accepted, true);
  db.exec('DELETE FROM users WHERE id=1');
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM user_legal_consents').get().n, 0);
});

function response() {
  return {headers: {}, code: 200,
    set(name, value) {this.headers[name] = value; return this;},
    status(code) {this.code = code; return this;},
    json(body) {this.body = body; return this;},
  };
}

const request = (userId = 1, token = 'session-a', body) =>
  ({userId, body, get: name => name === 'authorization' ? `Bearer ${token}` : undefined});

test('routes expose only authenticated GET and explicit POST, with no-store responses', async t => {
  const {service} = fixture(t);
  const routes = new Map();
  registerLegalRoutes({get: (path, handler) => routes.set(`GET ${path}`, handler),
    post: (path, handler) => routes.set(`POST ${path}`, handler)}, service);
  assert.deepEqual([...routes.keys()], ['GET /api/me/legal', 'POST /api/me/legal']);
  const next = error => {throw error;};
  for (const [method, body, expectedCode, expectedAccepted] of [
    ['GET', undefined, 200, false], ['POST', {}, 400, undefined],
    ['POST', {version: 'old', accepted: true}, 409, undefined], ['POST', acceptance, 200, true],
  ]) {
    const res = response();
    await routes.get(`${method} /api/me/legal`)(request(1, 'session-a', body), res, next);
    assert.equal(res.headers['Cache-Control'], 'no-store');
    assert.equal(res.code, expectedCode);
    assert.equal(res.body.version, LEGAL_VERSION);
    assert.equal(res.body.accepted, expectedAccepted);
  }
  const res = response();
  await routes.get('GET /api/me/legal')({userId: 1, get: () => undefined}, res, next);
  assert.equal(res.code, 401);
});

test('UGC middleware rejects missing consent and stale sessions, and fails closed on database errors', async t => {
  const {service} = fixture(t);
  const gate = requireLegalAcceptance(service);
  let passed = 0;
  const next = error => {assert.equal(error, undefined); passed++;};
  const rejected = response();
  await gate(request(), rejected, next);
  assert.equal(passed, 0);
  assert.equal(rejected.code, 403);
  assert.deepEqual(rejected.body, {error: 'legal_acceptance_required', version: LEGAL_VERSION});
  await service.accept(1, acceptance, 'session-a');
  await gate(request(), response(), next);
  assert.equal(passed, 1);
  const stale = response();
  await gate(request(1, 'session-b'), stale, next);
  assert.equal(stale.code, 401);
  assert.equal(passed, 1);
  const failure = new Error('database unavailable');
  const broken = requireLegalAcceptance(createLegalService({execute: async () => {throw failure;}}));
  let forwarded;
  await broken(request(), response(), error => {forwarded = error;});
  assert.equal(forwarded, failure);
});

test('manual migration and exported DDL agree, with per-account cascade and no automatic creation', () => {
  assert.equal(read('../db/migrate_legal_consent.sql').trim(), `${legalConsentTableSql};`);
  assert.match(legalConsentTableSql, /PRIMARY KEY \(user_id, version\)/);
  assert.match(legalConsentTableSql, /REFERENCES users\(id\) ON DELETE CASCADE/);
});

test('offline Flutter legal paragraphs exactly match both public documents', () => {
  const dart = read('../../lib/features/safety/presentation/legal_page.dart');
  for (const [document, start, end] of [
    ['privacy', 'const _privacySections = [', 'const _termsSections = ['],
    ['terms', 'const _termsSections = [', 'class LegalPage'],
  ]) {
    const part = dart.split(start)[1].split(end)[0];
    const offline = [...part.matchAll(/_LegalSection\('([^']+)', \[([\s\S]*?)\]\)/g)]
      .map(match => [match[1], ...[...match[2].matchAll(/'([^']*)'/g)].map(item => item[1])]);
    const web = read(`../../web/official/${document}.html`);
    const published = [...web.matchAll(/<section data-legal-section[^>]*>([\s\S]*?)<\/section>/g)]
      .map(match => [...match[1].matchAll(/<(?:h2|p)>([\s\S]*?)<\/(?:h2|p)>/g)].map(item => item[1]));
    assert.equal(offline.length, 9);
    assert.deepEqual(offline, published);
    assert.match(web, /2026-10-28/);
  }
});

function browserFixture() {
  const ids = ['login-form', 'delete-form', 'email', 'login-password', 'delete-password', 'confirmation',
    'understood', 'login-button', 'delete-button', 'cancel-button', 'status', 'done', 'account-label',
    'delete-title', 'done-title'];
  const elements = Object.fromEntries(ids.map(id => [id, {
    value: '', checked: false, disabled: false, hidden: false, textContent: '', dataset: {}, events: {},
    addEventListener(event, handler) {this.events[event] = handler;},
    setAttribute() {}, reportValidity: () => true, focus() {},
  }]));
  elements['login-form'].reset = () => {
    elements.email.value = '';
    elements['login-password'].value = '';
  };
  elements['delete-form'].reset = () => {
    elements['delete-password'].value = '';
    elements.confirmation.value = '';
    elements.understood.checked = false;
  };
  const events = {};
  const calls = [];
  const replies = [];
  const context = vm.createContext({document: {getElementById: id => elements[id]},
    window: {addEventListener: (name, handler) => {events[name] = handler;}},
    location: {protocol: 'https:'}, AbortController, setTimeout, clearTimeout,
    fetch: async (path, options) => {
      calls.push({path, options});
      const reply = replies.shift();
      if (reply instanceof Error) throw reply;
      if (typeof reply === 'function') return reply();
      assert.ok(reply, 'Unexpected request');
      return {status: reply.status, ok: reply.status >= 200 && reply.status < 300,
        json: async () => reply.data};
    },
  });
  vm.runInContext(read('../../web/official/delete-account.js'), context);
  const fire = (id, type = 'submit') => elements[id].events[type]({preventDefault() {}});
  const login = async () => {
    elements.email.value = 'Owner@example.invalid';
    elements['login-password'].value = 'login-password';
    replies.push({status: 200, data: {token: 'session-a', user: {nickname: '<img src=x onerror=alert(1)>'}}});
    await fire('login-form');
  };
  return {elements, events, calls, replies, fire, login, context};
}

test('public deletion never sends on load or login and requires a separate explicit authenticated POST', async () => {
  const f = browserFixture();
  const el = f.elements;
  assert.equal(f.calls.length, 0);
  await f.login();
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].path, '/api/auth/login');
  assert.equal(el['delete-form'].hidden, false);
  assert.equal(el.understood.checked, false);
  assert.match(el['account-label'].textContent, /<img src=x onerror=alert\(1\)>/);
  await f.fire('delete-form');
  assert.equal(f.calls.length, 1);
  el['delete-password'].value = 'reentered-password';
  el.confirmation.value = 'delete';
  el.understood.checked = true;
  await f.fire('delete-form');
  assert.equal(f.calls.length, 1);
  el.confirmation.value = 'DELETE';
  f.replies.push({status: 204});
  await f.fire('delete-form');
  assert.equal(f.calls.length, 2);
  const {path, options} = f.calls[1];
  assert.equal(path, '/api/me/delete-account');
  assert.equal(options.method, 'POST');
  assert.equal(options.headers.Authorization, 'Bearer session-a');
  assert.deepEqual(JSON.parse(options.body), {confirmation: 'DELETE', password: 'reentered-password'});
  assert.equal(options.credentials, 'omit');
  assert.equal(options.referrerPolicy, 'no-referrer');
  assert.equal(options.redirect, 'error');
  assert.equal(options.mode, 'same-origin');
  assert.equal(el.done.hidden, false);
  assert.equal(el['delete-password'].value, '');
  await f.fire('delete-form');
  assert.equal(f.calls.length, 2);
});

test('cancel, page exit and failed login cannot leave a reusable deletion session', async () => {
  for (const mode of ['cancel', 'pagehide', 'login-failure']) {
    const f = browserFixture();
    if (mode === 'login-failure') {
      f.replies.push({status: 401, data: {error: 'invalid_credentials'}});
      await f.fire('login-form');
    } else {
      await f.login();
      if (mode === 'cancel') f.fire('cancel-button', 'click');
      else f.events.pagehide();
    }
    f.elements.confirmation.value = 'DELETE';
    f.elements['delete-password'].value = 'password';
    f.elements.understood.checked = true;
    await f.fire('delete-form');
    assert.equal(f.calls.length, 1);
    assert.equal(f.elements['login-form'].hidden, false);
  }
});

test('uncertain deletion clears the session and cannot claim success or automatically retry', async () => {
  const f = browserFixture();
  await f.login();
  f.elements.confirmation.value = 'DELETE';
  f.elements['delete-password'].value = 'password';
  f.elements.understood.checked = true;
  f.replies.push(new TypeError('connection lost'));
  await f.fire('delete-form');
  assert.equal(f.calls.length, 2);
  assert.equal(f.elements.done.hidden, true);
  assert.match(f.elements.status.textContent, /尚無法確認刪除結果/);
  await f.fire('delete-form');
  assert.equal(f.calls.length, 2);
});

test('public pages enforce self-only assets, no referrer and no native GET form submission', () => {
  for (const file of ['privacy', 'terms', 'delete-account']) {
    const html = read(`../../web/official/${file}.html`);
    assert.match(html, /name="referrer" content="no-referrer"/);
    assert.match(html, /form-action 'none'/);
    assert.match(html, /default-src 'none'/);
    assert.doesNotMatch(html, /<script(?![^>]*src=)[^>]*>/);
    assert.doesNotMatch(html, /\son[a-z]+=/i);
  }
  const script = read('../../web/official/delete-account.js');
  assert.doesNotMatch(script, /innerHTML|localStorage|sessionStorage|document\.cookie|sendBeacon|console\./);
  const html = read('../../web/official/delete-account.html');
  assert.equal([...html.matchAll(/<form[^>]+method="post"/g)].length, 2);
  assert.doesNotMatch(html, /type="checkbox"[^>]*\schecked/);
});
