import 'dotenv/config';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import cors from 'cors';
import express from 'express';
import {
  importEventsFromHtml,
} from '../scripts/scrape-events.js';
import { createPool } from './db.js';
import { sendRecognitionPush } from './push-service.js';
import { eventListQuery } from './event-queries.js';
import { sharedLocationsQuery, updateLocationCoordinatesQuery } from './location-queries.js';
import { createEventSyncService } from './event-sync-service.js';
import { fetchLineProfile } from './line-auth.js';
import { ensureAuthIdentities, linkLineIdentity, authIdentityUserQuery } from './auth-identities.js';
import { inTransaction } from './db-transaction.js';
import { ensureFriendships, registerFriendRoutes } from './friendships.js';
import {createMailService} from './mail-service.js';
import {createEmailAccountService, emailActionTableSql, registerEmailAccountRoutes} from './email-account-service.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const uploadDir = path.resolve(__dirname, '..', 'uploads');
const app = express();
app.set('trust proxy', 'loopback');
const pool = createPool();
const devUserId = 1;
const scrypt = promisify(crypto.scrypt);
const isProduction = process.env.NODE_ENV === 'production';
const eventScraperEnabled = process.env.EVENT_SCRAPER_ENABLED !== 'false';
const eventScraperTimeZone = process.env.EVENT_SCRAPER_TIME_ZONE ?? 'Asia/Taipei';
const eventSyncService = createEventSyncService(pool, {timeZone: eventScraperTimeZone});
const syncIngestToken = String(process.env.SYNC_INGEST_TOKEN ?? '').trim();
const emailAccountService = createEmailAccountService(pool, {
  mail: createMailService(), publicAppUrl: process.env.PUBLIC_APP_URL, hashPassword,
});
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

function isValidSyncIngestToken(req) {
  if (syncIngestToken.length < 32) return false;
  const header = String(req.get('authorization') ?? '');
  const token = header.startsWith('Bearer ')
    ? header.slice('Bearer '.length).trim()
    : String(req.get('x-coscircle-sync-token') ?? '').trim();
  if (token.length !== syncIngestToken.length) return false;

  return crypto.timingSafeEqual(
    Buffer.from(token),
    Buffer.from(syncIngestToken),
  );
}

app.get('/api/health', (_req, res) => res.json({ ok: true, name: 'CosCircle API' }));

app.post('/api/source-ingest/doujin-html', async (req, res, next) => {
  try {
    if (!isValidSyncIngestToken(req)) {
      res.status(401).json({ error: 'invalid_sync_ingest_token' });
      return;
    }

    const html = String(req.body.html ?? '');
    const sourceUrl = String(
      req.body.sourceUrl ?? 'https://www.doujin.com.tw/events/alist/all',
    ).trim();
    if (!html.includes('同人活動') || !html.includes('活動時間')) {
      res.status(400).json({ error: 'invalid_doujin_html' });
      return;
    }

    const events = await importEventsFromHtml(html, pool);
    await recordSourceSyncRun({
      sourceKey: 'doujin-events-edge',
      sourceUrl,
      status: 'success',
      importedCount: events.length,
    });
    res.json({
      imported: true,
      count: events.length,
      source: 'edge-html',
    });
  } catch (error) {
    try {
      await recordSourceSyncRun({
        sourceKey: 'doujin-events-edge',
        sourceUrl:
          req.body?.sourceUrl?.toString() ??
          'https://www.doujin.com.tw/events/alist/all',
        status: 'failure',
        errorCode:
          error?.response?.status?.toString() ??
          error?.code?.toString() ??
          'edge_ingest_failed',
        errorMessage: summarizeError(error),
      });
    } catch (recordError) {
      console.error('[event-scraper] failed to record edge sync status', recordError);
    }
    next(error);
  }
});

app.use('/api/auth', createRateLimiter({ windowMs: 15 * 60 * 1000, max: 30 }));
registerEmailAccountRoutes(app, emailAccountService, {production: isProduction});
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
    const result = await inTransaction(pool, async (db) => {
      const [result] = await db.execute(
        `INSERT INTO users (
           provider, provider_user_id, public_code, email, password_hash, session_token, nickname,
           avatar_url, facebook_url, bio
         )
         VALUES ('email', ?, ?, ?, ?, ?, ?, '', '', '')`,
        [email, createPublicCode(), email, passwordHash, sessionToken, nickname],
      );
      await db.execute(`INSERT INTO user_auth_identities (user_id,provider,provider_user_id,password_hash)
        VALUES (?,'email',?,?)`, [result.insertId, email, passwordHash]);
      return result;
    });
    const profile = await fetchUserProfile(result.insertId);
    console.info('[auth/register] success', { email, userId: result.insertId });
    setImmediate(() => emailAccountService.requestVerification(result.insertId)
      .catch(() => console.warn('[account-mail] registration verification unavailable')));
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
      authIdentityUserQuery,
      ['email', email],
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

    if (user.accountStatus !== 'active') {
      return res.status(403).json({error: 'account_suspended'});
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
      const [[user]] = await pool.execute('SELECT id FROM users WHERE session_token = ?', [token]);
      if (user && req.body.pushToken) {
        await pool.execute('DELETE FROM device_push_tokens WHERE user_id = ? AND token = ?', [user.id, req.body.pushToken]);
      }
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
    if (provider === 'line' && isProduction && !req.secure) {
      return res.status(426).json({error: 'secure_transport_required'});
    }
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
    let userId;
    let isNewUser = false;
    await inTransaction(pool, async (db) => {
      const [existingRows] = await db.execute(
        `${authIdentityUserQuery} FOR UPDATE`,
        [provider, socialProfile.id],
      );
      userId = existingRows[0]?.id;
      if (existingRows[0]?.accountStatus === 'suspended') {
        throw Object.assign(new Error('account_suspended'), {code: 'account_suspended'});
      }
      if (userId) {
        await db.execute(
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
        const [result] = await db.execute(
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
        await db.execute(`INSERT INTO user_auth_identities (user_id,provider,provider_user_id,verified_at)
          VALUES (?,?,?,UTC_TIMESTAMP())`, [userId, provider, socialProfile.id]);
      }
    });
    res.json({
      token: sessionToken,
      user: await fetchUserProfile(userId),
      isNewUser,
    });
  } catch (error) {
    if (error.code === 'account_suspended') return res.status(403).json({error: error.code});
    if (error.code === 'ER_DUP_ENTRY') return res.status(409).json({error: 'social_identity_conflict'});
    if (['line_login_not_configured', 'line_login_unavailable'].includes(error.code)) {
      return res.status(503).json({error: error.code});
    }
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

app.use('/api/me/email-verification', createRateLimiter({windowMs: 15 * 60 * 1000, max: 10}));
registerEmailAccountRoutes(app, emailAccountService, {privateRoutes: true, production: isProduction});

app.use('/api/friend-invites', createRateLimiter({ windowMs: 60 * 60 * 1000, max: 30 }));
app.use('/api/friend-requests', createRateLimiter({ windowMs: 15 * 60 * 1000, max: 60 }));
registerFriendRoutes(app, pool);

app.get('/api/me/auth-identities', async (req, res, next) => {
  try {
    const [rows] = await pool.execute(`SELECT provider FROM user_auth_identities WHERE user_id=? ORDER BY provider`, [req.userId]);
    res.json(rows);
  } catch (error) { next(error); }
});

app.use('/api/me/auth-identities', createRateLimiter({windowMs: 15 * 60 * 1000, max: 30}));
app.post('/api/me/auth-identities/line', async (req, res, next) => {
  try {
    if (isProduction && !req.secure) return res.status(426).json({error: 'secure_transport_required'});
    const password = typeof req.body.password === 'string' ? req.body.password : '';
    if (!password || password.length > 1024) return res.status(401).json({error: 'reauthentication_required'});
    const profile = await fetchLineProfile(req.body.accessToken);
    res.json(await linkLineIdentity(pool, {userId: req.userId, lineUserId: profile.id, password, verifyPassword}));
  } catch (error) {
    if (['invalid_social_token', 'line_login_not_configured', 'line_login_unavailable',
      'account_suspended', 'reauthentication_required', 'line_identity_already_linked'].includes(error.code)) {
      return res.status(error.status ?? 401).json({error: error.code});
    }
    next(error);
  }
});

app.post('/api/me/push-tokens', async (req, res, next) => {
  try {
    const token = String(req.body.token ?? '').trim();
    const platform = normalizePushPlatform(req.body.platform);
    if (!platform || token.length < 24 || token.length > 512) {
      res.status(400).json({ error: 'invalid_push_token' });
      return;
    }
    await pool.execute(
      `INSERT INTO device_push_tokens (user_id, platform, token)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE user_id = VALUES(user_id),
         platform = VALUES(platform),
         updated_at = CURRENT_TIMESTAMP`,
      [req.userId, platform, token],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.delete('/api/me/push-tokens', async (req, res, next) => {
  try {
    const token = String(req.body.token ?? '').trim();
    if (!token) {
      res.status(400).json({ error: 'invalid_push_token' });
      return;
    }
    await pool.execute(
      `DELETE FROM device_push_tokens
        WHERE user_id = ?
          AND token = ?`,
      [req.userId, token],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.put('/api/me', async (req, res, next) => {
  let connection;
  try {
    connection = await pool.getConnection();
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
      profileRoles = [],
      otherPhotoUrls = [],
      bookingVisibility = 'public',
      onboardingCompleted,
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
    const normalizedProfileRoles = normalizeStringArray(profileRoles, [
      'coser',
      'photographer',
      'manager',
      'self',
    ]);
    const normalizedPhotoUrls = normalizeStringArray(otherPhotoUrls).slice(0, 3);
    const normalizedBookingVisibility = normalizeBookingVisibility(bookingVisibility);
    if (!String(nickname ?? '').trim()) {
      res.status(400).json({ error: 'nickname_required' });
      return;
    }
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
              profile_roles_json = ?,
              other_photo_urls_json = ?,
              booking_visibility = ?,
              onboarding_completed = CASE WHEN ? = 1 THEN TRUE ELSE onboarding_completed END
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
        JSON.stringify(normalizedProfileRoles),
        JSON.stringify(normalizedPhotoUrls),
        normalizedBookingVisibility,
        onboardingCompleted === true ? 1 : 0,
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
    await connection?.rollback().catch(() => {});
    next(error);
  } finally {
    connection?.release();
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
      eventListQuery,
      Array(16).fill(req.userId),
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
    const [[suspendedUsers]] = await pool.query(
      "SELECT COUNT(*) AS count FROM users WHERE account_status = 'suspended'",
    );
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
      suspendedUsers: suspendedUsers.count,
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
              account_status AS accountStatus,
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
app.get('/api/admin/event-sync-jobs/current', async (_req, res, next) => {
  try { res.json(await eventSyncService.readLatest()); }
  catch (error) { next(error); }
});
app.get('/api/admin/event-sync-jobs/:id', async (req, res, next) => {
  try {
    const job = await eventSyncService.readJob(req.params.id);
    if (!job) return res.status(404).json({error: 'event_sync_job_not_found'});
    res.json(job);
  } catch (error) { next(error); }
});

app.get('/api/admin/doujin-sync-check', async (_req, res, next) => {
  try {
    const [dbEvents, syncRuns] = await Promise.all([
      fetchDoujinDbEvents(),
      fetchRecentSyncRuns(),
    ]);
    const approvedDbEvents = dbEvents.filter((event) => event.status === 'approved');
    const base = {
      sourceUrl: 'https://www.doujin.com.tw/events/alist/all',
      databaseCount: approvedDbEvents.length,
      databaseCurrentOrFutureCount: approvedDbEvents.filter(
        (event) => !event.isEnded,
      ).length,
      databaseEndedCount: approvedDbEvents.filter((event) => event.isEnded)
        .length,
      recentRuns: syncRuns,
    };

    try {
      const [snapshots] = await pool.execute("SELECT events_json, DATE_FORMAT(fetched_at, '%Y-%m-%dT%H:%i:%sZ') AS fetchedAt FROM event_source_snapshots WHERE source_key='doujin-source'");
      if (!snapshots.length) throw Object.assign(new Error('尚無成功同步快照，請先執行同步'), {code: 'source_snapshot_unavailable'});
      const sourceEvents = typeof snapshots[0].events_json === 'string' ? JSON.parse(snapshots[0].events_json) : snapshots[0].events_json;
      const sourceKeys = new Set(sourceEvents.map((event) => event.sourceKey));
      const dbKeys = new Set(approvedDbEvents.map((event) => event.sourceKey));
      const missingInDatabase = sourceEvents
        .filter((event) => !dbKeys.has(event.sourceKey))
        .map(formatDoujinCheckEvent);
      const extraInDatabase = approvedDbEvents
        .filter((event) => !sourceKeys.has(event.sourceKey))
        .map(formatDoujinCheckEvent);

      res.json({
        ...base,
        sourceAvailable: true,
        fromCache: true,
        checkedAt: snapshots[0].fetchedAt,
        sourceCount: sourceEvents.length,
        matchedCount: sourceEvents.length - missingInDatabase.length,
        isCountMatched: sourceEvents.length === approvedDbEvents.length,
        isFullyMatched:
          missingInDatabase.length === 0 && extraInDatabase.length === 0,
        missingInDatabase,
        extraInDatabase,
      });
    } catch (error) {
      res.json({
        ...base,
        sourceAvailable: false,
        sourceCount: null,
        matchedCount: null,
        isCountMatched: false,
        isFullyMatched: false,
        missingInDatabase: [],
        extraInDatabase: [],
        sourceError: {
          code:
            error?.response?.status?.toString() ??
            error?.code?.toString() ??
            'source_fetch_failed',
          message: summarizeError(error),
        },
      });
    }
  } catch (error) {
    next(error);
  }
});

app.get('/api/admin/sync-status', async (_req, res, next) => {
  try {
    const [rows] = await pool.query(
      `SELECT source_key AS sourceKey,
              source_url AS sourceUrl,
              status,
              imported_count AS importedCount,
              error_code AS errorCode,
              error_message AS errorMessage,
              DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%s') AS createdAt
         FROM source_sync_runs
        ORDER BY created_at DESC
        LIMIT 20`,
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

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
    res.status(202).json(await eventSyncService.startManual());
  } catch (error) {
    next(error);
  }
}

async function fetchDoujinDbEvents() {
  const [rows] = await pool.query(
    `SELECT source_key AS sourceKey,
            category,
            name,
            source_url AS sourceUrl,
            DATE_FORMAT(start_date, '%Y-%m-%d') AS startDate,
            DATE_FORMAT(end_date, '%Y-%m-%d') AS endDate,
            venue,
            status,
            end_date < CURDATE() AS isEnded
       FROM events
      WHERE source_name = '同人誌中心'
         OR source_type = 1
         OR source_key LIKE 'doujin-%'
      ORDER BY start_date ASC, id ASC`,
  );
  return rows;
}

async function fetchRecentSyncRuns() {
  const [rows] = await pool.query(
    `SELECT source_key AS sourceKey,
            source_url AS sourceUrl,
            status,
            imported_count AS importedCount,
            error_code AS errorCode,
            error_message AS errorMessage,
            DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%s') AS createdAt
       FROM source_sync_runs
      ORDER BY created_at DESC
      LIMIT 5`,
  );
  return rows;
}

function formatDoujinCheckEvent(event) {
  return {
    sourceKey: event.sourceKey,
    category: event.category,
    name: event.name,
    sourceUrl: event.sourceUrl,
    startDate: event.startDate,
    endDate: event.endDate,
    venue: event.venue,
    status: event.status,
    isEnded: event.isEnded === true || event.isEnded === 1,
  };
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

app.put('/api/admin/users/:userId/status', async (req, res, next) => {
  try {
    const userId = Number(req.params.userId);
    if (!Number.isInteger(userId)) {
      res.status(400).json({ error: 'invalid_user_id' });
      return;
    }
    const status = String(req.body.status ?? '').trim();
    if (!['active', 'suspended'].includes(status)) {
      res.status(400).json({ error: 'invalid_account_status' });
      return;
    }
    if (userId === Number(req.userId) && status === 'suspended') {
      res.status(400).json({ error: 'cannot_suspend_self' });
      return;
    }
    const [result] = await pool.execute(
      `UPDATE users
          SET account_status = ?,
              session_token = CASE WHEN ? = 'suspended' THEN NULL ELSE session_token END
        WHERE id = ?`,
      [status, status, userId],
    );
    if (result.affectedRows === 0) {
      res.status(404).json({ error: 'user_not_found' });
      return;
    }
    await recordAdminAction(req, `user.${status}`, userId);
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.put('/api/admin/users/:userId/admin', async (req, res, next) => {
  try {
    const userId = Number(req.params.userId);
    if (!Number.isInteger(userId)) {
      res.status(400).json({ error: 'invalid_user_id' });
      return;
    }
    const isAdmin = req.body.isAdmin === true || req.body.isAdmin === 1;
    if (userId === Number(req.userId) && !isAdmin) {
      res.status(400).json({ error: 'cannot_revoke_self_admin' });
      return;
    }
    const [result] = await pool.execute(
      `UPDATE users
          SET is_admin = ?
        WHERE id = ?`,
      [isAdmin, userId],
    );
    if (result.affectedRows === 0) {
      res.status(404).json({ error: 'user_not_found' });
      return;
    }
    await recordAdminAction(
      req,
      isAdmin ? 'user.grant_admin' : 'user.revoke_admin',
      userId,
    );
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
  let connection;
  try {
    connection = await pool.getConnection();
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
    await connection?.rollback().catch(() => {});
    next(error);
  } finally {
    connection?.release();
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
          LEFT JOIN user_blocks AS viewer_blocks
            ON viewer_blocks.blocker_user_id = ?
           AND viewer_blocks.blocked_user_id = users.id
          LEFT JOIN user_blocks AS member_blocks
            ON member_blocks.blocker_user_id = users.id
           AND member_blocks.blocked_user_id = ?
          WHERE circle_members.circle_id IN (${placeholders})
            AND (
              users.id = ?
              OR (
                viewer_blocks.blocked_user_id IS NULL
                AND member_blocks.blocker_user_id IS NULL
              )
            )
          ORDER BY isOwner DESC, circle_members.created_at ASC`,
        [req.userId, req.userId, ...circleIds, req.userId],
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
        inviteUrl: `${publicAppBaseUrl(req)}/#/join/${row.inviteCode}`,
        members: membersByCircle.get(String(row.id)) ?? [],
      })),
    );
  } catch (error) {
    next(error);
  }
});

app.post('/api/circles', async (req, res, next) => {
  let connection;
  try {
    connection = await pool.getConnection();
    const { name, description } = req.body;
    const normalizedName = String(name ?? '').trim();
    if (!normalizedName) return res.status(400).json({ error: 'circle_name_required' });
    const inviteCode = await createInviteCode(connection);
    const inviteUrl = `${publicAppBaseUrl(req)}/#/join/${inviteCode}`;

    await connection.beginTransaction();
    const [result] = await connection.execute(
      `INSERT INTO circles (owner_user_id, name, description, invite_code, invite_url)
       VALUES (?, ?, ?, ?, ?)`,
      [req.userId, normalizedName, String(description ?? '').trim() || null, inviteCode, inviteUrl],
    );
    await connection.execute(
      `INSERT INTO circle_members (circle_id, user_id)
       VALUES (?, ?)`,
      [result.insertId, req.userId],
    );
    await connection.commit();
    res.status(201).json({ id: result.insertId, inviteCode, inviteUrl });
  } catch (error) {
    await connection?.rollback().catch(() => {});
    next(error);
  } finally {
    connection?.release();
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
      res.status(409).json({ error: 'circle_owner_cannot_leave' });
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

app.delete('/api/circles/:circleId', async (req, res, next) => {
  try {
    const [result] = await pool.execute('DELETE FROM circles WHERE id = ? AND owner_user_id = ?', [req.params.circleId, req.userId]);
    if (!result.affectedRows) return res.status(404).json({ error: 'circle_not_found' });
    res.status(204).end();
  } catch (error) { next(error); }
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
         LEFT JOIN user_blocks AS my_blocks
           ON my_blocks.blocker_user_id = ?
          AND my_blocks.blocked_user_id = users.id
         LEFT JOIN user_blocks AS their_blocks
           ON their_blocks.blocker_user_id = users.id
          AND their_blocks.blocked_user_id = ?
        WHERE follows.follower_user_id = ?
          AND my_blocks.blocked_user_id IS NULL
          AND their_blocks.blocker_user_id IS NULL
        ORDER BY follows.created_at DESC`,
      [req.userId, req.userId, req.userId],
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.get('/api/me/bookings', async (req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT b.event_id AS eventId, b.user_id AS userId, u.nickname, u.public_code AS publicCode,
              b.day_index AS dayIndex, b.role, b.work_id AS workId, w.name AS workName,
              b.character_name AS characterName, b.outfit_image_url AS outfitImageUrl,
              b.interaction_tags AS interactionTags, b.available_time AS availableTime,
              b.presence_status AS presenceStatus, b.message, TRUE AS isMe
         FROM event_bookings b INNER JOIN users u ON u.id = b.user_id
         INNER JOIN events e ON e.id = b.event_id
         LEFT JOIN works w ON w.id = b.work_id
        WHERE b.user_id = ? AND e.status = 'approved' ORDER BY e.start_date, b.day_index`, [req.userId]);
    res.json(rows);
  } catch (error) { next(error); }
});

app.get('/api/me/booking-followers', async (req, res, next) => {
  try {
    const [bookings] = await pool.execute(
      `SELECT event_bookings.id AS bookingId,
              events.id AS eventId,
              events.name AS eventName,
              DATE_FORMAT(events.start_date, '%Y-%m-%d') AS startDate,
              DATE_FORMAT(events.end_date, '%Y-%m-%d') AS endDate,
              event_bookings.day_index AS dayIndex,
              event_bookings.role
         FROM event_bookings
         INNER JOIN events
           ON events.id = event_bookings.event_id
          AND events.status = 'approved'
        WHERE event_bookings.user_id = ?
        ORDER BY events.start_date ASC,
                 event_bookings.day_index ASC`,
      [req.userId],
    );

    if (bookings.length === 0) {
      res.json([]);
      return;
    }

    const bookingIds = bookings.map((booking) => booking.bookingId);
    const placeholders = bookingIds.map(() => '?').join(',');
    const [followers] = await pool.execute(
      `SELECT event_bookings.id AS bookingId,
              users.id AS userId,
              users.public_code AS publicCode,
              users.nickname,
              users.avatar_url AS avatarUrl,
              DATE_FORMAT(follows.created_at, '%Y-%m-%dT%H:%i:%s') AS followedAt
         FROM event_bookings
         INNER JOIN users AS owner
           ON owner.id = event_bookings.user_id
         INNER JOIN follows
           ON follows.followed_user_id = event_bookings.user_id
         INNER JOIN users
           ON users.id = follows.follower_user_id
         LEFT JOIN user_blocks AS owner_blocks
           ON owner_blocks.blocker_user_id = owner.id
          AND owner_blocks.blocked_user_id = users.id
         LEFT JOIN user_blocks AS follower_blocks
           ON follower_blocks.blocker_user_id = users.id
          AND follower_blocks.blocked_user_id = owner.id
        WHERE event_bookings.id IN (${placeholders})
          AND owner_blocks.blocked_user_id IS NULL
          AND follower_blocks.blocker_user_id IS NULL
          AND (
            owner.booking_visibility = 'public'
            OR EXISTS (
              SELECT 1
                FROM circle_members AS owner_circles
                INNER JOIN circle_members AS follower_circles
                  ON follower_circles.circle_id = owner_circles.circle_id
                 AND follower_circles.user_id = users.id
               WHERE owner_circles.user_id = owner.id
               LIMIT 1
            )
          )
        ORDER BY follows.created_at DESC`,
      bookingIds,
    );

    const followersByBooking = new Map();
    for (const follower of followers) {
      const key = String(follower.bookingId);
      if (!followersByBooking.has(key)) followersByBooking.set(key, []);
      followersByBooking.get(key).push({
        userId: follower.userId,
        publicCode: follower.publicCode,
        nickname: follower.nickname,
        avatarUrl: follower.avatarUrl,
        followedAt: follower.followedAt,
      });
    }

    res.json(
      bookings.map((booking) => ({
        ...booking,
        followers: followersByBooking.get(String(booking.bookingId)) ?? [],
      })),
    );
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
    const normalizedDayIndex = Number(dayIndex);
    if (!Number.isInteger(normalizedDayIndex) || normalizedDayIndex < 1) {
      res.status(400).json({ error: 'invalid_day_index' });
      return;
    }
    const [[event]] = await pool.execute(
      `SELECT start_date AS startDate, end_date AS endDate, status,
              DATE_ADD(start_date, INTERVAL ? DAY) < DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+08:00')) AS isEnded
         FROM events
        WHERE id = ?
        LIMIT 1`,
      [normalizedDayIndex - 1, req.params.eventId],
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
    if (event.isEnded) {
      res.status(409).json({ error: 'event_ended' });
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
    const dayIndex = Number(req.query.dayIndex);
    if (req.query.dayIndex != null && (!Number.isInteger(dayIndex) || dayIndex < 1)) {
      return res.status(400).json({ error: 'invalid_day_index' });
    }
    const [[past]] = await pool.execute(
      `SELECT 1 FROM event_bookings b INNER JOIN events e ON e.id = b.event_id
        WHERE b.event_id = ? AND b.user_id = ?
          AND (? IS NULL OR b.day_index = ?)
          AND DATE_ADD(e.start_date, INTERVAL (b.day_index - 1) DAY) < DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+08:00')) LIMIT 1`,
      [req.params.eventId, req.userId, req.query.dayIndex == null ? null : dayIndex, req.query.dayIndex == null ? null : dayIndex],
    );
    if (past) return res.status(409).json({ error: 'event_ended' });
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
         LEFT JOIN user_blocks AS my_blocks
           ON my_blocks.blocker_user_id = ?
          AND my_blocks.blocked_user_id = users.id
         LEFT JOIN user_blocks AS their_blocks
           ON their_blocks.blocker_user_id = users.id
          AND their_blocks.blocked_user_id = ?
         LEFT JOIN works
           ON works.id = event_bookings.work_id
        WHERE event_bookings.event_id = ?
          AND (
            users.id = ?
            OR (
              my_blocks.blocked_user_id IS NULL
              AND their_blocks.blocker_user_id IS NULL
              AND (
                users.booking_visibility = 'public'
                OR (users.booking_visibility = 'circle' AND EXISTS (
                  SELECT 1
                    FROM circle_members AS my_visibility_circles
                    INNER JOIN circle_members AS booking_visibility_circles
                      ON booking_visibility_circles.circle_id = my_visibility_circles.circle_id
                     AND booking_visibility_circles.user_id = users.id
                   WHERE my_visibility_circles.user_id = ?
                   LIMIT 1
                ))
              )
            )
          )
        ORDER BY event_bookings.day_index ASC, event_bookings.updated_at DESC`,
      [
        req.userId,
        req.userId,
        req.userId,
        req.userId,
        req.params.eventId,
        req.userId,
        req.userId,
      ],
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
    if (await hasBlockingRelation(req.userId, req.params.userId)) {
      res.status(403).json({ error: 'user_unavailable' });
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

app.delete('/api/me/followers/:userId', async (req, res, next) => {
  try {
    await pool.execute(
      `DELETE FROM follows
        WHERE follower_user_id = ?
          AND followed_user_id = ?`,
      [req.params.userId, req.userId],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.post('/api/users/:userId/block', async (req, res, next) => {
  let connection;
  try {
    connection = await pool.getConnection();
    if (Number(req.params.userId) === req.userId) {
      res.status(400).json({ error: 'cannot_block_self' });
      return;
    }
    await connection.beginTransaction();
    await connection.execute('SELECT id FROM users WHERE id IN (?, ?) ORDER BY id FOR UPDATE', [req.userId, req.params.userId]);
    await connection.execute(
      `INSERT IGNORE INTO user_blocks (blocker_user_id, blocked_user_id)
       VALUES (?, ?)`,
      [req.userId, req.params.userId],
    );
    await connection.execute(
      `DELETE FROM follows
        WHERE (follower_user_id = ? AND followed_user_id = ?)
           OR (follower_user_id = ? AND followed_user_id = ?)`,
      [req.userId, req.params.userId, req.params.userId, req.userId],
    );
    await connection.execute('DELETE FROM friendships WHERE user_low_id=LEAST(?, ?) AND user_high_id=GREATEST(?, ?)',
      [req.userId, req.params.userId, req.userId, req.params.userId]);
    await connection.commit();
    res.status(204).end();
  } catch (error) {
    await connection?.rollback().catch(() => {});
    next(error);
  } finally {
    connection?.release();
  }
});

app.delete('/api/users/:userId/block', async (req, res, next) => {
  try {
    await pool.execute(
      `DELETE FROM user_blocks
        WHERE blocker_user_id = ?
          AND blocked_user_id = ?`,
      [req.userId, req.params.userId],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.get('/api/blocked-users', async (req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT users.id AS userId,
              users.public_code AS publicCode,
              users.nickname,
              users.avatar_url AS avatarUrl,
              DATE_FORMAT(user_blocks.created_at, '%Y-%m-%dT%H:%i:%s') AS blockedAt
         FROM user_blocks
         INNER JOIN users
           ON users.id = user_blocks.blocked_user_id
        WHERE user_blocks.blocker_user_id = ?
        ORDER BY user_blocks.created_at DESC`,
      [req.userId],
    );
    res.json(rows);
  } catch (error) {
    next(error);
  }
});

app.get('/api/events/:eventId/locations', async (req, res, next) => {
  try {
    const [rows] = await pool.execute(
      sharedLocationsQuery,
      [
        req.userId,
        req.userId,
        req.userId,
        req.userId,
        req.userId,
        req.userId,
        req.userId,
        req.userId,
        req.params.eventId,
        req.userId,
      ],
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
    const visibility = normalizeLocationVisibility(req.body.visibility);
    const expiresInMinutes = normalizeLocationExpiry(req.body.expiresInMinutes);
    const dayIndex = await resolveEventDayIndex(
      req.params.eventId,
      req.userId,
      req.body.dayIndex,
    );
    if (dayIndex == null) {
      res.status(403).json({ error: 'event_booking_required' });
      return;
    }
    if (!Number.isFinite(lat) || lat < -90 || lat > 90) {
      res.status(400).json({ error: 'invalid_latitude' });
      return;
    }
    if (!Number.isFinite(lng) || lng < -180 || lng > 180) {
      res.status(400).json({ error: 'invalid_longitude' });
      return;
    }
    await pool.execute(
      `INSERT INTO shared_locations (
         event_id, day_index, user_id, latitude, longitude, visibility, shared_at, expires_at
       )
       VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? MINUTE))
       ON DUPLICATE KEY UPDATE latitude = VALUES(latitude),
         day_index = VALUES(day_index),
         longitude = VALUES(longitude),
         visibility = VALUES(visibility),
         shared_at = CURRENT_TIMESTAMP,
         expires_at = VALUES(expires_at)`,
      [
        req.params.eventId,
        dayIndex,
        req.userId,
        lat,
        lng,
        visibility,
        expiresInMinutes,
      ],
    );
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.put('/api/events/:eventId/location/coordinates', async (req, res, next) => {
  try {
    const lat = req.body.latitude;
    const lng = req.body.longitude;
    if (typeof lat !== 'number' || typeof lng !== 'number' ||
        !Number.isFinite(lat) || lat < -90 || lat > 90 ||
        !Number.isFinite(lng) || lng < -180 || lng > 180) {
      return res.status(400).json({error: 'invalid_latitude'});
    }
    const dayIndex = await resolveEventDayIndex(req.params.eventId, req.userId, req.body.dayIndex);
    if (dayIndex == null) return res.status(403).json({error: 'event_booking_required'});
    const [result] = await pool.execute(updateLocationCoordinatesQuery,
      [lat, lng, req.params.eventId, req.userId, dayIndex]);
    if (result.affectedRows === 0) return res.status(409).json({error: 'location_share_expired'});
    res.status(204).end();
  } catch (error) { next(error); }
});

app.delete('/api/events/:eventId/location', async (req, res, next) => {
  try {
    await pool.execute(
      `DELETE FROM shared_locations
        WHERE event_id = ?
          AND user_id = ?`,
      [req.params.eventId, req.userId],
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
              event_recognition_requests.day_index AS dayIndex,
              event_recognition_requests.requester_user_id AS requesterUserId,
              requester.nickname AS requesterNickname,
              event_recognition_requests.target_user_id AS targetUserId,
              target.nickname AS targetNickname,
              CASE
                WHEN event_recognition_requests.status = 'pending'
                 AND event_recognition_requests.expires_at <= CURRENT_TIMESTAMP
                THEN 'expired'
                ELSE event_recognition_requests.status
              END AS status,
              event_recognition_requests.response_message AS responseMessage,
              DATE_FORMAT(event_recognition_requests.created_at, '%Y-%m-%dT%H:%i:%s') AS createdAt,
              DATE_FORMAT(event_recognition_requests.expires_at, '%Y-%m-%dT%H:%i:%s') AS expiresAt,
              DATE_FORMAT(event_recognition_requests.responded_at, '%Y-%m-%dT%H:%i:%s') AS respondedAt,
              CASE WHEN event_recognition_requests.requester_user_id = ? THEN TRUE ELSE FALSE END AS isRequester,
              CASE WHEN event_recognition_requests.target_user_id = ? THEN TRUE ELSE FALSE END AS isTarget
         FROM event_recognition_requests
         INNER JOIN users AS requester
           ON requester.id = event_recognition_requests.requester_user_id
         INNER JOIN users AS target
           ON target.id = event_recognition_requests.target_user_id
         LEFT JOIN user_blocks AS requester_blocks
           ON requester_blocks.blocker_user_id = event_recognition_requests.requester_user_id
          AND requester_blocks.blocked_user_id = event_recognition_requests.target_user_id
         LEFT JOIN user_blocks AS target_blocks
           ON target_blocks.blocker_user_id = event_recognition_requests.target_user_id
          AND target_blocks.blocked_user_id = event_recognition_requests.requester_user_id
        WHERE event_recognition_requests.event_id = ?
          AND (
            event_recognition_requests.requester_user_id = ?
            OR event_recognition_requests.target_user_id = ?
          )
          AND requester_blocks.blocked_user_id IS NULL
          AND target_blocks.blocker_user_id IS NULL
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
    if (await hasBlockingRelation(req.userId, targetUserId)) {
      res.status(403).json({ error: 'user_unavailable' });
      return;
    }
    const dayIndex = await resolveEventDayIndex(
      req.params.eventId,
      req.userId,
      req.body.dayIndex,
    );
    if (dayIndex == null) {
      res.status(403).json({ error: 'event_booking_required' });
      return;
    }
    if (!(await userHasEventDayBooking(req.params.eventId, targetUserId, dayIndex))) {
      res.status(403).json({ error: 'target_not_available_for_event_day' });
      return;
    }
    const cooldown = await recognitionCooldownState({
      eventId: req.params.eventId,
      dayIndex,
      requesterUserId: req.userId,
      targetUserId,
    });
    if (!cooldown.ok) {
      res.status(429).json({ error: cooldown.error });
      return;
    }
    const [result] = await pool.execute(
      `INSERT INTO event_recognition_requests (
         event_id, day_index, requester_user_id, target_user_id, status, expires_at
       )
       VALUES (?, ?, ?, ?, 'pending', DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 5 MINUTE))`,
      [req.params.eventId, dayIndex, req.userId, targetUserId],
    );
    const pushResult = await notifyRecognitionRequest({
      requestId: result.insertId,
      eventId: req.params.eventId,
      dayIndex,
      requesterUserId: req.userId,
      targetUserId,
    });
    res.status(201).json({ id: result.insertId, push: pushResult });
  } catch (error) {
    next(error);
  }
});

app.post('/api/recognitions/:requestId/respond', async (req, res, next) => {
  try {
    const status = String(req.body.status ?? '');
    if (!['accepted', 'declined'].includes(status)) {
      res.status(400).json({ error: 'invalid_recognition_status' });
      return;
    }
    const responseMessage = status === 'accepted' ? '快來' : '當前不方便';
    const [result] = await pool.execute(
      `UPDATE event_recognition_requests
          SET status = ?,
              response_message = ?,
              responded_at = CURRENT_TIMESTAMP
        WHERE id = ?
          AND target_user_id = ?
          AND status = 'pending'
          AND expires_at > CURRENT_TIMESTAMP`,
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
  if (error.code === 'event_sync_busy') return res.status(409).json({error: 'event_sync_busy'});
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
await ensureAuthIdentities(pool);
await pool.execute(emailActionTableSql);
await ensureFriendships(pool);
await eventSyncService.initialize();
if (eventScraperEnabled) scheduleDailyEventImport();

app.listen(port, () => {
  console.log(`CosCircle API listening on ${port}`);
});

function scheduleDailyEventImport() {
  let checking = false;
  const check = async () => {
    if (checking) return;
    checking = true;
    try {
      await eventSyncService.runDueDaily();
    } catch (error) {
      console.error('[event-sync] scheduler check failed', error.code ?? 'scheduler_failed');
    } finally { checking = false; }
  };
  void check();
  setInterval(check, 30 * 1000);
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
  const addedOnboarding = await ensureColumn({
    tableName: 'users', columnName: 'onboarding_completed', definition: 'BOOLEAN NOT NULL DEFAULT FALSE',
  });
  await ensureColumn({
    tableName: 'users',
    columnName: 'booking_visibility',
    definition: "ENUM('public','circle') NOT NULL DEFAULT 'public'",
  });
  await ensureColumn({
    tableName: 'users',
    columnName: 'profile_roles_json',
    definition: 'TEXT NULL',
  });
  if (addedOnboarding) {
    await pool.execute("UPDATE users SET onboarding_completed = TRUE WHERE profile_roles_json IS NOT NULL AND profile_roles_json <> '[]' AND nickname <> ''");
  }
  await ensureColumn({
    tableName: 'users',
    columnName: 'account_status',
    definition: "ENUM('active','suspended') NOT NULL DEFAULT 'active'",
  });
  await ensureColumn({
    tableName: 'shared_locations',
    columnName: 'visibility',
    definition: "ENUM('public','followed','circle') NOT NULL DEFAULT 'circle'",
  });
  await ensureColumn({
    tableName: 'shared_locations',
    columnName: 'day_index',
    definition: 'INT UNSIGNED NOT NULL DEFAULT 1',
  });
  await ensureColumn({
    tableName: 'shared_locations',
    columnName: 'expires_at',
    definition: 'TIMESTAMP NULL',
  });
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
    `CREATE TABLE IF NOT EXISTS source_sync_runs (
      id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
      source_key VARCHAR(80) NOT NULL,
      source_url TEXT NOT NULL,
      status ENUM('success','failure') NOT NULL,
      imported_count INT UNSIGNED NOT NULL DEFAULT 0,
      error_code VARCHAR(80) NULL,
      error_message TEXT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      KEY idx_source_sync_runs_source_created (source_key, created_at),
      KEY idx_source_sync_runs_status_created (status, created_at)
    )`,
  );
  await pool.execute(
    `CREATE TABLE IF NOT EXISTS device_push_tokens (
      id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
      user_id BIGINT UNSIGNED NOT NULL,
      platform ENUM('android','ios','web') NOT NULL,
      token VARCHAR(512) NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      UNIQUE KEY uniq_device_push_token (token),
      KEY idx_device_push_tokens_user (user_id),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
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
      day_index INT UNSIGNED NOT NULL DEFAULT 1,
      requester_user_id BIGINT UNSIGNED NOT NULL,
      target_user_id BIGINT UNSIGNED NOT NULL,
      status ENUM('pending','accepted','declined','expired','cancelled') NOT NULL DEFAULT 'pending',
      response_message VARCHAR(80) NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      expires_at TIMESTAMP NULL,
      responded_at TIMESTAMP NULL,
      FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
      FOREIGN KEY (requester_user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (target_user_id) REFERENCES users(id) ON DELETE CASCADE,
      KEY idx_event_recognition_event (event_id),
      KEY idx_event_recognition_target (target_user_id),
      KEY idx_event_recognition_requester (requester_user_id)
    )`,
  );
  await ensureColumn({
    tableName: 'event_recognition_requests',
    columnName: 'day_index',
    definition: 'INT UNSIGNED NOT NULL DEFAULT 1',
  });
  await ensureColumn({
    tableName: 'event_recognition_requests',
    columnName: 'expires_at',
    definition: 'TIMESTAMP NULL',
  });
  await pool.execute(
    `CREATE TABLE IF NOT EXISTS user_blocks (
      blocker_user_id BIGINT UNSIGNED NOT NULL,
      blocked_user_id BIGINT UNSIGNED NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (blocker_user_id, blocked_user_id),
      FOREIGN KEY (blocker_user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (blocked_user_id) REFERENCES users(id) ON DELETE CASCADE
    )`,
  );
}

async function ensureColumn({ tableName, columnName, definition }) {
  const [rows] = await pool.execute(
    `SELECT COLUMN_NAME
       FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = ?
        AND COLUMN_NAME = ?
      LIMIT 1`,
    [tableName, columnName],
  );
  if (rows.length > 0) return false;
  await pool.query(`ALTER TABLE \`${tableName}\` ADD COLUMN \`${columnName}\` ${definition}`);
  return true;
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

async function recordSourceSyncRun({
  sourceKey,
  sourceUrl,
  status,
  importedCount = 0,
  errorCode = null,
  errorMessage = null,
}) {
  await pool.execute(
    `INSERT INTO source_sync_runs
      (source_key, source_url, status, imported_count, error_code, error_message)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [
      sourceKey,
      sourceUrl,
      status,
      importedCount,
      errorCode,
      errorMessage == null ? null : String(errorMessage).slice(0, 2000),
    ],
  );
}

function summarizeError(error) {
  if (error?.response?.headers?.['cf-mitigated'] === 'challenge') {
    return 'Cloudflare 驗證攔截：未取得活動資料；既有資料保留';
  }
  const responseStatus = error?.response?.status;
  const responseStatusText = error?.response?.statusText;
  if (responseStatus != null) {
    return [responseStatus, responseStatusText, error?.message]
      .filter(Boolean)
      .join(' ');
  }
  return error?.message?.toString() ?? error?.code?.toString() ?? 'unknown_error';
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
    return fetchLineProfile(accessToken);
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
  const sourceName =
    String(body.sourceName ?? '官方人員建立').trim() || '官方人員建立';
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

function normalizeBookingVisibility(value) {
  return value === 'circle' ? 'circle' : 'public';
}

function normalizeLocationVisibility(value) {
  return ['public', 'followed', 'circle'].includes(value) ? value : 'circle';
}

function normalizePushPlatform(value) {
  const platform = String(value ?? '').trim().toLowerCase();
  return ['android', 'ios', 'web'].includes(platform) ? platform : null;
}

function normalizeLocationExpiry(value) {
  const minutes = Number(value);
  if ([15, 30, 60].includes(minutes)) return minutes;
  return 30;
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
    "SELECT id FROM users WHERE session_token = ? AND account_status = 'active' LIMIT 1",
    [token],
  );
  return rows[0]?.id ?? null;
}

async function hasBlockingRelation(leftUserId, rightUserId) {
  const [rows] = await pool.execute(
    `SELECT blocker_user_id
       FROM user_blocks
      WHERE (blocker_user_id = ? AND blocked_user_id = ?)
         OR (blocker_user_id = ? AND blocked_user_id = ?)
      LIMIT 1`,
    [leftUserId, rightUserId, rightUserId, leftUserId],
  );
  return rows.length > 0;
}

async function userHasEventDayBooking(eventId, userId, dayIndex) {
  const [rows] = await pool.execute(
    `SELECT id
       FROM event_bookings
      WHERE event_id = ?
        AND user_id = ?
        AND day_index = ?
      LIMIT 1`,
    [eventId, userId, dayIndex],
  );
  return rows.length > 0;
}

async function recognitionCooldownState({
  eventId,
  dayIndex,
  requesterUserId,
  targetUserId,
}) {
  const [rows] = await pool.execute(
    `SELECT status,
            expires_at > CURRENT_TIMESTAMP AS isPendingActive,
            created_at >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 HOUR) AS isWithinHour,
            COALESCE(responded_at, created_at) >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 15 MINUTE) AS isRecentResponse
       FROM event_recognition_requests
      WHERE event_id = ?
        AND day_index = ?
        AND requester_user_id = ?
        AND target_user_id = ?
        AND created_at >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 HOUR)
      ORDER BY created_at DESC`,
    [eventId, dayIndex, requesterUserId, targetUserId],
  );
  if (rows.some((row) => row.status === 'pending' && row.isPendingActive)) {
    return { ok: false, error: 'recognition_pending_exists' };
  }
  if (
    rows.some(
      (row) => row.status === 'declined' && row.isRecentResponse,
    )
  ) {
    return { ok: false, error: 'recognition_declined_cooldown' };
  }
  if (rows.filter((row) => row.isWithinHour).length >= 3) {
    return { ok: false, error: 'recognition_hourly_limit' };
  }
  return { ok: true };
}

async function notifyRecognitionRequest({
  requestId,
  eventId,
  dayIndex,
  requesterUserId,
  targetUserId,
}) {
  try {
    const [[requester]] = await pool.execute(
      `SELECT nickname
         FROM users
        WHERE id = ?
        LIMIT 1`,
      [requesterUserId],
    );
    const [tokenRows] = await pool.execute(
      `SELECT t.token
         FROM device_push_tokens t INNER JOIN users u ON u.id = t.user_id
        WHERE t.user_id = ? AND u.session_token IS NOT NULL AND u.account_status = 'active'`,
      [targetUserId],
    );
    const tokens = tokenRows.map((row) => row.token);
    const result = await sendRecognitionPush({
      tokens,
      requestId,
      eventId,
      dayIndex,
      requesterName: requester?.nickname,
    });
    if (result.invalidTokens.length > 0) {
      const placeholders = result.invalidTokens.map(() => '?').join(',');
      await pool.execute(
        `DELETE FROM device_push_tokens
          WHERE token IN (${placeholders})`,
        result.invalidTokens,
      );
    }
    return {
      sent: result.successCount,
      failed: result.failureCount,
    };
  } catch (error) {
    console.warn('[push] recognition notification failed', {
      requestId,
      targetUserId,
      message: error?.message,
    });
    return { sent: 0, failed: 0, error: 'push_send_failed' };
  }
}

async function resolveEventDayIndex(eventId, userId, requestedDayIndex = null) {
  const parsed = Number(requestedDayIndex);
  if (Number.isInteger(parsed) && parsed > 0) {
    const [rows] = await pool.execute(
      `SELECT day_index AS dayIndex
         FROM event_bookings b INNER JOIN events e ON e.id = b.event_id
        WHERE b.event_id = ?
          AND b.user_id = ?
          AND b.day_index = ?
          AND e.status = 'approved'
          AND DATE_ADD(e.start_date, INTERVAL (b.day_index - 1) DAY) = DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+08:00'))
        LIMIT 1`,
      [eventId, userId, parsed],
    );
    return rows[0]?.dayIndex ?? null;
  }
  const [rows] = await pool.execute(
    `SELECT day_index AS dayIndex
       FROM event_bookings b INNER JOIN events e ON e.id = b.event_id
      WHERE b.event_id = ?
        AND b.user_id = ?
        AND e.status = 'approved'
        AND DATE_ADD(e.start_date, INTERVAL (b.day_index - 1) DAY) = DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '+08:00'))
      ORDER BY b.day_index ASC
      LIMIT 1`,
    [eventId, userId],
  );
  return rows[0]?.dayIndex ?? null;
}

async function requireAdmin(req, res, next) {
  try {
    const [rows] = await pool.execute(
      "SELECT is_admin AS isAdmin FROM users WHERE id = ? AND account_status = 'active' LIMIT 1",
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
            profile_roles_json AS profileRolesJson,
            other_photo_urls_json AS otherPhotoUrlsJson,
            booking_visibility AS bookingVisibility,
            onboarding_completed AS onboardingCompleted
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
            users.profile_roles_json AS profileRolesJson,
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
  if (
    viewerUserId != null &&
    Number(viewerUserId) !== Number(id) &&
    (await hasBlockingRelation(id, viewerUserId))
  ) {
    return null;
  }
  const pitWorks = await fetchUserPitWorks(id);
  profile.landmine = '';
  if (profile.gender === '不公開') {
    profile.gender = '';
  }
  return {
    id,
    isMe: Number(viewerUserId) === Number(id),
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
    profileRolesJson,
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
    profileRoles: parseJsonStringArray(profileRolesJson).filter((role) =>
      ['coser', 'photographer', 'manager', 'self'].includes(role),
    ),
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

function publicAppBaseUrl(req) {
  const configured = process.env.PUBLIC_APP_URL;
  return (configured || `${req.protocol}://${req.get('host')}/app`).replace(/\/$/, '');
}

function publicUploadUrl(req, fileName) {
  const origin = process.env.PUBLIC_APP_URL ? new URL(process.env.PUBLIC_APP_URL).origin : `${req.protocol}://${req.get('host')}`;
  return `${origin}/uploads/${fileName}`;
}
