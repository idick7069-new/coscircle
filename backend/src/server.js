import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import { importEvents } from '../scripts/scrape-events.js';
import { createPool } from './db.js';

const app = express();
const pool = createPool();
const devUserId = 1;
const eventScraperEnabled = process.env.EVENT_SCRAPER_ENABLED !== 'false';
const eventScraperTimeZone = process.env.EVENT_SCRAPER_TIME_ZONE ?? 'Asia/Taipei';

app.use(cors());
app.use(express.json({ limit: '10mb' }));

if (eventScraperEnabled) {
  scheduleDailyEventImport();
}

app.get('/api/health', (_req, res) => res.json({ ok: true, name: 'CosCircle API' }));

app.get('/api/me', async (_req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT id, nickname, avatar_url AS avatarUrl, facebook_url AS facebookUrl, bio
         FROM users
        WHERE id = ?`,
      [devUserId],
    );
    if (!rows[0]) {
      res.json(null);
      return;
    }
    res.json({
      ...rows[0],
      pitWorks: await fetchUserPitWorks(devUserId),
    });
  } catch (error) {
    next(error);
  }
});

app.put('/api/me', async (req, res, next) => {
  const connection = await pool.getConnection();
  try {
    const { nickname, avatarUrl, facebookUrl, bio, pitWorkIds = [] } = req.body;
    await connection.beginTransaction();
    await connection.execute(
      `UPDATE users
          SET nickname = ?, avatar_url = ?, facebook_url = ?, bio = ?
        WHERE id = ?`,
      [nickname, avatarUrl ?? null, facebookUrl ?? null, bio ?? null, devUserId],
    );
    await connection.execute('DELETE FROM user_pit_works WHERE user_id = ?', [
      devUserId,
    ]);
    for (const workId of pitWorkIds) {
      await connection.execute(
        `INSERT IGNORE INTO user_pit_works (user_id, work_id)
         VALUES (?, ?)`,
        [devUserId, workId],
      );
    }
    await connection.commit();
    const [rows] = await pool.execute(
      `SELECT id, nickname, avatar_url AS avatarUrl, facebook_url AS facebookUrl, bio
         FROM users
        WHERE id = ?`,
      [devUserId],
    );
    res.json({
      ...rows[0],
      pitWorks: await fetchUserPitWorks(devUserId),
    });
  } catch (error) {
    await connection.rollback();
    next(error);
  } finally {
    connection.release();
  }
});

app.get('/api/works', async (req, res, next) => {
  try {
    const query = String(req.query.query ?? '').trim();
    const like = `%${query}%`;
    const [rows] = await pool.execute(
      `SELECT id, name
         FROM works
        WHERE ? = '' OR name LIKE ?
        ORDER BY
          CASE WHEN name = ? THEN 0
               WHEN name LIKE ? THEN 1
               ELSE 2
          END,
          name ASC
        LIMIT 20`,
      [query, like, query, `${query}%`],
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.post('/api/works', async (req, res, next) => {
  try {
    const name = String(req.body.name ?? '').trim();
    if (!name) {
      res.status(400).json({ error: 'work_name_required' });
      return;
    }
    await pool.execute('INSERT IGNORE INTO works (name) VALUES (?)', [name]);
    const [rows] = await pool.execute('SELECT id, name FROM works WHERE name = ?', [
      name,
    ]);
    res.status(201).json(rows[0]);
  } catch (error) {
    next(error);
  }
});

app.get('/api/events', async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      `SELECT events.id, events.category, events.name,
              DATE_FORMAT(events.start_date, '%Y-%m-%d') AS startDate,
              DATE_FORMAT(events.end_date, '%Y-%m-%d') AS endDate,
              events.venue, events.fee, events.organizer, events.description,
              events.image_url AS imageUrl,
              events.source_type AS sourceType,
              events.source_name AS sourceName,
              events.source_url AS sourceUrl,
              CASE WHEN my_bookings.id IS NULL THEN FALSE ELSE TRUE END AS isJoined,
              CASE WHEN followed_bookings.user_id IS NULL THEN FALSE ELSE TRUE END AS hasFollowedParticipants,
              CASE WHEN circle_bookings.user_id IS NULL THEN FALSE ELSE TRUE END AS hasCircleMembers
         FROM events
         LEFT JOIN event_bookings AS my_bookings
           ON my_bookings.event_id = events.id
          AND my_bookings.user_id = ${devUserId}
         LEFT JOIN (
           SELECT DISTINCT event_bookings.event_id, event_bookings.user_id
             FROM event_bookings
             INNER JOIN follows
               ON follows.followed_user_id = event_bookings.user_id
              AND follows.follower_user_id = ${devUserId}
         ) AS followed_bookings
           ON followed_bookings.event_id = events.id
         LEFT JOIN (
           SELECT DISTINCT event_bookings.event_id, event_bookings.user_id
             FROM event_bookings
             INNER JOIN circle_members AS other_members
               ON other_members.user_id = event_bookings.user_id
             INNER JOIN circle_members AS my_members
               ON my_members.circle_id = other_members.circle_id
              AND my_members.user_id = ${devUserId}
            WHERE event_bookings.user_id <> ${devUserId}
         ) AS circle_bookings
           ON circle_bookings.event_id = events.id
        WHERE events.status = 'approved'
        GROUP BY events.id, my_bookings.id, followed_bookings.user_id, circle_bookings.user_id
        ORDER BY events.start_date ASC`
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.get('/api/admin/stats', async (_req, res, next) => {
  try {
    const [[users]] = await pool.query('SELECT COUNT(*) AS count FROM users');
    const [[events]] = await pool.query('SELECT COUNT(*) AS count FROM events');
    const [[approvedEvents]] = await pool.query(
      "SELECT COUNT(*) AS count FROM events WHERE status = 'approved'",
    );
    const [[bookings]] = await pool.query('SELECT COUNT(*) AS count FROM event_bookings');
    const [[locations]] = await pool.query('SELECT COUNT(*) AS count FROM shared_locations');
    const [[circles]] = await pool.query('SELECT COUNT(*) AS count FROM circles');
    const [[submissions]] = await pool.query('SELECT COUNT(*) AS count FROM event_submissions');
    res.json({
      users: users.count,
      events: events.count,
      approvedEvents: approvedEvents.count,
      bookings: bookings.count,
      sharedLocations: locations.count,
      circles: circles.count,
      eventSubmissions: submissions.count,
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/admin/events', async (_req, res, next) => {
  try {
    const [rows] = await pool.query(
      `SELECT id, source_key AS sourceKey, category, name,
              source_type AS sourceType, source_name AS sourceName,
              source_url AS sourceUrl, image_url AS imageUrl,
              DATE_FORMAT(start_date, '%Y-%m-%d') AS startDate,
              DATE_FORMAT(end_date, '%Y-%m-%d') AS endDate,
              venue, fee, organizer, description, status
         FROM events
        ORDER BY start_date DESC, id DESC`,
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.post('/api/admin/sync-doujin-events', syncDoujinEvents);
app.post('/api/admin/events/sync-doujin', syncDoujinEvents);

app.post('/api/admin/events', async (req, res, next) => {
  try {
    const {
      category = '綜合',
      name,
      startDate,
      endDate,
      venue,
      fee = '',
      organizer = '',
      description = '',
      status = 'approved',
      imageUrl = '',
      sourceUrl = '',
      sourceType = 1,
      sourceName = '管理後台',
    } = req.body;
    const [result] = await pool.execute(
      `INSERT INTO events
        (source_key, source_type, source_name, source_url, image_url, category, name, start_date, end_date, venue, fee, organizer, description, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        `admin-${Date.now()}`,
        sourceType,
        sourceName,
        sourceUrl,
        imageUrl,
        category,
        name,
        startDate,
        endDate ?? startDate,
        venue,
        fee,
        organizer,
        description,
        status,
      ],
    );
    res.status(201).json({ id: result.insertId });
  } catch (error) {
    next(error);
  }
});

async function syncDoujinEvents(_req, res, next) {
  try {
    const events = await importEvents(pool);
    res.json({ imported: true, count: events.length });
  } catch (error) {
    next(error);
  }
}

app.delete('/api/admin/events/:eventId', async (req, res, next) => {
  try {
    await pool.execute('DELETE FROM events WHERE id = ?', [req.params.eventId]);
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.get('/api/admin/event-submissions', async (_req, res, next) => {
  try {
    const [rows] = await pool.query(
      `SELECT id, name,
              DATE_FORMAT(start_date, '%Y-%m-%d') AS startDate,
              DATE_FORMAT(end_date, '%Y-%m-%d') AS endDate,
              venue, description,
              review_status AS reviewStatus,
              DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%s') AS createdAt
         FROM event_submissions
        ORDER BY created_at DESC`,
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.post('/api/admin/event-submissions/:submissionId/approve', async (req, res, next) => {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [rows] = await connection.execute(
      `SELECT id, name, start_date AS startDate, end_date AS endDate, venue, description
         FROM event_submissions
        WHERE id = ?
          AND review_status = 'pending'
        FOR UPDATE`,
      [req.params.submissionId],
    );
    const submission = rows[0];
    if (!submission) {
      await connection.rollback();
      res.status(404).json({ error: 'pending_submission_not_found' });
      return;
    }

    const [result] = await connection.execute(
      `INSERT INTO events
        (source_key, source_type, source_name, category, name, start_date, end_date, venue, fee, organizer, description, status)
       VALUES (?, 2, '投稿活動', '投稿', ?, ?, ?, ?, '', '使用者投稿', ?, 'approved')`,
      [
        `submission-${submission.id}`,
        submission.name,
        submission.startDate,
        submission.endDate,
        submission.venue,
        submission.description,
      ],
    );
    await connection.execute(
      `UPDATE event_submissions
          SET review_status = 'approved'
        WHERE id = ?`,
      [submission.id],
    );
    await connection.commit();
    res.status(201).json({ eventId: result.insertId });
  } catch (error) {
    await connection.rollback();
    next(error);
  } finally {
    connection.release();
  }
});

app.post('/api/admin/event-submissions/:submissionId/reject', async (req, res, next) => {
  try {
    await pool.execute(
      `UPDATE event_submissions
          SET review_status = 'rejected'
        WHERE id = ?
          AND review_status = 'pending'`,
      [req.params.submissionId],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.get('/api/circles', async (_req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT circles.id,
              circles.name,
              circles.invite_code AS inviteCode,
              circles.invite_url AS inviteUrl,
              circles.owner_user_id AS ownerUserId,
              COUNT(circle_members.user_id) AS memberCount,
              CASE WHEN circles.owner_user_id = ? THEN TRUE ELSE FALSE END AS isOwner
         FROM circles
         INNER JOIN circle_members
           ON circle_members.circle_id = circles.id
        WHERE circles.id IN (
          SELECT my_circles.circle_id
            FROM circle_members AS my_circles
           WHERE my_circles.user_id = ?
        )
        GROUP BY circles.id
        ORDER BY circles.created_at DESC`,
      [devUserId, devUserId],
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.post('/api/circles', async (req, res, next) => {
  const connection = await pool.getConnection();
  try {
    const { name } = req.body;
    const inviteCode = await createInviteCode(connection);
    const inviteUrl = `https://coscircle.local/join/${inviteCode}`;

    await connection.beginTransaction();
    const [result] = await connection.execute(
      `INSERT INTO circles (owner_user_id, name, invite_code, invite_url)
       VALUES (?, ?, ?, ?)`,
      [devUserId, name, inviteCode, inviteUrl],
    );
    await connection.execute(
      `INSERT INTO circle_members (circle_id, user_id)
       VALUES (?, ?)`,
      [result.insertId, devUserId],
    );
    await connection.commit();
    res.status(201).json({ id: result.insertId, inviteCode, inviteUrl });
  } catch (error) {
    await connection.rollback();
    next(error);
  } finally {
    connection.release();
  }
});

app.post('/api/circles/join', async (req, res, next) => {
  try {
    const { invite } = req.body;
    const inviteCode = extractInviteCode(invite);
    const [circles] = await pool.execute(
      `SELECT id FROM circles WHERE invite_code = ?`,
      [inviteCode],
    );
    const circle = circles[0];
    if (!circle) {
      res.status(404).json({ error: 'circle_not_found' });
      return;
    }

    await pool.execute(
      `INSERT IGNORE INTO circle_members (circle_id, user_id)
       VALUES (?, ?)`,
      [circle.id, devUserId],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.delete('/api/circles/:circleId/members/me', async (req, res, next) => {
  try {
    const [circles] = await pool.execute(
      `SELECT owner_user_id AS ownerUserId
         FROM circles
        WHERE id = ?`,
      [req.params.circleId],
    );
    if (circles[0]?.ownerUserId === devUserId) {
      await pool.execute('DELETE FROM circles WHERE id = ?', [req.params.circleId]);
      res.status(204).end();
      return;
    }

    await pool.execute(
      `DELETE FROM circle_members
        WHERE circle_id = ?
          AND user_id = ?`,
      [req.params.circleId, devUserId],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.post('/api/events/submissions', async (req, res, next) => {
  try {
    const { name, startDate, endDate, venue, description } = req.body;
    const [result] = await pool.execute(
      `INSERT INTO event_submissions (name, start_date, end_date, venue, description)
       VALUES (?, ?, ?, ?, ?)`,
      [name, startDate, endDate, venue, description ?? null]
    );
    res.status(201).json({ id: result.insertId, reviewStatus: 'pending' });
  } catch (error) {
    next(error);
  }
});

app.post('/api/events/:eventId/bookings', async (req, res, next) => {
  try {
    const { role, workId, characterName, outfitImageUrl, message } = req.body;
    await pool.execute(
      `INSERT INTO event_bookings (event_id, user_id, role, work_id, character_name, outfit_image_url, message)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE role = VALUES(role),
         work_id = VALUES(work_id),
         character_name = VALUES(character_name),
         outfit_image_url = VALUES(outfit_image_url),
         message = VALUES(message)`,
      [
        req.params.eventId,
        devUserId,
        role,
        workId || null,
        characterName ?? null,
        outfitImageUrl ?? null,
        message ?? null,
      ]
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.delete('/api/events/:eventId/bookings/me', async (req, res, next) => {
  try {
    await pool.execute(
      `DELETE FROM event_bookings
        WHERE event_id = ?
          AND user_id = ?`,
      [req.params.eventId, devUserId],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.get('/api/events/:eventId/participants', async (req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT users.id AS userId,
              users.nickname,
              users.avatar_url AS avatarUrl,
              users.facebook_url AS facebookUrl,
              users.bio,
              event_bookings.role,
              works.id AS workId,
              works.name AS workName,
              event_bookings.character_name AS characterName,
              event_bookings.outfit_image_url AS outfitImageUrl,
              event_bookings.message,
              CASE WHEN users.id = ? THEN TRUE ELSE FALSE END AS isMe,
              CASE WHEN follows.followed_user_id IS NULL THEN FALSE ELSE TRUE END AS isFollowed
         FROM event_bookings
         INNER JOIN users
           ON users.id = event_bookings.user_id
         LEFT JOIN follows
           ON follows.follower_user_id = ?
          AND follows.followed_user_id = users.id
         LEFT JOIN works
           ON works.id = event_bookings.work_id
        WHERE event_bookings.event_id = ?
        ORDER BY event_bookings.updated_at DESC`,
      [devUserId, devUserId, req.params.eventId],
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.post('/api/users/:userId/follow', async (req, res, next) => {
  try {
    if (Number(req.params.userId) === devUserId) {
      res.status(400).json({ error: 'cannot_follow_self' });
      return;
    }
    await pool.execute(
      `INSERT IGNORE INTO follows (follower_user_id, followed_user_id)
       VALUES (?, ?)`,
      [devUserId, req.params.userId],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.delete('/api/users/:userId/follow', async (req, res, next) => {
  try {
    await pool.execute(
      `DELETE FROM follows
        WHERE follower_user_id = ?
          AND followed_user_id = ?`,
      [devUserId, req.params.userId],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.get('/api/events/:eventId/locations', async (req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT shared_locations.user_id AS userId,
              users.nickname,
              users.avatar_url AS avatarUrl,
              event_bookings.role,
              works.id AS workId,
              works.name AS workName,
              event_bookings.character_name AS characterName,
              event_bookings.outfit_image_url AS outfitImageUrl,
              shared_locations.latitude,
              shared_locations.longitude,
              DATE_FORMAT(shared_locations.shared_at, '%Y-%m-%dT%H:%i:%s') AS sharedAt,
              CASE WHEN shared_locations.user_id = ? THEN TRUE ELSE FALSE END AS isMe,
              CASE WHEN follows.followed_user_id IS NULL THEN FALSE ELSE TRUE END AS isFollowed,
              CASE WHEN circle_members.user_id IS NULL THEN FALSE ELSE TRUE END AS isCircleMember
         FROM shared_locations
         INNER JOIN users
           ON users.id = shared_locations.user_id
         LEFT JOIN event_bookings
           ON event_bookings.event_id = shared_locations.event_id
          AND event_bookings.user_id = shared_locations.user_id
         LEFT JOIN works
           ON works.id = event_bookings.work_id
         LEFT JOIN follows
           ON follows.follower_user_id = ?
          AND follows.followed_user_id = shared_locations.user_id
         LEFT JOIN circle_members
           ON circle_members.user_id = shared_locations.user_id
          AND circle_members.circle_id IN (
            SELECT my_circles.circle_id
              FROM circle_members AS my_circles
             WHERE my_circles.user_id = ?
          )
        WHERE shared_locations.event_id = ?
        ORDER BY shared_locations.shared_at DESC`,
      [devUserId, devUserId, devUserId, req.params.eventId],
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.put('/api/events/:eventId/location', async (req, res, next) => {
  try {
    const { latitude, longitude } = req.body;
    await pool.execute(
      `INSERT INTO shared_locations (event_id, user_id, latitude, longitude, shared_at)
       VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
       ON DUPLICATE KEY UPDATE latitude = VALUES(latitude),
         longitude = VALUES(longitude),
         shared_at = CURRENT_TIMESTAMP`,
      [req.params.eventId, devUserId, latitude, longitude]
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.use((error, _req, res, _next) => {
  console.error(error);
  res.status(500).json({ error: 'internal_server_error' });
});

const port = Number(process.env.PORT ?? 8080);
await ensureDevUser();

app.listen(port, () => {
  console.log(`CosCircle API listening on ${port}`);
});

function scheduleDailyEventImport() {
  let running = false;
  let lastRunDate = '';

  setInterval(async () => {
    const now = timePartsInZone(eventScraperTimeZone);
    if (now.hour !== 12 || now.minute !== 0 || lastRunDate === now.date || running) {
      return;
    }

    running = true;
    lastRunDate = now.date;
    try {
      const events = await importEvents(pool);
      console.log(
        `[event-scraper] imported ${events.length} events from Doujin at ${now.date} 12:00 ${eventScraperTimeZone}`,
      );
    } catch (error) {
      console.error('[event-scraper] daily import failed', error);
    } finally {
      running = false;
    }
  }, 30 * 1000);
}

function timePartsInZone(timeZone) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return {
    date: `${values.year}-${values.month}-${values.day}`,
    hour: Number(values.hour),
    minute: Number(values.minute),
  };
}

async function ensureDevUser() {
  await pool.execute(
    `INSERT INTO users (id, provider, provider_user_id, nickname, avatar_url, facebook_url, bio)
     VALUES (?, 'dev', 'local-user', '圈圈新朋友', '', '', '')
     ON DUPLICATE KEY UPDATE nickname = nickname`,
    [devUserId],
  );
}

async function fetchUserPitWorks(userId) {
  const [rows] = await pool.execute(
    `SELECT works.id, works.name
       FROM user_pit_works
       INNER JOIN works
         ON works.id = user_pit_works.work_id
      WHERE user_pit_works.user_id = ?
      ORDER BY works.name ASC`,
    [userId],
  );
  return rows;
}

async function createInviteCode(connection) {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const code = `CC-${Math.random().toString(36).slice(2, 8).toUpperCase()}`;
    const [rows] = await connection.execute(
      'SELECT id FROM circles WHERE invite_code = ?',
      [code],
    );
    if (rows.length === 0) return code;
  }
  throw new Error('Unable to generate unique invite code');
}

function extractInviteCode(invite) {
  const value = String(invite ?? '').trim();
  const parts = value.split('/');
  return parts[parts.length - 1].trim().toUpperCase();
}
