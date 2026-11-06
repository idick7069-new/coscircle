import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import {inTransaction} from './db-transaction.js';

export const accountDeletionTableSql = [
  `CREATE TABLE IF NOT EXISTS account_uploads (
    file_name VARCHAR(64) PRIMARY KEY,
    user_id BIGINT UNSIGNED NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY idx_account_uploads_user (user_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS account_upload_cleanup (
    file_name VARCHAR(64) PRIMARY KEY,
    attempts INT UNSIGNED NOT NULL DEFAULT 0,
    last_attempt_at_ms BIGINT UNSIGNED NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  ) ENGINE=InnoDB`,
  `CREATE TABLE IF NOT EXISTS account_legacy_upload_review (
    file_name VARCHAR(64) PRIMARY KEY,
    reason VARCHAR(32) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  ) ENGINE=InnoDB`,
];

export async function ensureAccountDeletionTables(pool) {
  for (const sql of accountDeletionTableSql) await pool.execute(sql);
}

const uploadName = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png|webp)$/;
const errors = new Map([
  ['invalid_confirmation', 400], ['invalid_user_id', 400], ['invalid_account_update', 400],
  ['invalid_account_status', 400], ['cannot_delete_self', 400], ['cannot_suspend_self', 400],
  ['cannot_revoke_self_admin', 400], ['authentication_required', 401],
  ['reauthentication_required', 403], ['admin_required', 403], ['user_not_found', 404],
  ['last_admin', 409], ['line_login_unavailable', 503], ['line_login_not_configured', 503],
]);
function fail(code) {
  throw Object.assign(new Error(code), {code, status: errors.get(code) ?? 400});
}
function validId(id) {
  return (typeof id === 'string' && /^[1-9][0-9]*$/.test(id)) ||
    (typeof id === 'number' && Number.isSafeInteger(id) && id > 0);
}
function sameToken(actual, supplied) {
  if (typeof actual !== 'string' || typeof supplied !== 'string' || !supplied || supplied.length > 191) return false;
  const a = Buffer.from(actual);
  const b = Buffer.from(supplied);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
function activeAdmin(user) {
  return Boolean(user && Number(user.is_admin) === 1 && user.account_status === 'active');
}

export function createAccountDeletionService(pool, {
  verifyPassword, fetchLineProfile, uploadDir,
  publicUploadOrigins = [], deleteAdditionalUserData = async () => {}, fileSystem = fs, now = Date.now,
} = {}) {
  const directory = uploadDir ? path.resolve(uploadDir) : null;
  const origins = new Set(publicUploadOrigins.map(origin => {
    const url = new URL(origin);
    if (url.protocol !== 'https:' || url.username || url.password || url.pathname !== '/' || url.search || url.hash) {
      throw new Error('invalid_public_upload_origin');
    }
    return url.origin;
  }));
  function localUpload(value) {
    if (typeof value !== 'string') return null;
    try {
      const url = new URL(value);
      const name = url.pathname.slice('/uploads/'.length);
      if (!origins.has(url.origin) || url.username || url.password ||
          url.pathname !== `/uploads/${name}` || !uploadName.test(name)) return null;
      return name;
    } catch { return null; }
  }
  function photos(value) {
    if (value == null || value === '') return [];
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed) && parsed.every(url => typeof url === 'string') ? parsed : null;
    } catch { return null; }
  }

  // Every operation that removes an active admin takes this lock before user locks.
  async function lockAdmins(db) {
    const [admins] = await db.execute(`SELECT id FROM users
      WHERE is_admin=TRUE AND account_status='active' ORDER BY id FOR UPDATE`);
    return admins;
  }
  function protectLastAdmin(user, admins) {
    if (activeAdmin(user) && admins.length <= 1) fail('last_admin');
  }
  async function lockUser(db, userId) {
    const [[user]] = await db.execute('SELECT * FROM users WHERE id=? FOR UPDATE', [userId]);
    return user;
  }
  async function adminOperation({userId, adminUserId, sessionToken}, work) {
    if (!validId(userId) || !validId(adminUserId)) fail('invalid_user_id');
    return inTransaction(pool, async db => {
      const admins = await lockAdmins(db);
      const actor = await lockUser(db, adminUserId);
      if (!actor || !sameToken(actor.session_token, sessionToken) || actor.account_status !== 'active') {
        fail('authentication_required');
      }
      if (!activeAdmin(actor)) fail('admin_required');
      const target = String(userId) === String(adminUserId) ? actor : await lockUser(db, userId);
      if (!target) fail('user_not_found');
      return work(db, target, admins);
    });
  }
  async function prepareUploads(db, user) {
    const [users] = await db.execute('SELECT id,avatar_url,other_photo_urls_json FROM users ORDER BY id FOR UPDATE');
    const [bookings] = await db.execute('SELECT id,user_id,outfit_image_url FROM event_bookings ORDER BY id FOR UPDATE');
    const [ownership] = await db.execute('SELECT file_name,user_id FROM account_uploads ORDER BY file_name FOR UPDATE');
    const owners = new Map(ownership.map(row => [row.file_name, row.user_id]));
    const references = new Map();
    let unreadableReferences = 0;
    const add = (value, userId) => {
      const name = localUpload(value);
      if (!name) return;
      if (!references.has(name)) references.set(name, new Set());
      references.get(name).add(String(userId));
    };
    for (const row of users) {
      add(row.avatar_url, row.id);
      const urls = photos(row.other_photo_urls_json);
      if (!urls) unreadableReferences++;
      else for (const url of urls) add(url, row.id);
    }
    for (const row of bookings) add(row.outfit_image_url, row.user_id);
    const result = {adopted: 0, review: 0, unreadableReferences};
    for (const [name, userIds] of references) {
      if (!userIds.has(String(user.id)) || owners.has(name)) continue;
      // Referencing a public URL is not proof that this account uploaded the file.
      await db.execute('INSERT IGNORE INTO account_legacy_upload_review (file_name,reason) VALUES (?,?)',
        [name, unreadableReferences ? 'unreadable_references' : userIds.size > 1
          ? 'shared_references' : 'unverified_ownership']);
      result.review++;
    }
    const owned = new Set([...owners].filter(([, id]) => id != null && String(id) === String(user.id)).map(([name]) => name));
    // Tracked ownership wins over copied references in someone else's profile.
    for (const row of users) {
      if (String(row.id) === String(user.id)) continue;
      const avatar = owned.has(localUpload(row.avatar_url)) ? null : row.avatar_url;
      const urls = photos(row.other_photo_urls_json);
      const kept = urls?.filter(url => !owned.has(localUpload(url)));
      if (avatar !== row.avatar_url || (kept && kept.length !== urls.length)) {
        await db.execute('UPDATE users SET avatar_url=?,other_photo_urls_json=? WHERE id=?',
          [avatar, kept && kept.length !== urls.length ? JSON.stringify(kept) : row.other_photo_urls_json, row.id]);
      }
    }
    for (const row of bookings) {
      if (String(row.user_id) !== String(user.id) && owned.has(localUpload(row.outfit_image_url))) {
        await db.execute('UPDATE event_bookings SET outfit_image_url=NULL WHERE id=?', [row.id]);
      }
    }
    for (const name of owned) {
      if (!uploadName.test(name)) throw new Error('invalid_owned_upload');
      await db.execute('INSERT INTO account_upload_cleanup (file_name) VALUES (?)', [name]);
      await db.execute('DELETE FROM account_legacy_upload_review WHERE file_name=?', [name]);
    }
    return result;
  }
  async function eraseUser(db, user) {
    const legacyUploads = await prepareUploads(db, user);
    // SET NULL on submissions retains personal text. Delete these explicitly.
    await db.execute('DELETE FROM event_submissions WHERE submitter_user_id=?', [user.id]);
    await db.execute(`DELETE FROM admin_audit_logs WHERE admin_user_id=?
      OR (target_id=? AND action LIKE 'user.%')`, [user.id, String(user.id)]);
    await deleteAdditionalUserData(db, user.id);
    // The schema cascades identities, email links, bookings, social and location data.
    await db.execute('DELETE FROM users WHERE id=?', [user.id]);
    return {legacyUploads};
  }
  async function cleanupUploads({limit = 100} = {}) {
    if (!directory) throw new Error('upload_directory_required');
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 1000) throw new Error('invalid_cleanup_limit');
    const [pending] = await pool.execute(`SELECT file_name FROM account_upload_cleanup
      ORDER BY COALESCE(last_attempt_at_ms, 0), file_name LIMIT ${limit}`);
    let cleaned = 0;
    let failed = 0;
    for (const {file_name: name} of pending) {
      try {
        const removed = await inTransaction(pool, async db => {
          const [[queued]] = await db.execute('SELECT file_name FROM account_upload_cleanup WHERE file_name=? FOR UPDATE', [name]);
          if (!queued) return false;
          const [[owned]] = await db.execute('SELECT user_id FROM account_uploads WHERE file_name=? FOR UPDATE', [name]);
          if (!uploadName.test(name) || !owned || owned.user_id != null) throw new Error('unsafe_upload_cleanup');
          try { await fileSystem.unlink(path.join(directory, name)); }
          catch (error) { if (error.code !== 'ENOENT') throw error; }
          await db.execute('DELETE FROM account_upload_cleanup WHERE file_name=?', [name]);
          await db.execute('DELETE FROM account_uploads WHERE file_name=? AND user_id IS NULL', [name]);
          return true;
        });
        if (removed) cleaned++;
      } catch {
        failed++;
        await pool.execute(`UPDATE account_upload_cleanup SET attempts=attempts+1,
          last_attempt_at_ms=? WHERE file_name=?`, [now(), name]);
      }
    }
    return {cleaned, failed};
  }
  async function afterDeletion() {
    // A committed deletion remains successful when disk cleanup needs a retry.
    try { await cleanupUploads(); } catch { /* The durable queue survives restarts. */ }
  }
  async function deleteAccount({sessionToken, confirmation, password, lineAccessToken} = {}) {
    if (confirmation !== 'DELETE') fail('invalid_confirmation');
    if (typeof sessionToken !== 'string' || !sessionToken || sessionToken.length > 191) fail('authentication_required');
    const hasPassword = typeof password === 'string' && password.length > 0 && password.length <= 1024;
    const hasLine = typeof lineAccessToken === 'string' && lineAccessToken.length >= 12 && lineAccessToken.length <= 4096;
    if (hasPassword === hasLine || (password != null && !hasPassword) || (lineAccessToken != null && !hasLine)) {
      fail('reauthentication_required');
    }
    let lineSubject;
    if (hasLine) {
      if (!fetchLineProfile) fail('reauthentication_required');
      try {
        const profile = await fetchLineProfile(lineAccessToken);
        if (typeof profile?.id !== 'string' || !profile.id) fail('reauthentication_required');
        lineSubject = profile.id;
      } catch (error) {
        if (['line_login_unavailable', 'line_login_not_configured'].includes(error.code)) fail(error.code);
        fail('reauthentication_required');
      }
    }
    const result = await inTransaction(pool, async db => {
      const admins = await lockAdmins(db);
      const [[user]] = await db.execute('SELECT * FROM users WHERE session_token=? FOR UPDATE', [sessionToken]);
      if (!user || !sameToken(user.session_token, sessionToken) || user.account_status !== 'active') {
        fail('authentication_required');
      }
      const [identities] = await db.execute('SELECT provider, provider_user_id, password_hash FROM user_auth_identities WHERE user_id=? FOR UPDATE', [user.id]);
      if (hasPassword) {
        const email = identities.find(identity => identity.provider === 'email');
        if (!email?.password_hash || !verifyPassword || !await verifyPassword(password, email.password_hash)) {
          fail('reauthentication_required');
        }
      } else {
        const line = identities.find(identity => identity.provider === 'line');
        if (!line || lineSubject !== line.provider_user_id) fail('reauthentication_required');
      }
      protectLastAdmin(user, admins);
      return eraseUser(db, user);
    });
    await afterDeletion();
    return result;
  }
  async function adminDelete(input) {
    const result = await adminOperation(input, async (db, user, admins) => {
      if (String(user.id) === String(input.adminUserId)) fail('cannot_delete_self');
      protectLastAdmin(user, admins);
      return eraseUser(db, user);
    });
    await afterDeletion();
    return result;
  }
  async function updateAdminAccount(input) {
    const {status, isAdmin} = input;
    if ((status === undefined) === (isAdmin === undefined)) fail('invalid_account_update');
    if (status !== undefined && !['active', 'suspended'].includes(status)) fail('invalid_account_status');
    if (isAdmin !== undefined && typeof isAdmin !== 'boolean') fail('invalid_account_update');
    await adminOperation(input, async (db, user, admins) => {
      const self = String(user.id) === String(input.adminUserId);
      if (self && status === 'suspended') fail('cannot_suspend_self');
      if (self && isAdmin === false) fail('cannot_revoke_self_admin');
      if (status === 'suspended' || isAdmin === false) protectLastAdmin(user, admins);
      if (status !== undefined) {
        await db.execute(`UPDATE users SET account_status=?,
          session_token=CASE WHEN ?='suspended' THEN NULL ELSE session_token END WHERE id=?`, [status, status, user.id]);
        if (status === 'suspended') await db.execute('DELETE FROM device_push_tokens WHERE user_id=?', [user.id]);
      } else await db.execute('UPDATE users SET is_admin=? WHERE id=?', [Number(isAdmin), user.id]);
    });
  }
  async function storeUpload({userId, bytes, extension}) {
    if (!directory) throw new Error('upload_directory_required');
    if (!validId(userId)) fail('invalid_user_id');
    if (!Buffer.isBuffer(bytes) || !bytes.length || !['jpg', 'png', 'webp'].includes(extension)) throw new Error('invalid_upload');
    const fileName = `${crypto.randomUUID()}.${extension}`;
    // Commit ownership before writing bytes so a process crash cannot orphan a file.
    await inTransaction(pool, async db => {
      const user = await lockUser(db, userId);
      if (!user || user.account_status !== 'active') fail('authentication_required');
      await db.execute('INSERT INTO account_uploads (file_name,user_id) VALUES (?,?)', [fileName, userId]);
    });
    let collision;
    await inTransaction(pool, async db => {
      const user = await lockUser(db, userId);
      if (!user || user.account_status !== 'active') fail('authentication_required');
      const [[owned]] = await db.execute('SELECT user_id FROM account_uploads WHERE file_name=? FOR UPDATE', [fileName]);
      if (!owned || String(owned.user_id) !== String(userId)) fail('authentication_required');
      await fileSystem.mkdir(directory, {recursive: true});
      try { await fileSystem.writeFile(path.join(directory, fileName), bytes, {flag: 'wx'}); }
      catch (error) {
        if (error.code !== 'EEXIST') throw error;
        // Drop the claim while the user lock still excludes account deletion.
        await db.execute('DELETE FROM account_uploads WHERE file_name=? AND user_id=?', [fileName, userId]);
        collision = error;
      }
    });
    if (collision) throw collision;
    return {fileName};
  }
  return {deleteAccount, adminDelete, updateAdminAccount, storeUpload, cleanupUploads};
}

export function registerAccountDeletionRoutes(app, service, {production = false} = {}) {
  app.post('/api/me/delete-account', async (req, res) => {
    res.set('Cache-Control', 'no-store');
    if (production && !req.secure) return res.status(426).json({error: 'secure_transport_required'});
    try {
      const authorization = req.get('authorization');
      const sessionToken = typeof authorization === 'string' && authorization.startsWith('Bearer ')
        ? authorization.slice(7) : null;
      const {confirmation, password, lineAccessToken} = req.body ?? {};
      await service.deleteAccount({sessionToken, confirmation, password, lineAccessToken});
      res.status(204).end();
    } catch (error) {
      if (errors.has(error.code)) return res.status(errors.get(error.code)).json({error: error.code});
      // SQL and provider errors can contain secrets. Never forward them to the logger.
      res.status(503).json({error: 'account_deletion_unavailable'});
    }
  });
}
