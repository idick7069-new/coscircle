import assert from 'node:assert/strict';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {listPartnerWorks, listWorkPartners, registerPartnerDiscoveryRoutes} from './partner-discovery.js';

function fixture(t) {
  const db = new DatabaseSync(':memory:');
  t.after(() => db.close());
  db.exec(`CREATE TABLE users(id INTEGER PRIMARY KEY, public_code TEXT, nickname TEXT,
      avatar_url TEXT, bio TEXT, account_status TEXT, email TEXT, session_token TEXT, password_hash TEXT);
    CREATE TABLE works(id INTEGER PRIMARY KEY, name TEXT);
    CREATE TABLE user_pit_works(user_id INTEGER, work_id INTEGER, depth TEXT);
    CREATE TABLE user_blocks(blocker_user_id INTEGER, blocked_user_id INTEGER);
    INSERT INTO users VALUES
      (1,'me','Viewer','','','active','private','secret','hash'),
      (2,'two','Partner',NULL,NULL,'active','private','secret','hash'),
      (3,'three','Blocked','','','active','private','secret','hash'),
      (4,'four','Blocks viewer','','','active','private','secret','hash'),
      (5,'five','Inactive','','','suspended','private','secret','hash'),
      (6,'six','Other work','','Other bio','active','private','secret','hash'),
      (7,NULL,'Null code','','','active','private','secret','hash'),
      (8,'eight','Partner 8','','','active','private','secret','hash'),
      (9,'','Empty code','','','active','private','secret','hash');
    INSERT INTO works VALUES (100,'Alpha'),(110,'Alpha'),(200,'Beta'),(300,'Solo'),
      (400,'Other'),(500,'Unavailable'),(600,'No members'),
      (700,'100% literal'),(710,'100X literal'),(800,'a_b'),(810,'axb'),(900,'bang!'),(910,'bangX');
    INSERT INTO user_pit_works VALUES
      (1,100,'deep'),(1,100,'shallow'),(1,200,'shallow'),(1,300,'deep'),
      (2,100,'deep'),(2,100,'shallow'),(2,200,'deep'),(2,110,'shallow'),
      (3,100,'deep'),(3,500,'deep'),(4,200,'deep'),(4,500,'deep'),
      (5,100,'deep'),(5,500,'deep'),(7,100,'deep'),(7,500,'deep'),
      (9,100,'deep'),(9,500,'deep'),(8,100,'shallow'),
      (6,400,'deep'),(6,700,'deep'),(6,710,'deep'),(6,800,'shallow'),
      (6,810,'shallow'),(6,900,'shallow'),(6,910,'deep');
    INSERT INTO user_blocks VALUES (1,3),(4,1);`);
  const calls = [];
  const pool = {execute: async (sql, params) => {
    calls.push({sql, params});
    return [db.prepare(sql).all(...params)];
  }};
  return {db, pool, calls};
}

test('pagination never advertises offsets beyond the accepted boundary', async () => {
  const rows = [{id: 1, name: 'Work', partnerCount: 1, isMine: 1, userId: 2},
    {id: 2, name: 'More', partnerCount: 1, isMine: 1, userId: 3}];
  const pool = {execute: async (sql) => [sql.includes('SELECT DISTINCT theirs') ? [] : rows]};
  for (const offset of [99999, 100000]) {
    for (const result of [await listPartnerWorks(pool, 1, {offset: String(offset), limit: '1'}),
      await listWorkPartners(pool, 1, '1', {offset: String(offset), limit: '1'})]) {
      assert.equal(result.items.length, 1);
      assert.equal(result.hasMore, offset === 99999);
      assert.equal(result.nextOffset, offset === 99999 ? 100000 : null);
    }
  }
});

test('mine includes zero partners and counts unique eligible other users across both depths', async (t) => {
  const {pool, calls} = fixture(t);
  const result = await listPartnerWorks(pool, 1);
  assert.deepEqual(result, {items: [
    {id: '100', name: 'Alpha', partnerCount: 2, isMine: true},
    {id: '200', name: 'Beta', partnerCount: 1, isMine: true},
    {id: '300', name: 'Solo', partnerCount: 0, isMine: true},
  ], hasMore: false, nextOffset: null});
  assert.equal(calls.length, 1);
});

test('all hides works with only self, unavailable people, or no members and includes unowned works', async (t) => {
  const {pool} = fixture(t);
  const {items} = await listPartnerWorks(pool, 1, {scope: 'all'});
  assert.deepEqual(items.map((item) => item.id), ['700','710','100','110','200','400','800','810','900','910']);
  assert.equal(items.find((item) => item.id === '100').partnerCount, 2);
  assert.deepEqual(items.find((item) => item.id === '400'), {id: '400', name: 'Other', partnerCount: 1, isMine: false});
  assert.deepEqual(items.find((item) => item.id === '110'), {id: '110', name: 'Alpha', partnerCount: 1, isMine: false});
});

test('works pagination uses name then id and returns a truthful final offset', async (t) => {
  const {pool} = fixture(t);
  const first = await listPartnerWorks(pool, 1, {scope: 'all', q: 'Alpha', limit: '1'});
  assert.deepEqual(first, {items: [{id: '100', name: 'Alpha', partnerCount: 2, isMine: true}], hasMore: true, nextOffset: 1});
  assert.deepEqual(await listPartnerWorks(pool, 1, {scope: 'all', q: 'Alpha', limit: '1', offset: '1'}), {
    items: [{id: '110', name: 'Alpha', partnerCount: 1, isMine: false}], hasMore: false, nextOffset: null,
  });
  assert.deepEqual(await listPartnerWorks(pool, 1, {offset: '100000', limit: '50'}), {items: [], hasMore: false, nextOffset: null});
});

test('search treats percent, underscore, escape character and SQL syntax as literal text', async (t) => {
  const {pool, calls} = fixture(t);
  for (const [q, ids] of [['%', ['700']], ['_', ['800']], ['!', ['900']], ["%' OR 1=1 --", []], ['\\', []], [' literal', ['700','710']]]) {
    const result = await listPartnerWorks(pool, 1, {scope: 'all', q});
    assert.deepEqual(result.items.map((item) => item.id), ids);
  }
  assert.ok(calls.every(({sql}) => !sql.includes("OR 1=1 --")));
  assert.equal((await listPartnerWorks(pool, 1, {q: 'x'.repeat(100)})).items.length, 0);
});

test('people exclude self, both block directions, inactive and missing codes and deduplicate membership', async (t) => {
  const {pool, calls} = fixture(t);
  const result = await listWorkPartners(pool, 1, '100');
  assert.deepEqual(result, {items: [
    {userId: '2', publicCode: 'two', nickname: 'Partner', avatarUrl: '', bio: '', commonWorkCount: 2,
      commonWorks: [{id: '100', name: 'Alpha'}, {id: '200', name: 'Beta'}]},
    {userId: '8', publicCode: 'eight', nickname: 'Partner 8', avatarUrl: '', bio: '', commonWorkCount: 1,
      commonWorks: [{id: '100', name: 'Alpha'}]},
  ], hasMore: false, nextOffset: null});
  assert.equal(calls.length, 2);
  assert.deepEqual(Object.keys(result.items[0]).sort(), ['avatarUrl','bio','commonWorkCount','commonWorks','nickname','publicCode','userId'].sort());
});

test('people pagination uses user id and details only the selected page', async (t) => {
  const {pool, calls} = fixture(t);
  const first = await listWorkPartners(pool, 1, '100', {limit: '1'});
  assert.equal(first.items[0].userId, '2');
  assert.equal(first.hasMore, true);
  assert.equal(first.nextOffset, 1);
  assert.deepEqual(calls[1].params, [1, 2]);
  const second = await listWorkPartners(pool, 1, '100', {limit: '1', offset: '1'});
  assert.equal(second.items[0].userId, '8');
  assert.equal(second.hasMore, false);
  assert.equal(second.nextOffset, null);
  assert.deepEqual(calls[3].params, [1, 8]);
  assert.deepEqual(await listWorkPartners(pool, 1, '100', {offset: '100000', limit: '50'}), {items: [], hasMore: false, nextOffset: null});
  assert.equal(calls.length, 5);
});

test('people order remains by user id when a later user has more common works', async (t) => {
  const {pool, db} = fixture(t);
  db.exec("INSERT INTO user_pit_works VALUES (8,200,'deep'),(8,300,'shallow')");
  const result = await listWorkPartners(pool, 1, '100');
  assert.deepEqual(result.items.map((user) => [user.userId, user.commonWorkCount]), [['2', 2], ['8', 3]]);
  assert.deepEqual(result.items[1].commonWorks, [
    {id: '100', name: 'Alpha'}, {id: '200', name: 'Beta'}, {id: '300', name: 'Solo'},
  ]);
});

test('unowned selected work still returns its people with zero common works', async (t) => {
  const {pool} = fixture(t);
  assert.deepEqual(await listWorkPartners(pool, 1, '400'), {items: [
    {userId: '6', publicCode: 'six', nickname: 'Other work', avatarUrl: '', bio: 'Other bio', commonWorkCount: 0, commonWorks: []},
  ], hasMore: false, nextOffset: null});
});

test('viewer with no works can discover all and work members, while mine stays empty', async (t) => {
  const {pool, db} = fixture(t);
  db.exec('DELETE FROM user_pit_works WHERE user_id = 1');
  assert.deepEqual(await listPartnerWorks(pool, 1), {items: [], hasMore: false, nextOffset: null});
  assert.ok((await listPartnerWorks(pool, 1, {scope: 'all'})).items.length > 0);
  const users = await listWorkPartners(pool, 1, '100');
  assert.deepEqual(users.items.map((user) => [user.userId, user.commonWorkCount, user.commonWorks]), [['2', 0, []], ['8', 0, []]]);
});

test('unavailable, self-only, empty and missing work have no members or detail query', async (t) => {
  const {pool, calls} = fixture(t);
  for (const id of ['500', '300', '600', '999999']) {
    assert.deepEqual(await listWorkPartners(pool, 1, id), {items: [], hasMore: false, nextOffset: null});
  }
  assert.equal(calls.length, 4);
});

test('pagination rejects repeated, unsafe, fractional and non-decimal inputs before SQL', async () => {
  const pool = {execute: () => assert.fail('unexpected SQL')};
  const queries = [
    {limit: '0'}, {limit: '51'}, {limit: ['1', '2']}, {limit: {}}, {limit: 1}, {limit: null},
    {limit: ''}, {limit: '1\n'}, {offset: '-1'}, {offset: '1.5'}, {offset: '1e2'},
    {offset: '0x10'}, {offset: '1 OR 1=1'}, {offset: '100001'}, {offset: '9007199254740992'},
    {offset: ['0']}, {offset: ' 0'}, {offset: '0 '},
  ];
  for (const query of queries) {
    await assert.rejects(listPartnerWorks(pool, 1, query), {message: 'invalid_pagination', status: 400});
    await assert.rejects(listWorkPartners(pool, 1, '100', query), {message: 'invalid_pagination', status: 400});
  }
});

test('scope, search and complete work id validation run before SQL', async () => {
  const pool = {execute: () => assert.fail('unexpected SQL')};
  for (const scope of ['Mine', '', null, ['mine'], ['mine', 'all'], {}, 1]) {
    await assert.rejects(listPartnerWorks(pool, 1, {scope}), {message: 'invalid_scope', status: 400});
  }
  for (const q of [null, ['a'], ['a', 'b'], {}, 1, 'x'.repeat(101)]) {
    await assert.rejects(listPartnerWorks(pool, 1, {q}), {message: 'invalid_search', status: 400});
  }
  for (const id of [undefined, null, [], ['100'], 100, '', '0', '-1', '100abc', '100/users', '1\n', '1.0', '1e2', '0x64', '9007199254740992']) {
    await assert.rejects(listWorkPartners(pool, 1, id), {message: 'invalid_work_id', status: 400});
  }
});

test('query count stays bounded as the people page grows', async (t) => {
  const {pool, db, calls} = fixture(t);
  const user = db.prepare("INSERT INTO users(id, public_code, nickname, account_status) VALUES (?, ?, 'Partner', 'active')");
  const pit = db.prepare("INSERT INTO user_pit_works VALUES (?, 100, 'deep')");
  for (let id = 10; id < 70; id++) {
    user.run(id, `user${id}`);
    pit.run(id);
  }
  const works = await listPartnerWorks(pool, 1);
  assert.equal(works.items[0].partnerCount, 62);
  assert.equal(calls.length, 1);
  const result = await listWorkPartners(pool, 1, '100', {limit: '50'});
  assert.equal(result.items.length, 50);
  assert.equal(result.hasMore, true);
  assert.equal(result.nextOffset, 50);
  assert.equal(calls.length, 3);
  assert.equal(calls[2].params.length, 51);
});

function response() {
  return {
    statusCode: 200, headers: {},
    set(name, value) {this.headers[name] = value;},
    status(code) {this.statusCode = code; return this;},
    json(body) {this.body = body;},
  };
}

test('both routes return private no-store pages using the authenticated viewer', async (t) => {
  const {pool, calls} = fixture(t);
  const handlers = new Map();
  registerPartnerDiscoveryRoutes({get: (path, handler) => handlers.set(path, handler)}, pool);
  for (const [path, handler] of handlers) {
    const res = response();
    await handler({userId: 1, query: {viewerId: '3'}, params: {workId: '100'}}, res, () => assert.fail('unexpected next'));
    assert.equal(res.headers['Cache-Control'], 'private, no-store');
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.items.length, path.endsWith('/users') ? 2 : 3);
  }
  assert.ok(calls.every(({params}) => params[0] === 1));
});

test('both routes report invalid inputs without SQL and forward database failures', async () => {
  const handlers = new Map();
  let calls = 0;
  const failure = new Error('database unavailable');
  registerPartnerDiscoveryRoutes({get: (path, handler) => handlers.set(path, handler)}, {
    execute: async () => {calls++; throw failure;},
  });
  for (const handler of handlers.values()) {
    const res = response();
    await handler({userId: 1, query: {limit: ['1']}, params: {workId: '100'}}, res, () => assert.fail('unexpected next'));
    assert.equal(res.statusCode, 400);
    assert.deepEqual(res.body, {error: 'invalid_pagination'});
    assert.equal(res.headers['Cache-Control'], 'private, no-store');
  }
  assert.equal(calls, 0);
  for (const handler of handlers.values()) {
    const res = response();
    let forwarded;
    await handler({userId: 1, query: {}, params: {workId: '100'}}, res, (error) => {forwarded = error;});
    assert.equal(forwarded, failure);
    assert.equal(res.body, undefined);
    assert.equal(res.headers['Cache-Control'], 'private, no-store');
  }
  assert.equal(calls, 2);
});

test('people route forwards failure of the common works batch without a partial response', async () => {
  const handlers = new Map();
  const failure = new Error('details unavailable');
  let calls = 0;
  registerPartnerDiscoveryRoutes({get: (path, handler) => handlers.set(path, handler)}, {
    execute: async () => {
      calls++;
      if (calls === 1) return [[{userId: 2, publicCode: 'two', nickname: 'Partner'}]];
      throw failure;
    },
  });
  const res = response();
  let forwarded;
  await handlers.get('/api/social/partner-works/:workId/users')(
    {userId: 1, query: {}, params: {workId: '100'}}, res, (error) => {forwarded = error;},
  );
  assert.equal(forwarded, failure);
  assert.equal(res.body, undefined);
  assert.equal(calls, 2);
});
