import fs from 'node:fs/promises';
import { inTransaction } from './db-transaction.js';

export async function ensureFriendships(pool) {
  await pool.query(await fs.readFile(new URL('../db/migrate_friendships.sql', import.meta.url), 'utf8'));
}

function fail(code, status = 400) {
  throw Object.assign(new Error(code), { code, status });
}

function validId(value) {
  const text = String(value);
  return /^[1-9]\d{0,19}$/.test(text) && BigInt(text) <= 18446744073709551615n;
}

export function userPair(a, b) {
  const ids = [String(a), String(b)];
  if (ids.some((id) => !validId(id))) fail('invalid_user_id');
  if (ids[0] === ids[1]) fail('cannot_friend_self');
  return BigInt(ids[0]) < BigInt(ids[1]) ? ids : ids.reverse();
}

export function validateFriendInvite(body) {
  const introduction = typeof body.introduction === 'string' ? body.introduction.trim() : '';
  if (!introduction || Array.from(introduction).length > 200) fail('invalid_friend_introduction');
  const hasEvent = body.eventId != null && body.eventId !== '';
  if (!hasEvent && body.dayIndex != null) fail('invalid_friend_event');
  if (hasEvent && (!validId(body.eventId) || !Number.isSafeInteger(body.dayIndex) || body.dayIndex < 1)) {
    fail('invalid_friend_event');
  }
  return { introduction, eventId: hasEvent ? String(body.eventId) : null, dayIndex: hasEvent ? body.dayIndex : null };
}

async function lockPair(db, pair) {
  // Invitations, replies and blocks acquire the same user locks in ID order.
  const [users] = await db.execute('SELECT id, account_status FROM users WHERE id IN (?, ?) ORDER BY id FOR UPDATE', pair);
  if (users.length !== 2 || users.some((user) => user.account_status !== 'active')) fail('user_unavailable', 404);
  const [blocks] = await db.execute(`SELECT 1 FROM user_blocks
    WHERE (blocker_user_id=? AND blocked_user_id=?) OR (blocker_user_id=? AND blocked_user_id=?) LIMIT 1`,
  [pair[0], pair[1], pair[1], pair[0]]);
  if (blocks.length) fail('user_unavailable', 404);
}

// Ignored is never serialized to the requester, even for repeat submissions.
export function publicFriendStatus(row, viewerId) {
  if (!row) return 'none';
  if (row.status === 'accepted') return 'accepted';
  if (String(row.requester_id) === String(viewerId)) return 'pending';
  return row.status === 'pending' ? 'incoming' : 'none';
}

export async function requestFriend(pool, viewerId, targetId, body) {
  const pair = userPair(viewerId, targetId);
  const invite = validateFriendInvite(body);
  return inTransaction(pool, async (db) => {
    await lockPair(db, pair);
    const [[existing]] = await db.execute('SELECT * FROM friendships WHERE user_low_id=? AND user_high_id=? FOR UPDATE', pair);
    if (existing && (existing.status !== 'ignored' || String(existing.requester_id) === String(viewerId))) {
      return { status: publicFriendStatus(existing, viewerId) };
    }
    let event = null;
    if (invite.eventId) {
      const [[row]] = await db.execute(`SELECT name,
        DATE_FORMAT(DATE_ADD(start_date, INTERVAL (? - 1) DAY), '%Y-%m-%d') AS eventDate
        FROM events WHERE id=? AND status='approved' AND ? <= DATEDIFF(end_date, start_date)+1`,
      [invite.dayIndex, invite.eventId, invite.dayIndex]);
      if (!row) fail('invalid_friend_event');
      event = row;
    }
    if (existing) await db.execute('DELETE FROM friendships WHERE id=?', [existing.id]);
    await db.execute(`INSERT INTO friendships
      (user_low_id,user_high_id,requester_id,recipient_id,introduction,event_id,day_index,event_name,event_date)
      VALUES (?,?,?,?,?,?,?,?,?)`,
    [...pair, viewerId, targetId, invite.introduction, invite.eventId, invite.dayIndex, event?.name ?? null, event?.eventDate ?? null]);
    return { status: 'pending' };
  });
}

export async function respondFriend(pool, viewerId, requestId, action) {
  if (!['accept', 'ignore'].includes(action)) fail('invalid_friend_action');
  if (!validId(requestId)) fail('friend_request_not_found', 404);
  return inTransaction(pool, async (db) => {
    const [[row]] = await db.execute('SELECT * FROM friendships WHERE id=? AND recipient_id=?', [requestId, viewerId]);
    if (!row) fail('friend_request_not_found', 404);
    await lockPair(db, userPair(row.requester_id, row.recipient_id));
    const [[current]] = await db.execute('SELECT * FROM friendships WHERE id=? AND recipient_id=? FOR UPDATE', [requestId, viewerId]);
    if (!current || current.status !== 'pending') fail('friend_request_not_found', 404);
    await db.execute(`UPDATE friendships SET status=?, accepted_at=${action === 'accept' ? 'CURRENT_TIMESTAMP' : 'NULL'} WHERE id=?`,
      [action === 'accept' ? 'accepted' : 'ignored', requestId]);
  });
}

export async function removeFriend(pool, viewerId, targetId) {
  const pair = userPair(viewerId, targetId);
  return inTransaction(pool, async (db) => {
    await lockPair(db, pair);
    await db.execute("DELETE FROM friendships WHERE user_low_id=? AND user_high_id=? AND status='accepted'", pair);
  });
}

export async function listFriends(pool, viewerId) {
  const [rows] = await pool.execute(`SELECT f.id, u.id AS userId, u.public_code AS publicCode,
    u.nickname, u.avatar_url AS avatarUrl, f.requester_id AS requesterId,
    CASE WHEN f.status='accepted' THEN 'accepted' WHEN f.requester_id=? THEN 'pending' ELSE 'incoming' END AS status,
    f.introduction, f.event_id AS eventId, f.day_index AS dayIndex, f.event_name AS eventName,
    DATE_FORMAT(f.event_date, '%Y-%m-%d') AS eventDate,
    DATE_FORMAT(f.created_at, '%Y-%m-%dT%H:%i:%s') AS createdAt,
    DATE_FORMAT(f.accepted_at, '%Y-%m-%dT%H:%i:%s') AS acceptedAt
    FROM friendships f INNER JOIN users u ON u.id=IF(f.requester_id=?, f.recipient_id, f.requester_id)
    WHERE (f.requester_id=? OR f.recipient_id=?) AND u.account_status='active'
      AND (f.status<>'ignored' OR f.requester_id=?)
      AND NOT EXISTS (SELECT 1 FROM user_blocks b WHERE
        (b.blocker_user_id=? AND b.blocked_user_id=u.id) OR (b.blocker_user_id=u.id AND b.blocked_user_id=?))
    ORDER BY f.created_at DESC`, Array(7).fill(viewerId));
  return rows;
}

export function registerFriendRoutes(app, pool) {
  const route = (handler) => async (req, res, next) => {
    try { await handler(req, res); } catch (error) {
      if (error.status) res.status(error.status).json({ error: error.code });
      else next(error);
    }
  };
  app.get('/api/friends', route(async (req, res) => res.json(await listFriends(pool, req.userId))));
  app.post('/api/friend-invites/:userId', route(async (req, res) => {
    res.json(await requestFriend(pool, req.userId, req.params.userId, req.body));
  }));
  app.post('/api/friend-requests/:requestId/respond', route(async (req, res) => {
    await respondFriend(pool, req.userId, req.params.requestId, req.body.action);
    res.status(204).end();
  }));
  app.delete('/api/friends/:userId', route(async (req, res) => {
    await removeFriend(pool, req.userId, req.params.userId);
    res.status(204).end();
  }));
}
