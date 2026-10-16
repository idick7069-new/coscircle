import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';

// Exercise the route's actual SQL without starting a server or accessing production.
const source = fs.readFileSync(new URL('./server.js', import.meta.url), 'utf8');
const route = source.split("app.get('/api/events/:eventId/participants'")[1]
  .split("app.post('/api/users/:userId/follow'")[0];
const query = route.match(/`(SELECT[\s\S]*?)`/)[1];
const bindings = route.match(/\[\s*(req\.userId,[\s\S]*?)\]/)[1]
  .split(',').map((value) => value.trim()).filter(Boolean);

function fixture() {
  const db = new DatabaseSync(':memory:');
  db.exec(`
    CREATE TABLE users(id INTEGER, public_code TEXT, nickname TEXT, avatar_url TEXT,
      facebook_url TEXT, bio TEXT, booking_visibility TEXT);
    CREATE TABLE event_bookings(event_id INTEGER, user_id INTEGER, day_index INTEGER,
      role TEXT, work_id INTEGER, character_name TEXT, outfit_image_url TEXT,
      interaction_tags TEXT, available_time TEXT, presence_status TEXT, message TEXT,
      updated_at TEXT);
    CREATE TABLE works(id INTEGER, name TEXT);
    CREATE TABLE follows(follower_user_id INTEGER, followed_user_id INTEGER);
    CREATE TABLE user_blocks(blocker_user_id INTEGER, blocked_user_id INTEGER);
    CREATE TABLE circle_members(circle_id INTEGER, user_id INTEGER);
    INSERT INTO users(id, nickname, booking_visibility) VALUES
      (1, 'viewer', 'circle'), (2, 'public peer', 'public'),
      (3, 'circle peer', 'circle'), (4, 'unknown visibility', 'private');
    INSERT INTO event_bookings(event_id, user_id, day_index, role) VALUES
      (10, 2, 1, 'coser'), (10, 2, 2, 'photographer'),
      (10, 3, 1, 'coser'), (10, 4, 1, 'coser'), (20, 2, 1, 'coser');
  `);
  return db;
}

function read(db) {
  return db.prepare(query).all(...bindings.map((binding) => {
    assert.ok(['req.userId', 'req.params.eventId'].includes(binding));
    return binding === 'req.userId' ? 1 : 10;
  }));
}

test('browsing without a booking shows public bookings, keeps dates and event separate', () => {
  const db = fixture();
  try {
    assert.deepEqual(read(db).map((row) => [row.userId, row.dayIndex]), [[2, 1], [2, 2]]);
    db.exec('INSERT INTO event_bookings(event_id, user_id, day_index) VALUES (10, 1, 3)');
    assert.equal(read(db).filter((row) => row.userId === 2).length, 2);
    assert.equal(read(db).find((row) => row.userId === 1).isMe, 1);
  } finally { db.close(); }
});

test('circle bookings require shared membership, not following, and never duplicate', () => {
  const db = fixture();
  try {
    db.exec('INSERT INTO follows VALUES (1, 3)');
    assert.equal(read(db).some((row) => row.userId === 3), false);
    db.exec('INSERT INTO circle_members VALUES (1, 1), (1, 3), (2, 1), (2, 3), (1, 4)');
    assert.equal(read(db).filter((row) => row.userId === 3).length, 1);
    assert.equal(read(db).some((row) => row.userId === 4), false);
    db.exec('DELETE FROM circle_members WHERE user_id = 1');
    assert.equal(read(db).some((row) => row.userId === 3), false);
  } finally { db.close(); }
});

for (const [blocker, blocked] of [[1, 2], [2, 1], [1, 3], [3, 1]]) {
  test(`blocking ${blocker} -> ${blocked} hides bookings despite shared circles`, () => {
    const db = fixture();
    try {
      db.exec(`INSERT INTO circle_members VALUES (1, 1), (1, 2), (1, 3);
        INSERT INTO user_blocks VALUES (${blocker}, ${blocked});`);
      const peer = blocker === 1 ? blocked : blocker;
      assert.equal(read(db).some((row) => row.userId === peer), false);
    } finally { db.close(); }
  });
}
