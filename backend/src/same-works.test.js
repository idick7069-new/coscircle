import assert from 'node:assert/strict';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import fs from 'node:fs';
import {listSameWorkUsers, registerSameWorkRoutes} from './same-works.js';

function fixture() {
  const db = new DatabaseSync(':memory:');
  db.exec(`CREATE TABLE users(id INTEGER PRIMARY KEY, public_code TEXT, nickname TEXT, avatar_url TEXT, bio TEXT, account_status TEXT);
    CREATE TABLE works(id INTEGER PRIMARY KEY, name TEXT);
    CREATE TABLE user_pit_works(user_id INTEGER, work_id INTEGER, depth TEXT, PRIMARY KEY(user_id,work_id));
    CREATE TABLE user_blocks(blocker_user_id INTEGER, blocked_user_id INTEGER);
    INSERT INTO users VALUES
      (1,'me','我','','','active'), (2,'two','兩個同坑','','自介','active'),
      (3,'three','我封鎖','','','active'), (4,'four','封鎖我','','','active'),
      (5,'five','停用','','','suspended'), (6,'six','不同坑','','','active'),
      (7,NULL,'未公開名片','','','active'), (8,'eight','一個同坑','','','active');
    INSERT INTO works VALUES (100,'星旅'), (200,'原神'), (300,'其他作品');
    INSERT INTO user_pit_works VALUES (1,100,'deep'),(1,200,'shallow'),
      (2,100,'shallow'),(2,200,'deep'),(3,100,'deep'),(4,200,'shallow'),
      (5,100,'deep'),(6,300,'shallow'),(7,100,'deep'),(8,200,'deep');
    INSERT INTO user_blocks VALUES (1,3),(4,1);`);
  const pool = {execute: async (sql, params) => [db.prepare(sql).all(...params)]};
  return {db, pool};
}

test('matches deep/shallow by shared work, excludes self, both block directions, inactive and missing public code', async () => {
  const {db, pool} = fixture();
  try {
    const result = await listSameWorkUsers(pool, 1);
    assert.deepEqual(result.items.map((item) => item.userId), ['2', '8']);
    assert.deepEqual(result.items.map((item) => item.commonWorkCount), [2, 1]);
    assert.deepEqual(new Set(result.items[0].commonWorks.map((work) => work.id)), new Set(['100', '200']));
    assert.deepEqual(Object.keys(result.items[0]).sort(), ['avatarUrl','bio','commonWorkCount','commonWorks','nickname','publicCode','userId'].sort());
    assert.equal(result.hasMore, false);
  } finally { db.close(); }
});

test('pagination is bounded and stable; only selected users receive common-work details', async () => {
  const {db, pool} = fixture();
  try {
    const first = await listSameWorkUsers(pool, 1, {limit: '1'});
    assert.equal(first.items.length, 1);
    assert.equal(first.items[0].userId, '2');
    assert.equal(first.hasMore, true);
    assert.equal(first.nextOffset, 1);
    const second = await listSameWorkUsers(pool, 1, {limit: '1', offset: '1'});
    assert.equal(second.items[0].userId, '8');
    assert.deepEqual(second.items[0].commonWorks, [{id: '200', name: '原神'}]);
    assert.equal(second.nextOffset, null);
  } finally { db.close(); }
});

test('no own works returns an empty page, never all users', async () => {
  const {db, pool} = fixture();
  try {
    db.exec('DELETE FROM user_pit_works WHERE user_id=1');
    assert.deepEqual(await listSameWorkUsers(pool, 1), {items: [], hasMore: false, nextOffset: null});
  } finally { db.close(); }
});

test('bad pagination is rejected before executing SQL', async () => {
  const pool = {execute: () => assert.fail('unexpected database call')};
  for (const query of [{limit:'0'}, {limit:'51'}, {limit:['1']}, {offset:'-1'}, {offset:'1 OR 1=1'}, {offset:'100001'}]) {
    await assert.rejects(listSameWorkUsers(pool, 1, query), /invalid_pagination/);
  }
});

test('route reports bad queries and forwards database failures', async () => {
  const handlerMap = new Map();
  registerSameWorkRoutes({get(path, callback) {
    handlerMap.set(path, callback);
  }}, {execute: async () => {throw new Error('db unavailable');}});
  assert.deepEqual([...handlerMap.keys()].sort(), [
    '/api/social/partner-works', '/api/social/partner-works/:workId/users', '/api/social/same-works',
  ]);
  const handler = handlerMap.get('/api/social/same-works');
  const res = {statusCode: 200, headers: {}, set(name, value) {this.headers[name] = value;}, status(code) {this.statusCode = code; return this;}, json(body) {this.body = body;}};
  await handler({userId: 1, query: {limit:'bad'}}, res, () => assert.fail('unexpected next'));
  assert.equal(res.statusCode, 400);
  assert.equal(res.headers['Cache-Control'], 'private, no-store');
  let forwarded;
  await handler({userId: 1, query: {}}, res, (error) => {forwarded = error;});
  assert.equal(forwarded.message, 'db unavailable');
  const server = fs.readFileSync(new URL('./server.js', import.meta.url), 'utf8');
  assert.ok(server.indexOf('registerSameWorkRoutes(app, pool)') > server.indexOf("error: 'authentication_required'"));
});
