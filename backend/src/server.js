import 'dotenv/config';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import cors from 'cors';
import express from 'express';
import { importEvents } from '../scripts/scrape-events.js';
import { createPool } from './db.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const uploadDir = path.resolve(__dirname, '..', 'uploads');
const app = express();
const pool = createPool();
const devUserId = 1;
const scrypt = promisify(crypto.scrypt);
const isProduction = process.env.NODE_ENV === 'production';
const eventScraperEnabled = process.env.EVENT_SCRAPER_ENABLED !== 'false';
const eventScraperTimeZone = process.env.EVENT_SCRAPER_TIME_ZONE ?? 'Asia/Taipei';
const maxUploadImageBytes = 5 * 1024 * 1024;
const corsOrigins = String(process.env.CORS_ORIGINS ?? '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

app.use(
  cors({
    origin(origin, callback) {
      if (!origin) {
        callback(null, true);
        return;
      }
      if (!isProduction && corsOrigins.length === 0) {
        callback(null, true);
        return;
      }
      if (corsOrigins.includes(origin)) {
        callback(null, true);
        return;
      }
      callback(new Error('cors_origin_not_allowed'));
    },
  }),
);
app.use(express.json({ limit: '10mb' }));
app.use('/uploads', express.static(uploadDir));

function encodeInteractionTags(value) {
  if (!Array.isArray(value)) return null;
  const tags = value
    .map((item) => String(item).trim())
    .filter((item) => item.length > 0);
  return tags.length === 0 ? null : tags.join(',');
}

function createRateLimiter({ windowMs, max }) {
  const buckets = new Map();
  return (req, res, next) => {
    const now = Date.now();
    const userKey = req.user?.id ?? req.ip ?? 'unknown';
    const key = `${req.method}:${req.baseUrl}:${userKey}`;
    const current = buckets.get(key);
    if (!current || current.resetAt <= now) {
      buckets.set(key, { count: 1, resetAt: now + windowMs });
      next();
      return;
    }
    current.count += 1;
    if (current.count > max) {
      res
        .status(429)
        .set('Retry-After', Math.ceil((current.resetAt - now) / 1000).toString())
        .json({ error: 'rate_limit_exceeded' });
      return;
    }
    next();
  };
}

if (eventScraperEnabled) {
  scheduleDailyEventImport();
}

app.get('/api/health', (_req, res) => res.json({ ok: true, name: 'CosCircle API' }));

app.use('/api/auth', createRateLimiter({ windowMs: 15 * 60 * 1000, max: 30 }));
app.use('/api/uploads', createRateLimiter({ windowMs: 60 * 60 * 1000, max: 80 }));
app.use('/api/events/submissions', createRateLimiter({ windowMs: 60 * 60 * 1000, max: 20 }));
app.use('/api/circles/join', createRateLimiter({ windowMs: 15 * 60 * 1000, max: 30 }));
app.use('/api/recognitions', createRateLimiter({ windowMs: 15 * 60 * 1000, max: 60 }));

app.post('/api/auth/register', async (req, res, next) => {
  try {
    const email = normalizeEmail(req.body.email);
    const password = String(req.body.password ?? '');
    const nickname = String(req.body.nickname ?? '').trim() || '圈圈新朋友';
    if (!email || password.length < 8) {
      console.warn('[auth/register] invalid input', {
        email,
        hasEmail: Boolean(email),
        passwordLength: password.length,
      });
      res.status(400).json({ error: 'invalid_email_or_password' });
      return;
    }

    const passwordHash = await hashPassword(password);
    const sessionToken = createSessionToken();
    const [result] = await pool.execute(
      `INSERT INTO users (
         provider, provider_user_id, public_code, email, password_hash, session_token, nickname,
         avatar_url, facebook_url, bio
       )
       VALUES ('email', ?, ?, ?, ?, ?, ?, '', '', '')`,
      [email, createPublicCode(), email, passwordHash, sessionToken, nickname],
    );
    const profile = await fetchUserProfile(result.insertId);
    console.info('[auth/register] success', { email, userId: result.insertId });
    res.status(201).json({ token: sessionToken, user: profile, isNewUser: true });
  } catch (error) {
    if (error.code === 'ER_DUP_ENTRY') {
      console.warn('[auth/register] duplicate email', {
        email: normalizeEmail(req.body.email),
      });
      res.status(409).json({ error: 'email_already_registered' });
      return;
    }
    next(error);
  }
});

app.post('/api/auth/login', async (req, res, next) => {
  try {
    const email = normalizeEmail(req.body.email);
    const password = String(req.body.password ?? '');
    console.info('[auth/login] attempt', { email });
    const [rows] = await pool.execute(
      `SELECT id, password_hash AS passwordHash
         FROM users
        WHERE email = ?
        LIMIT 1`,
      [email],
    );
    const user = rows[0];
    if (!user) {
      console.warn('[auth/login] failed', { email, reason: 'user_not_found' });
      res.status(401).json({ error: 'invalid_credentials' });
      return;
    }
    if (!user.passwordHash) {
      console.warn('[auth/login] failed', {
        email,
        userId: user.id,
        reason: 'missing_password_hash',
      });
      res.status(401).json({ error: 'invalid_credentials' });
      return;
    }
    if (!(await verifyPassword(password, user.passwordHash))) {
      console.warn('[auth/login] failed', {
        email,
        userId: user.id,
        reason: 'bad_password',
      });
      res.status(401).json({ error: 'invalid_credentials' });
      return;
    }

    const sessionToken = createSessionToken();
    await pool.execute('UPDATE users SET session_token = ? WHERE id = ?', [
      sessionToken,
      user.id,
    ]);
    console.info('[auth/login] success', { email, userId: user.id });
    res.json({
      token: sessionToken,
      user: await fetchUserProfile(user.id),
      isNewUser: false,
    });
  } catch (error) {
    console.error('[auth/login] error', {
      email: normalizeEmail(req.body.email),
      message: error.message,
    });
    next(error);
  }
});

app.post('/api/auth/logout', async (req, res, next) => {
  try {
    const token = bearerToken(req);
    if (token) {
      await pool.execute('UPDATE users SET session_token = NULL WHERE session_token = ?', [
        token,
      ]);
    }
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.post('/api/auth/social', async (req, res, next) => {
  try {
    const provider = String(req.body.provider ?? '').trim().toLowerCase();
    const accessToken = String(req.body.accessToken ?? '').trim();
    if (!['facebook', 'line'].includes(provider) || accessToken.length < 12) {
      res.status(400).json({ error: 'invalid_social_login' });
      return;
    }

    const socialProfile = await fetchSocialProfile(provider, accessToken);
    if (!socialProfile?.id) {
      res.status(401).json({ error: 'invalid_social_token' });
      return;
    }

    const sessionToken = createSessionToken();
    const [existingRows] = await pool.execute(
      `SELECT id
         FROM users
        WHERE provider = ?
          AND provider_user_id = ?
        LIMIT 1`,
      [provider, socialProfile.id],
    );
    let userId = existingRows[0]?.id;
    let isNewUser = false;
    if (userId) {
      await pool.execute(
        `UPDATE users
            SET session_token = ?,
                email = COALESCE(email, ?),
                nickname = CASE
                  WHEN nickname = '' OR nickname = '圈圈新朋友' THEN ?
                  ELSE nickname
                END
          WHERE id = ?`,
        [sessionToken, socialProfile.email, socialProfile.nickname, userId],
      );
    } else {
      isNewUser = true;
      const [result] = await pool.execute(
        `INSERT INTO users (
           provider, provider_user_id, public_code, email, password_hash, session_token,
           nickname, avatar_url, facebook_url, bio
         )
         VALUES (?, ?, ?, ?, NULL, ?, ?, ?, '', '')`,
        [
          provider,
          socialProfile.id,
          createPublicCode(),
          socialProfile.email,
          sessionToken,
          socialProfile.nickname,
          socialProfile.avatarUrl,
        ],
      );
      userId = result.insertId;
    }
    res.json({
      token: sessionToken,
      user: await fetchUserProfile(userId),
      isNewUser,
    });
  } catch (error) {
    if (error?.message === 'invalid_social_token') {
      res.status(401).json({ error: 'invalid_social_token' });
      return;
    }
    next(error);
  }
});

app.use(async (req, _res, next) => {
  try {
    if (req.path.startsWith('/api/profiles/')) {
      next();
      return;
    }
    req.userId = await resolveUserId(req);
    if (!req.userId) {
      _res.status(401).json({ error: 'authentication_required' });
      return;
    }
    next();
  } catch (error) {
    next(error);
  }
});

app.get('/api/me', async (req, res, next) => {
  try {
    res.json(await fetchUserProfile(req.userId));
  } catch (error) {
    next(error);
  }
});

app.put('/api/me', async (req, res, next) => {
  const connection = await pool.getConnection();
  try {
    const {
      nickname,
      avatarUrl,
      facebookUrl,
      bio,
      age,
      regions = [],
      travelRegions = [],
      travelSameRegion = false,
      landmine,
      gender = 'private',
      otherPhotoUrls = [],
      pitWorkIds = [],
      deepPitWorkIds = pitWorkIds,
      shallowPitWorkIds = [],
    } = req.body;
    const normalizedRegions = normalizeStringArray(regions, [
      '北部',
      '中部',
      '南部',
      '離島',
      '海外',
    ]);
    const normalizedTravelRegions = normalizeStringArray(travelRegions, [
      '北部',
      '中部',
      '南部',
      '離島',
      '海外',
    ]);
    const normalizedGender = ['male', 'female', 'private'].includes(gender)
      ? gender
      : 'private';
    const normalizedPhotoUrls = normalizeStringArray(otherPhotoUrls).slice(0, 3);
    await connection.beginTransaction();
    await connection.execute(
      `UPDATE users
          SET nickname = ?,
              avatar_url = ?,
              facebook_url = ?,
              bio = ?,
              age = ?,
              regions_json = ?,
              travel_regions_json = ?,
              travel_same_region = ?,
              landmine = ?,
              gender = ?,
              other_photo_urls_json = ?
        WHERE id = ?`,
      [
        nickname,
        avatarUrl ?? null,
        facebookUrl ?? null,
        bio ?? null,
        age ?? null,
        JSON.stringify(normalizedRegions),
        JSON.stringify(normalizedTravelRegions),
        travelSameRegion ||
        sameStringSet(normalizedRegions, normalizedTravelRegions)
          ? 1
          : 0,
        landmine ?? null,
        normalizedGender,
        JSON.stringify(normalizedPhotoUrls),
        req.userId,
      ],
    );
    await connection.execute('DELETE FROM user_pit_works WHERE user_id = ?', [
      req.userId,
    ]);
    for (const workId of normalizeIdArray(deepPitWorkIds)) {
      await connection.execute(
        `INSERT IGNORE INTO user_pit_works (user_id, work_id, depth)
         VALUES (?, ?, 'deep')`,
        [req.userId, workId],
      );
    }
    for (const workId of normalizeIdArray(shallowPitWorkIds)) {
      await connection.execute(
        `INSERT IGNORE INTO user_pit_works (user_id, work_id, depth)
         VALUES (?, ?, 'shallow')`,
        [req.userId, workId],
      );
    }
    await connection.commit();
    res.json(await fetchUserProfile(req.userId));
  } catch (error) {
    await connection.rollback();
    next(error);
  } finally {
    connection.release();
  }
});

app.post('/api/uploads/image', async (req, res, next) => {
  try {
    const { bytesBase64, mimeType } = req.body;
    const extension = imageExtension(mimeType);
    if (!extension || typeof bytesBase64 !== 'string') {
      res.status(400).json({ error: 'invalid_image' });
      return;
    }

    const bytes = Buffer.from(bytesBase64, 'base64');
    if (bytes.length === 0 || bytes.length > maxUploadImageBytes) {
      res.status(400).json({ error: 'invalid_image_size' });
      return;
    }
    if (!isValidImageBytes(bytes, extension)) {
      res.status(400).json({ error: 'invalid_image_bytes' });
      return;
    }

    await fs.mkdir(uploadDir, { recursive: true });
    const fileName = `${crypto.randomUUID()}.${extension}`;
    await fs.writeFile(path.join(uploadDir, fileName), bytes);
    res.status(201).json({ url: publicUploadUrl(req, fileName) });
  } catch (error) {
    next(error);
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
    const [rows] = await pool.execute(
      `SELECT events.id, events.category, events.name,
              DATE_FORMAT(events.start_date, '%Y-%m-%d') AS startDate,
              DATE_FORMAT(events.end_date, '%Y-%m-%d') AS endDate,
              events.venue, events.detailed_address AS detailedAddress,
              events.fee, events.organizer, events.description,
              events.image_url AS imageUrl,
              events.source_type AS sourceType,
              events.source_name AS sourceName,
              events.source_url AS sourceUrl,
              CASE WHEN my_bookings.event_id IS NULL THEN FALSE ELSE TRUE END AS isJoined,
              CASE WHEN followed_bookings.user_id IS NULL THEN FALSE ELSE TRUE END AS hasFollowedParticipants,
              CASE WHEN circle_bookings.user_id IS NULL THEN FALSE ELSE TRUE END AS hasCircleMembers
         FROM events
         LEFT JOIN (
           SELECT DISTINCT event_id
             FROM event_bookings
            WHERE user_id = ?
         ) AS my_bookings
           ON my_bookings.event_id = events.id
         LEFT JOIN (
           SELECT DISTINCT event_bookings.event_id, event_bookings.user_id
             FROM event_bookings
             INNER JOIN follows
               ON follows.followed_user_id = event_bookings.user_id
              AND follows.follower_user_id = ?
         ) AS followed_bookings
           ON followed_bookings.event_id = events.id
         LEFT JOIN (
           SELECT DISTINCT event_bookings.event_id, event_bookings.user_id
             FROM event_bookings
             INNER JOIN circle_members AS other_members
               ON other_members.user_id = event_bookings.user_id
             INNER JOIN circle_members AS my_members
               ON my_members.circle_id = other_members.circle_id
              AND my_members.user_id = ?
            WHERE event_bookings.user_id <> ?
         ) AS circle_bookings
           ON circle_bookings.event_id = events.id
        WHERE events.status = 'approved'
        GROUP BY events.id, my_bookings.event_id, followed_bookings.user_id, circle_bookings.user_id
        ORDER BY events.start_date ASC`,
      [req.userId, req.userId, req.userId, req.userId],
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.use('/api/admin', requireAdmin);

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
              venue, detailed_address AS detailedAddress,
              fee, organizer, description, status
         FROM events
        ORDER BY start_date DESC, id DESC`,
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.get('/api/admin/users', async (req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT id, email, nickname, is_admin AS isAdmin,
              CASE WHEN id = ? THEN TRUE ELSE FALSE END AS isMe,
              DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%s') AS createdAt
         FROM users
        ORDER BY created_at DESC, id DESC`,
      [req.userId],
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
    const payload = normalizeAdminEventPayload(req.body);
    if (!payload.ok) {
      res.status(400).json({ error: payload.error });
      return;
    }
    const [result] = await pool.execute(
      `INSERT INTO events
        (source_key, source_type, source_name, source_url, image_url, category, name, start_date, end_date, venue, detailed_address, fee, organizer, description, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        `admin-${Date.now()}`,
        payload.sourceType,
        payload.sourceName,
        payload.sourceUrl,
        payload.imageUrl,
        payload.category,
        payload.name,
        payload.startDate,
        payload.endDate,
        payload.venue,
        payload.detailedAddress,
        payload.fee,
        payload.organizer,
        payload.description,
        payload.status,
      ],
    );
    res.status(201).json({ id: result.insertId });
  } catch (error) {
    next(error);
  }
});

app.put('/api/admin/events/:eventId', async (req, res, next) => {
  try {
    const payload = normalizeAdminEventPayload(req.body);
    if (!payload.ok) {
      res.status(400).json({ error: payload.error });
      return;
    }
    const [result] = await pool.execute(
      `UPDATE events
          SET source_type = ?,
              source_name = ?,
              source_url = ?,
              image_url = ?,
              category = ?,
              name = ?,
              start_date = ?,
              end_date = ?,
              venue = ?,
              detailed_address = ?,
              fee = ?,
              organizer = ?,
              description = ?,
              status = ?
        WHERE id = ?`,
      [
        payload.sourceType,
        payload.sourceName,
        payload.sourceUrl,
        payload.imageUrl,
        payload.category,
        payload.name,
        payload.startDate,
        payload.endDate,
        payload.venue,
        payload.detailedAddress,
        payload.fee,
        payload.organizer,
        payload.description,
        payload.status,
        req.params.eventId,
      ],
    );
    if (result.affectedRows === 0) {
      res.status(404).json({ error: 'event_not_found' });
      return;
    }
    await recordAdminAction(req, 'event.update', req.params.eventId, payload);
    res.status(204).end();
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
    const [result] = await pool.execute('DELETE FROM events WHERE id = ?', [
      req.params.eventId,
    ]);
    if (result.affectedRows === 0) {
      res.status(404).json({ error: 'event_not_found' });
      return;
    }
    await recordAdminAction(req, 'event.delete', req.params.eventId);
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.put('/api/admin/events/:eventId/dates', async (req, res, next) => {
  try {
    const startDate = String(req.body.startDate ?? '').trim();
    const endDate = String(req.body.endDate ?? startDate).trim();
    if (!isDateOnly(startDate) || !isDateOnly(endDate)) {
      res.status(400).json({ error: 'invalid_date' });
      return;
    }
    if (endDate < startDate) {
      res.status(400).json({ error: 'end_before_start' });
      return;
    }
    const [result] = await pool.execute(
      `UPDATE events
          SET start_date = ?,
              end_date = ?
        WHERE id = ?`,
      [startDate, endDate, req.params.eventId],
    );
    if (result.affectedRows === 0) {
      res.status(404).json({ error: 'event_not_found' });
      return;
    }
    await recordAdminAction(req, 'event.update_dates', req.params.eventId, {
      startDate,
      endDate,
    });
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.delete('/api/admin/users/:userId', async (req, res, next) => {
  try {
    const userId = Number(req.params.userId);
    if (!Number.isInteger(userId)) {
      res.status(400).json({ error: 'invalid_user_id' });
      return;
    }
    if (userId === Number(req.userId)) {
      res.status(400).json({ error: 'cannot_delete_self' });
      return;
    }
    const [result] = await pool.execute('DELETE FROM users WHERE id = ?', [
      userId,
    ]);
    if (result.affectedRows === 0) {
      res.status(404).json({ error: 'user_not_found' });
      return;
    }
    await recordAdminAction(req, 'user.delete', userId);
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
              venue, detailed_address AS detailedAddress, description,
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
      `SELECT id, name, start_date AS startDate, end_date AS endDate,
              venue, detailed_address AS detailedAddress, description
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
        (source_key, source_type, source_name, category, name, start_date, end_date, venue, detailed_address, fee, organizer, description, status)
       VALUES (?, 2, '投稿活動', '投稿', ?, ?, ?, ?, ?, '', '使用者投稿', ?, 'approved')`,
      [
        `submission-${submission.id}`,
        submission.name,
        submission.startDate,
        submission.endDate,
        submission.venue,
        submission.detailedAddress || submission.venue,
        submission.description,
      ],
    );
    await connection.execute(
      `UPDATE event_submissions
          SET review_status = 'approved'
        WHERE id = ?`,
      [submission.id],
    );
    await recordAdminAction(
      req,
      'submission.approve',
      submission.id,
      { eventId: result.insertId },
      connection,
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
    const [result] = await pool.execute(
      `UPDATE event_submissions
          SET review_status = 'rejected'
        WHERE id = ?
          AND review_status = 'pending'`,
      [req.params.submissionId],
    );
    if (result.affectedRows === 0) {
      res.status(404).json({ error: 'pending_submission_not_found' });
      return;
    }
    await recordAdminAction(req, 'submission.reject', req.params.submissionId);
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.get('/api/circles', async (req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT circles.id,
              circles.name,
              circles.description,
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
      [req.userId, req.userId],
    );
    const circleIds = rows.map((row) => row.id);
    const membersByCircle = new Map();
    if (circleIds.length > 0) {
      const placeholders = circleIds.map(() => '?').join(',');
      const [members] = await pool.execute(
        `SELECT circle_members.circle_id AS circleId,
                users.id AS userId,
                users.public_code AS publicCode,
                users.nickname,
                users.avatar_url AS avatarUrl,
                CASE WHEN circles.owner_user_id = users.id THEN TRUE ELSE FALSE END AS isOwner
           FROM circle_members
           INNER JOIN users
             ON users.id = circle_members.user_id
           INNER JOIN circles
             ON circles.id = circle_members.circle_id
          WHERE circle_members.circle_id IN (${placeholders})
          ORDER BY isOwner DESC, circle_members.created_at ASC`,
        circleIds,
      );
      for (const member of members) {
        const key = String(member.circleId);
        if (!membersByCircle.has(key)) membersByCircle.set(key, []);
        membersByCircle.get(key).push(member);
      }
    }
    res.json(
      rows.map((row) => ({
        ...row,
        members: membersByCircle.get(String(row.id)) ?? [],
      })),
    );
  } catch (error) {
    next(error);
  }
});

app.post('/api/circles', async (req, res, next) => {
  const connection = await pool.getConnection();
  try {
    const { name, description } = req.body;
    const inviteCode = await createInviteCode(connection);
    const inviteUrl = `https://coscircle.local/join/${inviteCode}`;

    await connection.beginTransaction();
    const [result] = await connection.execute(
      `INSERT INTO circles (owner_user_id, name, description, invite_code, invite_url)
       VALUES (?, ?, ?, ?, ?)`,
      [req.userId, name, String(description ?? '').trim() || null, inviteCode, inviteUrl],
    );
    await connection.execute(
      `INSERT INTO circle_members (circle_id, user_id)
       VALUES (?, ?)`,
      [result.insertId, req.userId],
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

app.put('/api/circles/:circleId', async (req, res, next) => {
  try {
    const name = String(req.body.name ?? '').trim();
    const description = String(req.body.description ?? '').trim();
    if (!name) {
      res.status(400).json({ error: 'circle_name_required' });
      return;
    }
    const [result] = await pool.execute(
      `UPDATE circles
          SET name = ?,
              description = ?
        WHERE id = ?
          AND owner_user_id = ?`,
      [name, description || null, req.params.circleId, req.userId],
    );
    if (result.affectedRows === 0) {
      res.status(404).json({ error: 'circle_not_found' });
      return;
    }
    res.status(204).end();
  } catch (error) {
    next(error);
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
      [circle.id, req.userId],
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
    if (circles[0]?.ownerUserId === req.userId) {
      await pool.execute('DELETE FROM circles WHERE id = ?', [req.params.circleId]);
      res.status(204).end();
      return;
    }

    await pool.execute(
      `DELETE FROM circle_members
        WHERE circle_id = ?
          AND user_id = ?`,
      [req.params.circleId, req.userId],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.delete('/api/circles/:circleId/members/:userId', async (req, res, next) => {
  try {
    const [circles] = await pool.execute(
      `SELECT owner_user_id AS ownerUserId
         FROM circles
        WHERE id = ?
        LIMIT 1`,
      [req.params.circleId],
    );
    const circle = circles[0];
    if (!circle || circle.ownerUserId !== req.userId) {
      res.status(404).json({ error: 'circle_not_found' });
      return;
    }
    if (Number(req.params.userId) === req.userId) {
      res.status(400).json({ error: 'cannot_remove_owner' });
      return;
    }
    await pool.execute(
      `DELETE FROM circle_members
        WHERE circle_id = ?
          AND user_id = ?`,
      [req.params.circleId, req.params.userId],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.get('/api/following', async (req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT users.id AS userId,
              users.public_code AS publicCode,
              users.nickname,
              users.avatar_url AS avatarUrl,
              users.bio,
              DATE_FORMAT(follows.created_at, '%Y-%m-%dT%H:%i:%s') AS followedAt
         FROM follows
         INNER JOIN users
           ON users.id = follows.followed_user_id
        WHERE follows.follower_user_id = ?
        ORDER BY follows.created_at DESC`,
      [req.userId],
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.post('/api/events/submissions', async (req, res, next) => {
  try {
    const name = String(req.body.name ?? '').trim();
    const startDate = String(req.body.startDate ?? '').trim();
    const endDate = String(req.body.endDate ?? startDate).trim();
    const venue = String(req.body.venue ?? '').trim();
    const detailedAddress = String(req.body.detailedAddress ?? '').trim() || venue;
    const description = String(req.body.description ?? '').trim();
    if (!name) {
      res.status(400).json({ error: 'event_name_required' });
      return;
    }
    if (!venue) {
      res.status(400).json({ error: 'event_venue_required' });
      return;
    }
    if (!isDateOnly(startDate) || !isDateOnly(endDate)) {
      res.status(400).json({ error: 'invalid_date' });
      return;
    }
    if (endDate < startDate) {
      res.status(400).json({ error: 'end_before_start' });
      return;
    }
    const [result] = await pool.execute(
      `INSERT INTO event_submissions
        (name, start_date, end_date, venue, detailed_address, description)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [
        name,
        startDate,
        endDate,
        venue,
        detailedAddress,
        description || null,
      ]
    );
    res.status(201).json({ id: result.insertId, reviewStatus: 'pending' });
  } catch (error) {
    next(error);
  }
});

app.post('/api/events/:eventId/bookings', async (req, res, next) => {
  try {
    const {
      role,
      dayIndex = 1,
      workId,
      characterName,
      outfitImageUrl,
      interactionTags,
      availableTime,
      presenceStatus,
      message,
    } = req.body;
    const normalizedRole = String(role ?? '').trim();
    if (!['coser', 'photographer', 'manager', 'self'].includes(normalizedRole)) {
      res.status(400).json({ error: 'invalid_booking_role' });
      return;
    }
    const normalizedDayIndex = Math.max(
      1,
      Number.parseInt(dayIndex, 10) || 1,
    );
    const [[event]] = await pool.execute(
      `SELECT start_date AS startDate, end_date AS endDate, status
         FROM events
        WHERE id = ?
        LIMIT 1`,
      [req.params.eventId],
    );
    if (!event || event.status !== 'approved') {
      res.status(404).json({ error: 'event_not_found' });
      return;
    }
    const eventDayCount = daysBetweenDates(event.startDate, event.endDate) + 1;
    if (normalizedDayIndex > eventDayCount) {
      res.status(400).json({ error: 'invalid_day_index' });
      return;
    }
    await pool.execute(
      `INSERT INTO event_bookings (
         event_id, user_id, day_index, role, work_id, character_name, outfit_image_url,
         interaction_tags, available_time, presence_status, message
       )
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE role = VALUES(role),
         work_id = VALUES(work_id),
         character_name = VALUES(character_name),
         outfit_image_url = VALUES(outfit_image_url),
         interaction_tags = VALUES(interaction_tags),
         available_time = VALUES(available_time),
         presence_status = VALUES(presence_status),
         message = VALUES(message)`,
      [
        req.params.eventId,
        req.userId,
        normalizedDayIndex,
        normalizedRole,
        workId || null,
        characterName ?? null,
        outfitImageUrl ?? null,
        encodeInteractionTags(interactionTags),
        availableTime ?? null,
        presenceStatus ?? 'open',
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
    const dayIndex = Number.parseInt(req.query.dayIndex, 10);
    if (Number.isFinite(dayIndex) && dayIndex > 0) {
      await pool.execute(
        `DELETE FROM event_bookings
          WHERE event_id = ?
            AND user_id = ?
            AND day_index = ?`,
        [req.params.eventId, req.userId, dayIndex],
      );
      res.status(204).end();
      return;
    }
    await pool.execute(
      `DELETE FROM event_bookings
        WHERE event_id = ?
          AND user_id = ?`,
      [req.params.eventId, req.userId],
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
              users.public_code AS publicCode,
              users.nickname,
              users.avatar_url AS avatarUrl,
              users.facebook_url AS facebookUrl,
              users.bio,
              event_bookings.role,
              event_bookings.day_index AS dayIndex,
              works.id AS workId,
              works.name AS workName,
              event_bookings.character_name AS characterName,
              event_bookings.outfit_image_url AS outfitImageUrl,
              event_bookings.interaction_tags AS interactionTags,
              event_bookings.available_time AS availableTime,
              event_bookings.presence_status AS presenceStatus,
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
        ORDER BY event_bookings.day_index ASC, event_bookings.updated_at DESC`,
      [req.userId, req.userId, req.params.eventId],
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.post('/api/users/:userId/follow', async (req, res, next) => {
  try {
    if (Number(req.params.userId) === req.userId) {
      res.status(400).json({ error: 'cannot_follow_self' });
      return;
    }
    await pool.execute(
      `INSERT IGNORE INTO follows (follower_user_id, followed_user_id)
       VALUES (?, ?)`,
      [req.userId, req.params.userId],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.get('/api/profiles/:publicCode', async (req, res, next) => {
  try {
    const viewerUserId = await resolveUserId(req);
    const profile = await fetchUserProfileByPublicCode(
      req.params.publicCode,
      viewerUserId,
    );
    if (!profile) {
      res.status(404).json({ error: 'user_not_found' });
      return;
    }
    res.json(profile);
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
      [req.userId, req.params.userId],
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
              users.public_code AS publicCode,
              users.nickname,
              users.avatar_url AS avatarUrl,
              event_bookings.role,
              event_bookings.day_index AS dayIndex,
              works.id AS workId,
              works.name AS workName,
              event_bookings.character_name AS characterName,
              event_bookings.outfit_image_url AS outfitImageUrl,
              event_bookings.interaction_tags AS interactionTags,
              event_bookings.available_time AS availableTime,
              event_bookings.presence_status AS presenceStatus,
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
          AND (
            shared_locations.user_id = ?
            OR follows.followed_user_id IS NOT NULL
            OR circle_members.user_id IS NOT NULL
          )
        ORDER BY shared_locations.shared_at DESC`,
      [req.userId, req.userId, req.userId, req.params.eventId, req.userId],
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.put('/api/events/:eventId/location', async (req, res, next) => {
  try {
    const { latitude, longitude } = req.body;
    const lat = Number(latitude);
    const lng = Number(longitude);
    if (!Number.isFinite(lat) || lat < -90 || lat > 90) {
      res.status(400).json({ error: 'invalid_latitude' });
      return;
    }
    if (!Number.isFinite(lng) || lng < -180 || lng > 180) {
      res.status(400).json({ error: 'invalid_longitude' });
      return;
    }
    await pool.execute(
      `INSERT INTO shared_locations (event_id, user_id, latitude, longitude, shared_at)
       VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
       ON DUPLICATE KEY UPDATE latitude = VALUES(latitude),
         longitude = VALUES(longitude),
         shared_at = CURRENT_TIMESTAMP`,
      [req.params.eventId, req.userId, lat, lng]
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.get('/api/events/:eventId/meetups', async (req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT event_meeting_points.id,
              event_meeting_points.event_id AS eventId,
              event_meeting_points.circle_id AS circleId,
              circles.name AS circleName,
              event_meeting_points.creator_user_id AS creatorUserId,
              users.nickname AS creatorNickname,
              event_meeting_points.latitude,
              event_meeting_points.longitude,
              event_meeting_points.description,
              DATE_FORMAT(event_meeting_points.meet_at, '%Y-%m-%dT%H:%i:%s') AS meetAt,
              DATE_FORMAT(event_meeting_points.created_at, '%Y-%m-%dT%H:%i:%s') AS createdAt,
              CASE WHEN event_meeting_points.creator_user_id = ? THEN TRUE ELSE FALSE END AS isMine
         FROM event_meeting_points
         INNER JOIN circles
           ON circles.id = event_meeting_points.circle_id
         INNER JOIN users
           ON users.id = event_meeting_points.creator_user_id
         INNER JOIN circle_members
           ON circle_members.circle_id = event_meeting_points.circle_id
          AND circle_members.user_id = ?
        WHERE event_meeting_points.event_id = ?
        ORDER BY event_meeting_points.meet_at ASC,
                 event_meeting_points.created_at DESC`,
      [req.userId, req.userId, req.params.eventId],
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.post('/api/events/:eventId/meetups', async (req, res, next) => {
  try {
    const { circleId, latitude, longitude, description, meetAt } = req.body;
    const [memberships] = await pool.execute(
      `SELECT circle_id AS circleId
         FROM circle_members
        WHERE circle_id = ?
          AND user_id = ?
        LIMIT 1`,
      [circleId, req.userId],
    );
    if (!memberships[0]) {
      res.status(403).json({ error: 'circle_membership_required' });
      return;
    }

    const [result] = await pool.execute(
      `INSERT INTO event_meeting_points (
         event_id, circle_id, creator_user_id, latitude, longitude, description, meet_at
       )
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [
        req.params.eventId,
        circleId,
        req.userId,
        latitude,
        longitude,
        description ?? null,
        normalizeDateTimeForSql(meetAt),
      ],
    );
    res.status(201).json({ id: result.insertId });
  } catch (error) {
    next(error);
  }
});

app.put('/api/events/:eventId/meetups/:meetupId', async (req, res, next) => {
  try {
    const { circleId, latitude, longitude, description, meetAt } = req.body;
    const [meetups] = await pool.execute(
      `SELECT creator_user_id AS creatorUserId
         FROM event_meeting_points
        WHERE id = ?
          AND event_id = ?
        LIMIT 1`,
      [req.params.meetupId, req.params.eventId],
    );
    const meetup = meetups[0];
    if (!meetup || meetup.creatorUserId !== req.userId) {
      res.status(404).json({ error: 'meetup_not_found' });
      return;
    }

    const [memberships] = await pool.execute(
      `SELECT circle_id AS circleId
         FROM circle_members
        WHERE circle_id = ?
          AND user_id = ?
        LIMIT 1`,
      [circleId, req.userId],
    );
    if (!memberships[0]) {
      res.status(403).json({ error: 'circle_membership_required' });
      return;
    }

    await pool.execute(
      `UPDATE event_meeting_points
          SET circle_id = ?,
              latitude = ?,
              longitude = ?,
              description = ?,
              meet_at = ?
        WHERE id = ?
          AND event_id = ?
          AND creator_user_id = ?`,
      [
        circleId,
        latitude,
        longitude,
        description ?? null,
        normalizeDateTimeForSql(meetAt),
        req.params.meetupId,
        req.params.eventId,
        req.userId,
      ],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.delete('/api/events/:eventId/meetups/:meetupId', async (req, res, next) => {
  try {
    await pool.execute(
      `DELETE FROM event_meeting_points
        WHERE id = ?
          AND event_id = ?
          AND creator_user_id = ?`,
      [req.params.meetupId, req.params.eventId, req.userId],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.get('/api/events/:eventId/recognitions', async (req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT event_recognition_requests.id,
              event_recognition_requests.event_id AS eventId,
              event_recognition_requests.requester_user_id AS requesterUserId,
              requester.nickname AS requesterNickname,
              event_recognition_requests.target_user_id AS targetUserId,
              target.nickname AS targetNickname,
              event_recognition_requests.status,
              event_recognition_requests.response_message AS responseMessage,
              DATE_FORMAT(event_recognition_requests.created_at, '%Y-%m-%dT%H:%i:%s') AS createdAt,
              DATE_FORMAT(event_recognition_requests.responded_at, '%Y-%m-%dT%H:%i:%s') AS respondedAt,
              CASE WHEN event_recognition_requests.requester_user_id = ? THEN TRUE ELSE FALSE END AS isRequester,
              CASE WHEN event_recognition_requests.target_user_id = ? THEN TRUE ELSE FALSE END AS isTarget
         FROM event_recognition_requests
         INNER JOIN users AS requester
           ON requester.id = event_recognition_requests.requester_user_id
         INNER JOIN users AS target
           ON target.id = event_recognition_requests.target_user_id
        WHERE event_recognition_requests.event_id = ?
          AND (
            event_recognition_requests.requester_user_id = ?
            OR event_recognition_requests.target_user_id = ?
          )
        ORDER BY event_recognition_requests.created_at DESC`,
      [req.userId, req.userId, req.params.eventId, req.userId, req.userId],
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.post('/api/events/:eventId/recognitions', async (req, res, next) => {
  try {
    const { targetUserId } = req.body;
    if (Number(targetUserId) === req.userId) {
      res.status(400).json({ error: 'cannot_recognize_self' });
      return;
    }
    const [result] = await pool.execute(
      `INSERT INTO event_recognition_requests (
         event_id, requester_user_id, target_user_id, status
       )
       VALUES (?, ?, ?, 'pending')`,
      [req.params.eventId, req.userId, targetUserId],
    );
    res.status(201).json({ id: result.insertId });
  } catch (error) {
    next(error);
  }
});

app.post('/api/recognitions/:requestId/respond', async (req, res, next) => {
  try {
    const status = String(req.body.status ?? '');
    if (!['come', 'busy'].includes(status)) {
      res.status(400).json({ error: 'invalid_recognition_status' });
      return;
    }
    const responseMessage = status === 'come' ? '快來' : '當前不方便';
    const [result] = await pool.execute(
      `UPDATE event_recognition_requests
          SET status = ?,
              response_message = ?,
              responded_at = CURRENT_TIMESTAMP
        WHERE id = ?
          AND target_user_id = ?
          AND status = 'pending'`,
      [status, responseMessage, req.params.requestId, req.userId],
    );
    if (result.affectedRows === 0) {
      res.status(404).json({ error: 'recognition_request_not_found' });
      return;
    }
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.use((error, _req, res, _next) => {
  if (error?.message === 'cors_origin_not_allowed') {
    res.status(403).json({ error: 'cors_origin_not_allowed' });
    return;
  }
  console.error(error);
  res.status(500).json({ error: 'internal_server_error' });
});

const port = Number(process.env.PORT ?? 8080);
if (!isProduction) {
  await ensureDevUser();
}
await ensureCollaborationTables();

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
    `INSERT INTO users (
       id, provider, provider_user_id, public_code, email, password_hash, session_token,
       is_admin, nickname, avatar_url, facebook_url, bio
     )
     VALUES (?, 'dev', 'local-user', ?, NULL, NULL, NULL, TRUE, '圈圈新朋友', '', '', '')
     ON DUPLICATE KEY UPDATE public_code = COALESCE(public_code, VALUES(public_code)),
       is_admin = TRUE`,
    [devUserId, createPublicCode()],
  );
}

async function ensureCollaborationTables() {
  await pool.execute(
    `CREATE TABLE IF NOT EXISTS admin_audit_logs (
      id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
      admin_user_id BIGINT UNSIGNED NOT NULL,
      action VARCHAR(64) NOT NULL,
      target_id VARCHAR(64) NULL,
      payload_json JSON NULL,
      ip_address VARCHAR(64) NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_admin_audit_logs_admin (admin_user_id),
      KEY idx_admin_audit_logs_action (action),
      KEY idx_admin_audit_logs_created (created_at),
      FOREIGN KEY (admin_user_id) REFERENCES users(id) ON DELETE CASCADE
    )`,
  );
  await pool.execute(
    `CREATE TABLE IF NOT EXISTS event_meeting_points (
      id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
      event_id BIGINT UNSIGNED NOT NULL,
      circle_id BIGINT UNSIGNED NOT NULL,
      creator_user_id BIGINT UNSIGNED NOT NULL,
      latitude DECIMAL(10, 7) NOT NULL,
      longitude DECIMAL(10, 7) NOT NULL,
      description TEXT NULL,
      meet_at DATETIME NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
      FOREIGN KEY (circle_id) REFERENCES circles(id) ON DELETE CASCADE,
      FOREIGN KEY (creator_user_id) REFERENCES users(id) ON DELETE CASCADE,
      KEY idx_event_meeting_points_event (event_id),
      KEY idx_event_meeting_points_circle (circle_id)
    )`,
  );
  await pool.execute(
    `CREATE TABLE IF NOT EXISTS event_recognition_requests (
      id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
      event_id BIGINT UNSIGNED NOT NULL,
      requester_user_id BIGINT UNSIGNED NOT NULL,
      target_user_id BIGINT UNSIGNED NOT NULL,
      status ENUM('pending','come','busy') NOT NULL DEFAULT 'pending',
      response_message VARCHAR(80) NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      responded_at TIMESTAMP NULL,
      FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
      FOREIGN KEY (requester_user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (target_user_id) REFERENCES users(id) ON DELETE CASCADE,
      KEY idx_event_recognition_event (event_id),
      KEY idx_event_recognition_target (target_user_id),
      KEY idx_event_recognition_requester (requester_user_id)
    )`,
  );
}

async function recordAdminAction(
  req,
  action,
  targetId,
  payload = null,
  connection = pool,
) {
  await connection.execute(
    `INSERT INTO admin_audit_logs
      (admin_user_id, action, target_id, payload_json, ip_address)
     VALUES (?, ?, ?, ?, ?)`,
    [
      req.userId,
      action,
      targetId == null ? null : String(targetId),
      payload == null ? null : JSON.stringify(payload),
      req.ip ?? null,
    ],
  );
}

function normalizeEmail(value) {
  return String(value ?? '').trim().toLowerCase();
}

async function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const derivedKey = await scrypt(password, salt, 64);
  return `${salt}:${derivedKey.toString('hex')}`;
}

async function verifyPassword(password, passwordHash) {
  if (!passwordHash || !passwordHash.includes(':')) return false;
  const [salt, stored] = passwordHash.split(':');
  const derivedKey = await scrypt(password, salt, 64);
  const storedBuffer = Buffer.from(stored, 'hex');
  return (
    storedBuffer.length === derivedKey.length &&
    crypto.timingSafeEqual(storedBuffer, derivedKey)
  );
}

function createSessionToken() {
  return crypto.randomBytes(32).toString('hex');
}

function createPublicCode() {
  return crypto.randomBytes(12).toString('hex');
}

async function fetchSocialProfile(provider, accessToken) {
  if (provider === 'facebook') {
    const url = new URL('https://graph.facebook.com/me');
    url.searchParams.set('fields', 'id,name,email,picture.type(large)');
    url.searchParams.set('access_token', accessToken);
    const response = await fetch(url);
    if (!response.ok) throw new Error('invalid_social_token');
    const data = await response.json();
    return {
      id: data.id?.toString() ?? '',
      email: data.email?.toString() || null,
      nickname: data.name?.toString() || 'Facebook 使用者',
      avatarUrl: data.picture?.data?.url?.toString() || '',
    };
  }
  if (provider === 'line') {
    const response = await fetch('https://api.line.me/v2/profile', {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!response.ok) throw new Error('invalid_social_token');
    const data = await response.json();
    return {
      id: data.userId?.toString() ?? '',
      email: null,
      nickname: data.displayName?.toString() || 'LINE 使用者',
      avatarUrl: data.pictureUrl?.toString() || '',
    };
  }
  return null;
}

function isDateOnly(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function daysBetweenDates(start, end) {
  const startDate = new Date(start);
  const endDate = new Date(end);
  if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) {
    return 0;
  }
  const millisecondsPerDay = 24 * 60 * 60 * 1000;
  return Math.floor((endDate - startDate) / millisecondsPerDay);
}

function normalizeAdminEventPayload(body) {
  const category = String(body.category ?? '綜合').trim() || '綜合';
  const name = String(body.name ?? '').trim();
  const startDate = String(body.startDate ?? '').trim();
  const endDate = String(body.endDate ?? startDate).trim();
  const venue = String(body.venue ?? '').trim();
  const detailedAddress = String(body.detailedAddress ?? '').trim() || venue;
  const fee = String(body.fee ?? '').trim();
  const organizer = String(body.organizer ?? '').trim();
  const description = String(body.description ?? '').trim();
  const imageUrl = String(body.imageUrl ?? '').trim();
  const sourceUrl = String(body.sourceUrl ?? '').trim();
  const sourceType = Number.parseInt(body.sourceType ?? 3, 10);
  const sourceName = String(body.sourceName ?? '管理後台').trim() || '管理後台';
  const status = String(body.status ?? 'approved').trim();

  if (!name) return { ok: false, error: 'event_name_required' };
  if (!venue) return { ok: false, error: 'event_venue_required' };
  if (!isDateOnly(startDate) || !isDateOnly(endDate)) {
    return { ok: false, error: 'invalid_date' };
  }
  if (endDate < startDate) return { ok: false, error: 'end_before_start' };
  if (!['pending', 'approved', 'rejected'].includes(status)) {
    return { ok: false, error: 'invalid_status' };
  }
  if (!Number.isFinite(sourceType) || sourceType <= 0) {
    return { ok: false, error: 'invalid_source_type' };
  }

  return {
    ok: true,
    category,
    name,
    startDate,
    endDate,
    venue,
    detailedAddress,
    fee,
    organizer,
    description,
    imageUrl,
    sourceUrl,
    sourceType,
    sourceName,
    status,
  };
}

function normalizeDateTimeForSql(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error('invalid_datetime');
  }
  return date.toISOString().slice(0, 19).replace('T', ' ');
}

function bearerToken(req) {
  const header = String(req.headers.authorization ?? '');
  if (!header.toLowerCase().startsWith('bearer ')) return '';
  return header.slice(7).trim();
}

async function resolveUserId(req) {
  const token = bearerToken(req);
  if (!token) return null;
  const [rows] = await pool.execute(
    'SELECT id FROM users WHERE session_token = ? LIMIT 1',
    [token],
  );
  return rows[0]?.id ?? null;
}

async function requireAdmin(req, res, next) {
  try {
    const [rows] = await pool.execute(
      'SELECT is_admin AS isAdmin FROM users WHERE id = ? LIMIT 1',
      [req.userId],
    );
    if (!rows[0]?.isAdmin) {
      res.status(403).json({ error: 'admin_required' });
      return;
    }
    next();
  } catch (error) {
    next(error);
  }
}

async function fetchUserProfile(userId) {
  const [rows] = await pool.execute(
    `SELECT id, public_code AS publicCode, is_admin AS isAdmin, nickname,
            avatar_url AS avatarUrl,
            facebook_url AS facebookUrl,
            bio,
            age,
            regions_json AS regionsJson,
            travel_regions_json AS travelRegionsJson,
            travel_same_region AS travelSameRegion,
            landmine,
            gender,
            other_photo_urls_json AS otherPhotoUrlsJson
       FROM users
      WHERE id = ?`,
    [userId],
  );
  if (!rows[0]) return null;
  const pitWorks = await fetchUserPitWorks(userId);
  return {
    ...normalizeProfileJsonFields(rows[0]),
    pitWorks,
    deepPitWorks: pitWorks.filter((work) => work.depth === 'deep'),
    shallowPitWorks: pitWorks.filter((work) => work.depth === 'shallow'),
  };
}

async function fetchUserProfileByPublicCode(publicCode, viewerUserId = null) {
  const [rows] = await pool.execute(
    `SELECT users.id,
            users.public_code AS publicCode,
            users.nickname,
            users.avatar_url AS avatarUrl,
            users.facebook_url AS facebookUrl,
            users.bio,
            users.age,
            users.regions_json AS regionsJson,
            users.travel_regions_json AS travelRegionsJson,
            users.travel_same_region AS travelSameRegion,
            users.landmine,
            users.gender,
            users.other_photo_urls_json AS otherPhotoUrlsJson,
            CASE WHEN follows.followed_user_id IS NULL THEN FALSE ELSE TRUE END AS isFollowed
       FROM users
       LEFT JOIN follows
         ON follows.follower_user_id = ?
        AND follows.followed_user_id = users.id
      WHERE users.public_code = ?
      LIMIT 1`,
    [viewerUserId ?? 0, publicCode],
  );
  if (!rows[0]) return null;
  const { id, ...profile } = rows[0];
  const pitWorks = await fetchUserPitWorks(id);
  profile.landmine = '';
  if (profile.gender === '不公開') {
    profile.gender = '';
  }
  return {
    ...normalizeProfileJsonFields(profile),
    pitWorks,
    deepPitWorks: pitWorks.filter((work) => work.depth === 'deep'),
    shallowPitWorks: pitWorks.filter((work) => work.depth === 'shallow'),
  };
}

async function fetchUserPitWorks(userId) {
  const [rows] = await pool.execute(
    `SELECT works.id, works.name, user_pit_works.depth
       FROM user_pit_works
       INNER JOIN works
         ON works.id = user_pit_works.work_id
      WHERE user_pit_works.user_id = ?
      ORDER BY user_pit_works.depth ASC, works.name ASC`,
    [userId],
  );
  return rows;
}

function normalizeProfileJsonFields(profile) {
  const {
    regionsJson,
    travelRegionsJson,
    otherPhotoUrlsJson,
    travelSameRegion,
    ...rest
  } = profile;
  const regions = parseJsonStringArray(regionsJson);
  const storedTravelRegions = parseJsonStringArray(travelRegionsJson);
  const isSameRegion =
    travelSameRegion === true ||
    travelSameRegion === 1 ||
    travelSameRegion === '1';
  const travelRegions =
    storedTravelRegions.length > 0 || !isSameRegion
      ? storedTravelRegions
      : regions;
  return {
    ...rest,
    travelSameRegion: isSameRegion,
    regions,
    travelRegions,
    otherPhotoUrls: parseJsonStringArray(otherPhotoUrlsJson).slice(0, 3),
  };
}

function parseJsonStringArray(value) {
  if (!value) return [];
  try {
    const parsed = JSON.parse(value);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((item) => typeof item === 'string')
      .map((item) => item.trim())
      .filter(Boolean);
  } catch (_error) {
    return [];
  }
}

function normalizeStringArray(value, allowList = null) {
  if (!Array.isArray(value)) return [];
  const allowed = allowList == null ? null : new Set(allowList);
  return [
    ...new Set(
      value
        .filter((item) => typeof item === 'string')
        .map((item) => item.trim())
        .filter((item) => item && (allowed == null || allowed.has(item))),
    ),
  ];
}

function normalizeIdArray(value) {
  if (!Array.isArray(value)) return [];
  return [
    ...new Set(
      value
        .map((item) => Number.parseInt(item, 10))
        .filter((item) => Number.isFinite(item) && item > 0),
    ),
  ];
}

function sameStringSet(left, right) {
  if (left.length !== right.length) return false;
  const rightSet = new Set(right);
  return left.every((item) => rightSet.has(item));
}

async function createInviteCode(connection) {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const code = `CC-${crypto.randomBytes(8).toString('base64url').toUpperCase()}`;
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

function imageExtension(mimeType) {
  return {
    'image/jpeg': 'jpg',
    'image/jpg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
  }[String(mimeType ?? '').toLowerCase()];
}

function isValidImageBytes(bytes, extension) {
  if (extension === 'jpg') {
    return (
      bytes.length >= 3 &&
      bytes[0] === 0xff &&
      bytes[1] === 0xd8 &&
      bytes[2] === 0xff
    );
  }
  if (extension === 'png') {
    return (
      bytes.length >= 8 &&
      bytes[0] === 0x89 &&
      bytes[1] === 0x50 &&
      bytes[2] === 0x4e &&
      bytes[3] === 0x47 &&
      bytes[4] === 0x0d &&
      bytes[5] === 0x0a &&
      bytes[6] === 0x1a &&
      bytes[7] === 0x0a
    );
  }
  if (extension === 'webp') {
    return (
      bytes.length >= 12 &&
      bytes.toString('ascii', 0, 4) === 'RIFF' &&
      bytes.toString('ascii', 8, 12) === 'WEBP'
    );
  }
  return false;
}

function publicUploadUrl(req, fileName) {
  return `${req.protocol}://${req.get('host')}/uploads/${fileName}`;
}
