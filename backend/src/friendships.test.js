import assert from 'node:assert/strict';
import test from 'node:test';
import { DatabaseSync } from 'node:sqlite';
import { requestFriend, respondFriend, removeFriend, listFriends, publicFriendStatus, validateFriendInvite, userPair } from './friendships.js';
import { eventListQuery } from './event-queries.js';

function fixture() {
  const db = new DatabaseSync(':memory:');
  db.function('DATE_FORMAT', (date, _format) => date);
  db.function('LEAST', (a, b) => Math.min(a, b));
  db.function('GREATEST', (a, b) => Math.max(a, b));
  db.exec(`CREATE TABLE users(id INTEGER PRIMARY KEY, account_status TEXT, public_code TEXT, nickname TEXT, avatar_url TEXT, booking_visibility TEXT);
    CREATE TABLE user_blocks(blocker_user_id INTEGER,blocked_user_id INTEGER);
    CREATE TABLE friendships(id INTEGER PRIMARY KEY AUTOINCREMENT,user_low_id INTEGER,user_high_id INTEGER,requester_id INTEGER,recipient_id INTEGER,
      status TEXT DEFAULT 'pending', introduction TEXT,event_id INTEGER,day_index INTEGER,event_name TEXT,event_date TEXT,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,accepted_at TEXT, UNIQUE(user_low_id,user_high_id));
    INSERT INTO users VALUES(1,'active','one','攝影','','public'),(2,'active','two','Coser','','public'),(3,'active','three','third','','public');
    CREATE TABLE events(id INTEGER, category TEXT, name TEXT, start_date TEXT,end_date TEXT,venue TEXT,detailed_address TEXT,fee TEXT,organizer TEXT,
      description TEXT,image_url TEXT,source_type INTEGER,source_name TEXT,source_url TEXT,status TEXT);
    CREATE TABLE event_bookings(event_id INTEGER,user_id INTEGER,day_index INTEGER);
    CREATE TABLE circle_members(circle_id INTEGER,user_id INTEGER);
    CREATE TABLE follows(follower_user_id INTEGER,followed_user_id INTEGER);
    INSERT INTO events(id,name,start_date,end_date,status) VALUES(10,'CCF','2026-10-09','2026-10-11','approved');
    INSERT INTO event_bookings VALUES(10,2,2);`);
  const calls = [];
  const connection = {
    async beginTransaction() { db.exec('BEGIN'); },
    async commit() { db.exec('COMMIT'); },
    async rollback() { db.exec('ROLLBACK'); },
    release() {},
    async execute(sql, params = []) {
      calls.push({sql, params});
      if (sql.includes('DATE_ADD(start_date')) {
        const event = db.prepare('SELECT * FROM events WHERE id=?').get(params[1]);
        return [[event && event.status === 'approved' && params[0] <= 3 ? {name: event.name, eventDate: `2026-10-${8 + params[0]}`} : undefined].filter(Boolean)];
      }
      const statement = db.prepare(sql.replaceAll(' FOR UPDATE', ''));
      if (/^\s*(SELECT|WITH)/.test(sql)) return [statement.all(...params)];
      return [statement.run(...params)];
    },
  };
  return {db, calls, pool: {...connection, async getConnection() {return connection;}}};
}

const invite = { introduction: '我是戴黑色帽子在水池旁拍照的攝影', eventId: '10', dayIndex: 2 };

test('invite input validates self, IDs, introduction length and explicit day', () => {
  assert.deepEqual(userPair('10', '2'), ['2','10']);
  assert.throws(() => userPair(1,1), {code:'cannot_friend_self'});
  assert.throws(() => userPair(1,'invalid'), {code:'invalid_user_id'});
  assert.throws(() => validateFriendInvite({introduction:' '}), {code:'invalid_friend_introduction'});
  assert.throws(() => validateFriendInvite({introduction:'字'.repeat(201)}), {code:'invalid_friend_introduction'});
  assert.equal(validateFriendInvite({introduction:'😀'.repeat(200)}).introduction.length, 400);
  assert.throws(() => validateFriendInvite({...invite,dayIndex:0}), {code:'invalid_friend_event'});
  assert.throws(() => validateFriendInvite({introduction:'hi',dayIndex:1}), {code:'invalid_friend_event'});
});

test('request preserves D2 snapshot, is idempotent, and does not create follows', async () => {
  const {db,pool,calls} = fixture();
  try {
    assert.deepEqual(await requestFriend(pool,1,2,invite), {status:'pending'});
    await requestFriend(pool,1,2,{...invite,introduction:'new',dayIndex:3});
    const row = db.prepare('SELECT * FROM friendships').get();
    assert.equal(row.introduction, invite.introduction);
    assert.equal(row.day_index, 2);
    assert.equal(row.event_date, '2026-10-10');
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM follows').get().n, 0);
    assert.match(calls[0].sql, /ORDER BY id FOR UPDATE/);
  } finally {db.close();}
});

test('only recipient may accept; both lists retain identical introduction and event', async () => {
  const {db,pool} = fixture();
  try {
    await requestFriend(pool,1,2,invite);
    await assert.rejects(respondFriend(pool,1,1,'accept'), {code:'friend_request_not_found'});
    assert.equal((await listFriends(pool,2))[0].status, 'incoming');
    await respondFriend(pool,2,1,'accept');
    for (const viewer of [1,2]) {
      const [row] = await listFriends(pool,viewer);
      assert.equal(row.status, 'accepted');
      assert.equal(row.introduction, invite.introduction);
      assert.equal(row.eventName, 'CCF');
      assert.equal(row.dayIndex, 2);
    }
    await assert.rejects(respondFriend(pool,2,1,'ignore'), {code:'friend_request_not_found'});
  } finally {db.close();}
});

test('ignored requests disappear only from recipient; retries and outgoing payload remain indistinguishable', async () => {
  const {db,pool} = fixture();
  try {
    await requestFriend(pool,1,2,invite);
    const before = await listFriends(pool,1);
    await respondFriend(pool,2,1,'ignore');
    assert.deepEqual(await listFriends(pool,1), before);
    assert.deepEqual(await listFriends(pool,2), []);
    assert.deepEqual(await requestFriend(pool,1,2,invite), {status:'pending'});
    assert.deepEqual(await listFriends(pool,2), []);
    assert.equal(publicFriendStatus(db.prepare('SELECT * FROM friendships').get(), 1), 'pending');
  } finally {db.close();}
});

test('cross invitations require explicit acceptance and cannot create duplicate pairs', async () => {
  const {db,pool} = fixture();
  try {
    await requestFriend(pool,1,2,invite);
    assert.deepEqual(await requestFriend(pool,2,1,invite), {status:'incoming'});
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM friendships').get().n, 1);
    await respondFriend(pool,2,1,'ignore');
    assert.deepEqual(await requestFriend(pool,2,1,invite), {status:'pending'});
    assert.equal((await listFriends(pool,1))[0].status, 'incoming');
  } finally {db.close();}
});

test('blocks, suspended users and invalid events fail without writing a relationship', async () => {
  const {db,pool} = fixture();
  try {
    db.exec('INSERT INTO user_blocks VALUES(2,1)');
    await assert.rejects(requestFriend(pool,1,2,invite), {code:'user_unavailable'});
    db.exec("DELETE FROM user_blocks; UPDATE users SET account_status='suspended' WHERE id=2");
    await assert.rejects(requestFriend(pool,1,2,invite), {code:'user_unavailable'});
    db.exec("UPDATE users SET account_status='active'");
    await assert.rejects(requestFriend(pool,1,2,{...invite,dayIndex:4}), {code:'invalid_friend_event'});
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM friendships').get().n, 0);
  } finally {db.close();}
});

test('removing friendship leaves follows intact; blocks hide even existing relationships', async () => {
  const {db,pool} = fixture();
  try {
    await requestFriend(pool,1,2,invite);
    await respondFriend(pool,2,1,'accept');
    db.exec('INSERT INTO follows VALUES(1,2); INSERT INTO user_blocks VALUES(2,1)');
    assert.deepEqual(await listFriends(pool,1), []);
    db.exec('DELETE FROM user_blocks');
    await removeFriend(pool,1,2);
    assert.deepEqual(await listFriends(pool,2), []);
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM follows').get().n, 1);
  } finally {db.close();}
});

test('event friend days are accepted-only, D2-specific and respect blocks and circle privacy', async () => {
  const {db,pool} = fixture();
  try {
    const sql = eventListQuery.replaceAll("GROUP_CONCAT(day_index ORDER BY day_index SEPARATOR ',')", 'GROUP_CONCAT(day_index)')
      .replace(/GROUP_CONCAT\(DISTINCT ([\w.]+) ORDER BY [\w.]+\)/g, 'GROUP_CONCAT(DISTINCT $1)');
    const read = () => db.prepare(sql).get(...Array(16).fill(1));
    await requestFriend(pool,1,2,invite);
    assert.equal(read().hasFriends, 0);
    await respondFriend(pool,2,1,'accept');
    assert.equal(read().hasFriends, 1);
    assert.equal(read().friendDayIndexes, '2');
    db.exec("UPDATE users SET booking_visibility='circle' WHERE id=2");
    assert.equal(read().hasFriends, 0);
    db.exec('INSERT INTO circle_members VALUES(1,1),(1,2)');
    assert.equal(read().hasFriends, 1);
    db.exec('INSERT INTO user_blocks VALUES(2,1)');
    assert.equal(read().hasFriends, 0);
  } finally {db.close();}
});
