import {createHash, timingSafeEqual} from 'node:crypto';

const reasons = new Set(['spam', 'harassment', 'sexual_content', 'hate', 'impersonation', 'privacy', 'other']);
const statuses = new Set(['pending', 'reviewing', 'resolved', 'dismissed']);
const actions = new Set(['none', 'suspend_user', 'remove_booking', 'remove_circle']);
const terminalStatuses = new Set(['resolved', 'dismissed']);
const targetFields = {
  user: ['targetUserId'],
  booking: ['targetUserId', 'eventId', 'dayIndex'],
  circle: ['circleId'],
};

function fail(status, code) {
  throw Object.assign(new Error(code), {status, code});
}

function userId(value, code = 'invalid_user_id') {
  if (typeof value !== 'string' || !/^[1-9]\d{0,19}$/.test(value) || BigInt(value) > 18446744073709551615n) {
    fail(400, code);
  }
  return value;
}

function numericId(value, code) {
  if (!Number.isSafeInteger(value) || value < 1) fail(400, code);
  return value;
}

function text(value, code) {
  if (value === undefined) return '';
  if (typeof value !== 'string' || [...value].length > 1000) fail(400, code);
  return value.trim();
}

export function validateReport(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) fail(400, 'invalid_report');
  const fields = typeof body.targetType === 'string' && Object.hasOwn(targetFields, body.targetType) && targetFields[body.targetType];
  if (!fields || !reasons.has(body.reason)) fail(400, 'invalid_report');
  const allowed = new Set(['targetType', 'reason', 'details', ...fields]);
  if (Object.keys(body).some((key) => !allowed.has(key))) fail(400, 'invalid_report_fields');
  const report = {targetType: body.targetType, reason: body.reason, details: text(body.details, 'invalid_details')};
  for (const field of fields) {
    report[field] = field === 'targetUserId'
      ? userId(body[field])
      : field === 'circleId' || field === 'eventId'
        ? userId(typeof body[field] === 'number' && Number.isSafeInteger(body[field]) ? String(body[field]) : body[field],
          field === 'circleId' ? 'invalid_circle_id' : 'invalid_event_id')
        : numericId(body[field], 'invalid_day_index');
  }
  if (report.dayIndex > 4294967295) fail(400, 'invalid_day_index');
  return report;
}

// These predicates match the profile, participants, and circle membership endpoints.
export const reportTargetQueries = {
  user: `SELECT CAST(u.id AS CHAR) AS targetUserId, u.nickname, u.bio,
      u.avatar_url AS avatarUrl, u.other_photo_urls_json AS otherPhotoUrls
    FROM users u WHERE u.id = ? AND u.account_status = 'active'
    AND u.public_code IS NOT NULL AND u.public_code <> ''
    AND NOT EXISTS (SELECT 1 FROM user_blocks b
      WHERE (b.blocker_user_id = ? AND b.blocked_user_id = u.id)
         OR (b.blocker_user_id = u.id AND b.blocked_user_id = ?)) FOR UPDATE`,
  booking: `SELECT CAST(eb.id AS CHAR) AS bookingId, CAST(u.id AS CHAR) AS targetUserId, u.nickname,
      eb.role, eb.character_name AS characterName, eb.message,
      eb.outfit_image_url AS outfitImageUrl, eb.interaction_tags AS interactionTags,
      eb.available_time AS availableTime, eb.presence_status AS presenceStatus,
      eb.work_id AS workId, eb.updated_at AS updatedAt
    FROM event_bookings eb INNER JOIN users u ON u.id = eb.user_id
    WHERE eb.user_id = ? AND eb.event_id = ? AND eb.day_index = ? AND u.account_status = 'active'
      AND NOT EXISTS (SELECT 1 FROM user_blocks b
        WHERE (b.blocker_user_id = ? AND b.blocked_user_id = u.id)
           OR (b.blocker_user_id = u.id AND b.blocked_user_id = ?))
      AND (u.booking_visibility = 'public' OR (u.booking_visibility = 'circle' AND EXISTS (
        SELECT 1 FROM circle_members mine INNER JOIN circle_members theirs
          ON theirs.circle_id = mine.circle_id AND theirs.user_id = u.id
        WHERE mine.user_id = ?))) FOR UPDATE`,
  circle: `SELECT CAST(c.id AS CHAR) AS circleId, CAST(c.owner_user_id AS CHAR) AS targetUserId, c.name, c.description
    FROM circles c INNER JOIN circle_members m ON m.circle_id = c.id
    WHERE c.id = ? AND m.user_id = ? FOR UPDATE`,
};

function targetBindings(report, reporterId) {
  if (report.targetType === 'user') return [report.targetUserId, reporterId, reporterId];
  if (report.targetType === 'circle') return [report.circleId, reporterId];
  return [report.targetUserId, report.eventId, report.dayIndex, reporterId, reporterId, reporterId];
}

function fingerprint(row) {
  return createHash('sha256').update(JSON.stringify(row)).digest('hex');
}

function photoUrl(value) {
  if (typeof value !== 'string' || value.length > 2048) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || !url.hostname || url.username || url.password || url.href.length > 2048) return null;
    return url.href;
  } catch {
    return null;
  }
}

function otherPhotos(value) {
  try {
    const photos = typeof value === 'string' ? JSON.parse(value) : value;
    return Array.isArray(photos) ? photos.map(photoUrl).filter(Boolean).slice(0, 3) : [];
  } catch {
    return [];
  }
}

function snapshot(type, row) {
  const fields = {
    user: {nickname: 80, bio: 500},
    booking: {nickname: 80, role: 40, characterName: 120, message: 500},
    circle: {name: 120, description: 500},
  }[type];
  const content = Object.fromEntries(Object.entries(fields).map(([key, limit]) => [key, [...String(row[key] ?? '')].slice(0, limit).join('')]));
  if (type === 'user') {
    content.avatarUrl = photoUrl(row.avatarUrl);
    content.otherPhotoUrls = otherPhotos(row.otherPhotoUrls);
  } else if (type === 'booking') {
    content.outfitImageUrl = photoUrl(row.outfitImageUrl);
  }
  return content;
}

async function transaction(pool, operation) {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const result = await operation(connection);
    await connection.commit();
    return result;
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

export async function submitReport(pool, reporterId, body) {
  const report = validateReport(body);
  if (!reporterId) fail(401, 'unauthorized');
  if (report.targetUserId === String(reporterId)) fail(400, 'cannot_report_self');
  return transaction(pool, async (connection) => {
    // Locking the reporter serializes duplicate checks across API processes.
    const [reporters] = await connection.execute(
      "SELECT id FROM users WHERE id = ? AND account_status = 'active' FOR UPDATE", [reporterId]);
    if (!reporters.length) fail(401, 'unauthorized');
    const [targets] = await connection.execute(reportTargetQueries[report.targetType], targetBindings(report, reporterId));
    const target = targets[0];
    if (!target) fail(404, 'report_target_unavailable');
    if (String(target.targetUserId) === String(reporterId)) fail(400, 'cannot_report_self');
    const [duplicates] = await connection.execute(
      `SELECT id FROM content_reports WHERE reporter_user_id = ? AND target_type = ?
        AND target_user_id <=> ? AND event_id <=> ? AND day_index <=> ? AND circle_id <=> ?
        AND (status IN ('pending','reviewing') OR created_at > DATE_SUB(UTC_TIMESTAMP(), INTERVAL 24 HOUR))
        LIMIT 1 FOR UPDATE`,
      [reporterId, report.targetType, target.targetUserId, report.eventId ?? null, report.dayIndex ?? null, report.circleId ?? null]);
    if (duplicates.length) fail(409, 'duplicate_report');
    const [result] = await connection.execute(
      `INSERT INTO content_reports (reporter_user_id, target_type, target_user_id, event_id, day_index,
        circle_id, target_booking_id, reason, details, target_snapshot, target_fingerprint, evidence_expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 90 DAY))`,
      [reporterId, report.targetType, target.targetUserId, report.eventId ?? null, report.dayIndex ?? null,
        report.circleId ?? null, target.bookingId ?? null, report.reason, report.details,
        JSON.stringify(snapshot(report.targetType, target)), fingerprint(target)]);
    return {id: String(result.insertId), status: 'pending'};
  });
}

async function requireReportAdmin(db, adminId, sessionToken, lock = false) {
  if (!adminId) fail(401, 'unauthorized');
  if (typeof sessionToken !== 'string' || !sessionToken || sessionToken.length > 191) fail(401, 'unauthorized');
  const [rows] = await db.execute(
    `SELECT id, session_token AS sessionToken FROM users WHERE id = ? AND is_admin = TRUE AND account_status = 'active'${lock ? ' FOR UPDATE' : ''}`, [adminId]);
  if (!rows.length) fail(403, 'admin_required');
  const expected = Buffer.from(rows[0].sessionToken ?? '');
  const actual = Buffer.from(sessionToken);
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) fail(401, 'unauthorized');
}

export async function purgeExpiredReportEvidence(db) {
  await db.execute(`UPDATE content_report_reviews SET note = NULL WHERE note IS NOT NULL AND report_id IN
    (SELECT id FROM content_reports WHERE evidence_expires_at <= UTC_TIMESTAMP())`);
  await db.execute(`UPDATE content_reports SET details = NULL, target_snapshot = NULL, target_fingerprint = NULL
    WHERE evidence_expires_at <= UTC_TIMESTAMP()
      AND (details IS NOT NULL OR target_snapshot IS NOT NULL OR target_fingerprint IS NOT NULL)`);
}

// Call inside every account-deletion transaction, before DELETE FROM users.
export async function eraseReportPersonalData(connection, deletedUserId) {
  await connection.execute('SELECT id FROM users WHERE id = ? FOR UPDATE', [deletedUserId]);
  await connection.execute(`UPDATE content_report_reviews SET note = NULL WHERE report_id IN
    (SELECT id FROM content_reports WHERE reporter_user_id = ? OR target_user_id = ?) OR admin_user_id = ?`,
  [deletedUserId, deletedUserId, deletedUserId]);
  await connection.execute(`UPDATE content_reports SET details = NULL, target_snapshot = NULL,
    target_fingerprint = NULL WHERE reporter_user_id = ? OR target_user_id = ?`, [deletedUserId, deletedUserId]);
}

function pageId(value) {
  return value === undefined ? null : userId(value, 'invalid_cursor');
}

function parseSnapshot(value) {
  return typeof value === 'string' ? JSON.parse(value) : value;
}

export async function listReports(pool, adminId, query = {}, sessionToken) {
  await requireReportAdmin(pool, adminId, sessionToken);
  const status = query.status ?? 'pending';
  if (!statuses.has(status)) fail(400, 'invalid_report_status');
  const beforeId = pageId(query.beforeId);
  await purgeExpiredReportEvidence(pool);
  const [rows] = await pool.execute(
    `SELECT CAST(id AS CHAR) AS id, CAST(reporter_user_id AS CHAR) AS reporterUserId,
      target_type AS targetType, CAST(target_user_id AS CHAR) AS targetUserId,
      CAST(event_id AS CHAR) AS eventId, day_index AS dayIndex, CAST(circle_id AS CHAR) AS circleId,
      reason, CASE WHEN evidence_expires_at > UTC_TIMESTAMP() THEN details ELSE NULL END AS details,
      CASE WHEN evidence_expires_at > UTC_TIMESTAMP() THEN target_snapshot ELSE NULL END AS snapshot,
      status, version, created_at AS createdAt, evidence_expires_at AS evidenceExpiresAt
    FROM content_reports WHERE status = ? AND (? IS NULL OR id < ?)
    ORDER BY content_reports.id DESC LIMIT 31`, [status, beforeId, beforeId]);
  const items = rows.slice(0, 30).map((row) => ({...row, snapshot: parseSnapshot(row.snapshot)}));
  const ids = items.map((row) => row.id);
  if (ids.length) {
    const [reviews] = await pool.execute(
      `SELECT CAST(r.report_id AS CHAR) AS reportId, CAST(r.admin_user_id AS CHAR) AS adminUserId,
        r.from_status AS fromStatus, r.to_status AS status, r.action,
        CASE WHEN c.evidence_expires_at > UTC_TIMESTAMP() THEN r.note ELSE NULL END AS note,
        r.created_at AS createdAt
      FROM (SELECT history.*, ROW_NUMBER() OVER (PARTITION BY report_id ORDER BY id DESC) AS position
        FROM content_report_reviews history WHERE report_id IN (${ids.map(() => '?').join(',')})) r
      INNER JOIN content_reports c ON c.id = r.report_id
      WHERE r.position <= 20 ORDER BY r.id ASC`, ids);
    for (const item of items) item.reviews = reviews.filter((review) => review.reportId === item.id);
  }
  return {items, nextBeforeId: rows.length > 30 ? items.at(-1).id : null};
}

function validateReview(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body) || !statuses.has(body.status) || !actions.has(body.action)) {
    fail(400, 'invalid_review');
  }
  if (Object.keys(body).some((key) => !['status', 'action', 'note', 'expectedVersion'].includes(key))) fail(400, 'invalid_review');
  if (body.expectedVersion !== undefined &&
      (!Number.isSafeInteger(body.expectedVersion) || body.expectedVersion < 1 || body.expectedVersion > 4294967295)) {
    fail(400, 'invalid_version');
  }
  if (body.action !== 'none' && body.status !== 'resolved') fail(400, 'action_requires_resolution');
  const note = text(body.note, 'invalid_note');
  if (body.action !== 'none' && !note) fail(400, 'review_note_required');
  return {...body, note};
}

async function currentTarget(connection, report) {
  if (report.targetType === 'user') {
    const [rows] = await connection.execute(`SELECT CAST(id AS CHAR) AS targetUserId, nickname, bio,
      avatar_url AS avatarUrl, other_photo_urls_json AS otherPhotoUrls FROM users WHERE id = ? FOR UPDATE`, [report.targetUserId]);
    return rows[0];
  }
  if (report.targetType === 'circle') {
    const [rows] = await connection.execute(`SELECT CAST(id AS CHAR) AS circleId, CAST(owner_user_id AS CHAR) AS targetUserId, name, description
      FROM circles WHERE id = ? FOR UPDATE`, [report.circleId]);
    return rows[0];
  }
  const [rows] = await connection.execute(`SELECT CAST(eb.id AS CHAR) AS bookingId, CAST(u.id AS CHAR) AS targetUserId, u.nickname,
    eb.role, eb.character_name AS characterName, eb.message,
    eb.outfit_image_url AS outfitImageUrl, eb.interaction_tags AS interactionTags,
    eb.available_time AS availableTime, eb.presence_status AS presenceStatus,
    eb.work_id AS workId, eb.updated_at AS updatedAt
    FROM event_bookings eb INNER JOIN users u ON u.id = eb.user_id
    WHERE eb.id = ? AND eb.event_id = ? AND eb.user_id = ? AND eb.day_index = ? FOR UPDATE`,
  [report.targetBookingId, report.eventId, report.targetUserId, report.dayIndex]);
  return rows[0];
}

export async function reviewReport(pool, adminId, reportId, body, sessionToken) {
  userId(reportId, 'invalid_report_id');
  const review = validateReview(body);
  if (!adminId) fail(401, 'unauthorized');
  return transaction(pool, async (connection) => {
    await requireReportAdmin(connection, adminId, sessionToken, true);
    const [rows] = await connection.execute(`SELECT CAST(id AS CHAR) AS id, target_type AS targetType, CAST(target_user_id AS CHAR) AS targetUserId,
      CAST(event_id AS CHAR) AS eventId, day_index AS dayIndex, CAST(circle_id AS CHAR) AS circleId, CAST(target_booking_id AS CHAR) AS targetBookingId,
      status, version, target_fingerprint AS targetFingerprint,
      evidence_expires_at > UTC_TIMESTAMP() AS evidenceAvailable
      FROM content_reports WHERE id = ? FOR UPDATE`, [reportId]);
    const report = rows[0];
    if (!report) fail(404, 'report_not_found');
    if (terminalStatuses.has(report.status) || review.status === report.status ||
        (review.expectedVersion !== undefined && review.expectedVersion !== report.version)) {
      fail(409, 'stale_report');
    }
    const validActions = ['none', 'suspend_user', {booking: 'remove_booking', circle: 'remove_circle'}[report.targetType]];
    if (!validActions.includes(review.action)) fail(400, 'action_target_mismatch');
    if (review.action !== 'none') {
      if (review.action === 'suspend_user') {
        const [users] = await connection.execute('SELECT is_admin AS isAdmin FROM users WHERE id = ? FOR UPDATE', [report.targetUserId]);
        if (users[0]?.isAdmin) fail(403, 'protected_admin_account');
      }
      if (!report.evidenceAvailable || !report.targetFingerprint) fail(409, 'report_evidence_unavailable');
      const target = await currentTarget(connection, report);
      if (!target || fingerprint(target) !== report.targetFingerprint) fail(409, 'report_target_changed');
      let result;
      if (review.action === 'suspend_user') {
        [result] = await connection.execute(`UPDATE users SET account_status = 'suspended', session_token = NULL
          WHERE id = ? AND account_status = 'active' AND is_admin = FALSE`, [report.targetUserId]);
      } else if (review.action === 'remove_booking') {
        [result] = await connection.execute('DELETE FROM event_bookings WHERE id = ?', [report.targetBookingId]);
      } else {
        [result] = await connection.execute('DELETE FROM circles WHERE id = ?', [report.circleId]);
      }
      if (result.affectedRows !== 1) fail(409, 'report_target_changed');
    }
    const [updated] = await connection.execute(`UPDATE content_reports SET status = ?, version = version + 1
      WHERE id = ? AND version = ? AND status IN ('pending','reviewing')`, [review.status, reportId, report.version]);
    if (updated.affectedRows !== 1) fail(409, 'stale_report');
    await connection.execute(`INSERT INTO content_report_reviews
      (report_id, admin_user_id, from_status, to_status, action, note) VALUES (?, ?, ?, ?, ?, ?)`,
    [reportId, adminId, report.status, review.status, review.action, report.evidenceAvailable ? review.note : null]);
    return {id: reportId, status: review.status, version: report.version + 1};
  });
}

function route(handler) {
  return async (req, res, next) => {
    res.set('Cache-Control', 'private, no-store');
    try {
      await handler(req, res);
    } catch (error) {
      if (error.status) res.status(error.status).json({error: error.code});
      else next(error);
    }
  };
}

// Register after authentication and the main server's bounded report rate limiter.
export function registerReportRoutes(app, pool) {
  app.post('/api/reports', route(async (req, res) => {
    res.status(201).json(await submitReport(pool, req.userId, req.body));
  }));
}

// Register after app.use('/api/admin', requireAdmin). Each operation rechecks privileges.
export function registerReportAdminRoutes(app, pool) {
  const sessionToken = req => /^Bearer ([^\s]+)$/i.exec(req.get('authorization') ?? '')?.[1];
  app.get('/api/admin/reports', route(async (req, res) => {
    res.json(await listReports(pool, req.userId, req.query, sessionToken(req)));
  }));
  app.post('/api/admin/reports/:id/review', route(async (req, res) => {
    res.json(await reviewReport(pool, req.userId, req.params.id, req.body, sessionToken(req)));
  }));
}
