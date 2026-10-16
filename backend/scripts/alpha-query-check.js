import assert from 'node:assert/strict';
import { createPool } from '../src/db.js';
import { eventListQuery } from '../src/event-queries.js';

// CTE fixtures shadow table names: this check never changes production records.
const fixtures = `WITH
events AS (
  SELECT 101 id, 'QA' category, 'QA event' name, DATE('2099-01-01') start_date,
    DATE('2099-01-03') end_date, '' venue, '' detailed_address, '' fee,
    '' organizer, '' description, '' image_url, 3 source_type, '' source_name,
    '' source_url, 'approved' status
  UNION ALL SELECT 102, 'QA', 'QA second event', DATE('2099-01-04'),
    DATE('2099-01-04'), '', '', '', '', '', '', 3, '', '', 'approved'
),
event_bookings AS (
  SELECT 101 event_id, 1 user_id, 1 day_index
  UNION ALL SELECT 101, 2, 2 UNION ALL SELECT 101, 3, 3
  UNION ALL SELECT 101, 4, 1 UNION ALL SELECT 102, 2, 1
),
users AS (SELECT 1 id, 'public' booking_visibility, 'active' account_status
  UNION ALL SELECT 2, 'public', 'active' UNION ALL SELECT 3, 'circle', 'active' UNION ALL SELECT 4, 'public', 'active'),
friendships AS (SELECT 1 user_low_id, 2 user_high_id, 'accepted' status
  UNION ALL SELECT 1, 3, 'pending' UNION ALL SELECT 1, 4, 'accepted'),
follows AS (SELECT 1 follower_user_id, 2 followed_user_id
  UNION ALL SELECT 1, 3 UNION ALL SELECT 1, 4),
user_blocks AS (SELECT 1 blocker_user_id, 4 blocked_user_id),
circle_members AS (SELECT 1 circle_id, 1 user_id
  UNION ALL SELECT 1, 2 UNION ALL SELECT 1, 3 UNION ALL SELECT 1, 4
  UNION ALL SELECT 2, 1 UNION ALL SELECT 2, 2)
`;

const pool = createPool();
try {
  const [rows] = await pool.execute(fixtures + eventListQuery, Array(16).fill(1));
  assert.equal(rows.length, 2, 'One event must remain one row with multiple followers/circles');
  const first = rows.find((row) => row.id === 101);
  assert.equal(first.joinedDayIndexes, '1');
  assert.equal(first.followedDayIndexes, '2,3');
  assert.equal(first.circleDayIndexes, '2,3');
  assert.equal(first.friendDayIndexes, '2');
  const [outsider] = await pool.execute(fixtures + eventListQuery, Array(16).fill(5));
  assert.ok(outsider.every((row) => !row.isJoined && !row.hasFollowedParticipants && !row.hasCircleMembers && !row.hasFriends));
  const [[dates]] = await pool.execute(`SELECT
    DATE_ADD(DATE('2099-01-01'), INTERVAL (2 - 1) DAY) = DATE('2099-01-02') AS dayTwo,
    DATE_ADD(DATE('2099-01-01'), INTERVAL ? DAY) < DATE('2099-01-02') AS dayOneEnded`, [0]);
  assert.equal(dates.dayTwo, 1);
  assert.equal(dates.dayOneEnded, 1);
  console.log('Alpha SQL checks passed: event uniqueness, daily social flags, blocks, and dates. No records changed.');
} finally {
  await pool.end();
}
