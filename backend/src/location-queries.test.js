import assert from 'node:assert/strict';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {sharedLocationsQuery, updateLocationCoordinatesQuery} from './location-queries.js';

function fixture() {
  const db = new DatabaseSync(':memory:');
  db.function('DATE_FORMAT', (date, _format) => date);
  db.function('LEAST', (a, b) => Math.min(a, b));
  db.function('GREATEST', (a, b) => Math.max(a, b));
  db.function('UNIX_TIMESTAMP', (date) => date == null ? null : Date.parse(`${date.replace(' ', 'T')}Z`) / 1000);
  db.exec(`CREATE TABLE users(id INTEGER,public_code TEXT,nickname TEXT,avatar_url TEXT);
    CREATE TABLE shared_locations(event_id INTEGER,user_id INTEGER,day_index INTEGER,latitude REAL,longitude REAL,visibility TEXT,shared_at TEXT,expires_at TEXT);
    CREATE TABLE event_bookings(event_id INTEGER,user_id INTEGER,day_index INTEGER,role TEXT,work_id INTEGER,character_name TEXT,outfit_image_url TEXT,interaction_tags TEXT,available_time TEXT,presence_status TEXT);
    CREATE TABLE works(id INTEGER,name TEXT);
    CREATE TABLE follows(follower_user_id INTEGER,followed_user_id INTEGER);
    CREATE TABLE user_blocks(blocker_user_id INTEGER,blocked_user_id INTEGER);
    CREATE TABLE circle_members(circle_id INTEGER,user_id INTEGER);
    CREATE TABLE friendships(user_low_id INTEGER,user_high_id INTEGER,status TEXT);
    INSERT INTO users VALUES (1,'one','viewer',''),(2,'two','peer','');
    INSERT INTO shared_locations VALUES (10,2,2,25,121,'circle','2026-01-01 00:00:00','2099-01-01 00:00:00');
    INSERT INTO event_bookings(event_id,user_id,day_index) VALUES (10,1,2),(10,2,2);
    INSERT INTO circle_members VALUES (1,1),(1,2),(2,1),(2,2);`);
  return db;
}

test('two shared circles still produce exactly one location per peer/day', () => {
  const db = fixture();
  try {
    const rows = db.prepare(sharedLocationsQuery).all(1,1,1,1,1,1,1,1,10,1);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].userId, 2);
    assert.equal(rows[0].dayIndex, 2);
  } finally {db.close();}
});

test('blocks and public-location same-day attendance remain enforced', () => {
  const db = fixture();
  try {
    db.exec("UPDATE shared_locations SET visibility='public'; DELETE FROM event_bookings WHERE user_id=1;");
    assert.equal(db.prepare(sharedLocationsQuery).all(1,1,1,1,1,1,1,1,10,1).length, 0);
    db.exec('INSERT INTO event_bookings(event_id,user_id,day_index) VALUES(10,1,2); INSERT INTO user_blocks VALUES(2,1);');
    assert.equal(db.prepare(sharedLocationsQuery).all(1,1,1,1,1,1,1,1,10,1).length, 0);
  } finally {db.close();}
});

test('friend filter metadata never grants private circle or followed visibility', () => {
  const db = fixture();
  try {
    db.exec("INSERT INTO friendships VALUES(1,2,'accepted'); DELETE FROM circle_members;");
    const read = () => db.prepare(sharedLocationsQuery).all(1,1,1,1,1,1,1,1,10,1);
    assert.equal(read().length, 0);
    db.exec("UPDATE shared_locations SET visibility='followed'");
    assert.equal(read().length, 0);
    db.exec("UPDATE shared_locations SET visibility='public'");
    assert.equal(read()[0].isFriend, 1);
    db.exec("UPDATE friendships SET status='pending'");
    assert.equal(read()[0].isFriend, 0);
  } finally { db.close(); }
});

test('coordinate updates preserve visibility, date and expiry; expired rows stay unchanged', () => {
  const db = fixture();
  try {
    assert.equal(db.prepare(updateLocationCoordinatesQuery).run(24,120,10,2,2).changes, 1);
    const row = db.prepare('SELECT * FROM shared_locations').get();
    assert.equal(row.visibility, 'circle');
    assert.equal(row.day_index, 2);
    assert.equal(row.expires_at, '2099-01-01 00:00:00');
    db.exec("UPDATE shared_locations SET expires_at='2000-01-01 00:00:00'");
    assert.equal(db.prepare(updateLocationCoordinatesQuery).run(23,119,10,2,2).changes, 0);
  } finally {db.close();}
});
