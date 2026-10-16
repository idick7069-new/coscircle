import crypto from 'node:crypto';
import {inTransaction} from './db-transaction.js';

export const emailActionTableSql = `CREATE TABLE IF NOT EXISTS email_action_tokens (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  identity_id BIGINT UNSIGNED NOT NULL,
  kind VARCHAR(32) NOT NULL,
  token_hash CHAR(64) NOT NULL,
  email_snapshot VARCHAR(191) NOT NULL,
  created_at_ms BIGINT UNSIGNED NOT NULL,
  expires_at_ms BIGINT UNSIGNED NOT NULL,
  consumed_at_ms BIGINT UNSIGNED NULL,
  UNIQUE KEY uniq_email_action_hash (token_hash),
  KEY idx_email_action_identity_time (identity_id, kind, created_at_ms),
  CONSTRAINT fk_email_action_identity FOREIGN KEY (identity_id) REFERENCES user_auth_identities(id) ON DELETE CASCADE
)`;

function fail(code, status = 400) {
  throw Object.assign(new Error(code), {code, status});
}
export function normalizeAccountEmail(value) {
  if (typeof value !== 'string') return null;
  const email = value.trim().toLowerCase();
  return email.length <= 191 && /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(email) ? email : null;
}
function tokenHash(token) {
  if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token)) fail('invalid_or_expired_email_link');
  return crypto.createHash('sha256').update(token).digest('hex');
}

export function createEmailAccountService(pool, {mail, publicAppUrl, hashPassword, now = Date.now}) {
  function ready() {
    const status = mail.status();
    if (!status.enabled || !status.configured) fail('account_mail_unavailable', 503);
    try {
      const url = new URL(publicAppUrl);
      if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) throw new Error();
    } catch { fail('account_mail_unavailable', 503); }
  }
  async function status(userId) {
    const [[identity]] = await pool.execute(`SELECT provider_user_id AS email, verified_at AS verifiedAt
      FROM user_auth_identities WHERE user_id=? AND provider='email'`, [userId]);
    const transport = mail.status();
    return {email: identity?.email ?? null, verified: Boolean(identity?.verifiedAt),
      available: transport.enabled && transport.configured};
  }
  async function issue({userId, email, kind}) {
    ready();
    const [identities] = await pool.execute(`SELECT i.id, i.user_id AS userId, i.provider_user_id AS email,
      i.verified_at AS verifiedAt FROM user_auth_identities i INNER JOIN users u ON u.id=i.user_id
      WHERE i.provider='email' AND ${userId != null ? 'i.user_id=?' : 'i.provider_user_id=?'}
      AND u.account_status='active'`, [userId ?? email]);
    const identity = identities[0];
    if (!identity || (kind === 'verify-email' && identity.verifiedAt)) return {requested: true};
    const token = crypto.randomBytes(32).toString('hex');
    const hash = tokenHash(token);
    const created = now();
    const inserted = await inTransaction(pool, async db => {
      const [[user]] = await db.execute('SELECT id, account_status AS accountStatus FROM users WHERE id=? FOR UPDATE', [identity.userId]);
      if (!user || user.accountStatus !== 'active') return false;
      const [[current]] = await db.execute(`SELECT provider_user_id AS email, verified_at AS verifiedAt
        FROM user_auth_identities WHERE id=? AND provider='email'`, [identity.id]);
      if (!current || current.email !== identity.email || (kind === 'verify-email' && current.verifiedAt)) return false;
      const [[counts]] = await db.execute(`SELECT COUNT(*) AS count, MAX(created_at_ms) AS latest
        FROM email_action_tokens WHERE identity_id=? AND created_at_ms>?`, [identity.id, created - 86400000]);
      if (Number(counts.count) >= 6 || (counts.latest != null && created - Number(counts.latest) < 60000)) {
        if (userId != null) fail('email_resend_cooldown', 429);
        return false;
      }
      await db.execute(`INSERT INTO email_action_tokens
        (identity_id,kind,token_hash,email_snapshot,created_at_ms,expires_at_ms)
        VALUES (?,?,?,?,?,?)`, [identity.id, kind, hash, identity.email, created,
        created + (kind === 'verify-email' ? 3600000 : 900000)]);
      return true;
    });
    if (!inserted) return {requested: true};
    const actionUrl = `${publicAppUrl.replace(/\/+$/, '')}/#/${kind}?token=${token}`;
    try {
      const options = {to: identity.email, actionUrl, requestId: hash};
      if (kind === 'verify-email') await mail.sendVerification(options);
      else await mail.sendPasswordReset(options);
    } catch (error) {
      // Unknown delivery may still arrive; keep that link valid. Definitive
      // rejections are revoked, without logging tokens or provider bodies.
      if (error.code !== 'mail_delivery_unknown') {
        await pool.execute('UPDATE email_action_tokens SET consumed_at_ms=? WHERE token_hash=?', [now(), hash]);
      }
      fail('account_mail_unavailable', 503);
    }
    return {requested: true};
  }

  async function consume(token, kind, password) {
    const hash = tokenHash(token);
    if (kind === 'reset-password' && (typeof password !== 'string' || password.length < 8 || password.length > 1024)) {
      fail('invalid_new_password');
    }
    const [[reference]] = await pool.execute(`SELECT i.user_id AS userId FROM email_action_tokens t
      INNER JOIN user_auth_identities i ON i.id=t.identity_id WHERE t.token_hash=? AND t.kind=?`, [hash, kind]);
    if (!reference) fail('invalid_or_expired_email_link');
    const newHash = kind === 'reset-password' ? await hashPassword(password) : null;
    const result = await inTransaction(pool, async db => {
      // Same lock order as issuance and account linking: user first.
      const [[user]] = await db.execute('SELECT id, account_status AS accountStatus FROM users WHERE id=? FOR UPDATE', [reference.userId]);
      const [[action]] = await db.execute(`SELECT t.identity_id AS identityId, t.email_snapshot AS email,
        t.expires_at_ms AS expiresAt, t.consumed_at_ms AS consumedAt, i.provider_user_id AS currentEmail,
        i.provider AS provider FROM email_action_tokens t INNER JOIN user_auth_identities i ON i.id=t.identity_id
        WHERE t.token_hash=? AND t.kind=? FOR UPDATE`, [hash, kind]);
      if (!user || user.accountStatus !== 'active' || !action || action.consumedAt != null ||
          Number(action.expiresAt) <= now() || action.provider !== 'email' || action.email !== action.currentEmail) {
        fail('invalid_or_expired_email_link');
      }
      if (kind === 'reset-password') {
        await db.execute('UPDATE user_auth_identities SET password_hash=?, verified_at=UTC_TIMESTAMP() WHERE id=?', [newHash, action.identityId]);
        await db.execute(`UPDATE users SET session_token=NULL,
          password_hash=CASE WHEN provider='email' THEN ? ELSE password_hash END WHERE id=?`, [newHash, user.id]);
        await db.execute('DELETE FROM device_push_tokens WHERE user_id=?', [user.id]);
        await db.execute('UPDATE email_action_tokens SET consumed_at_ms=? WHERE identity_id=? AND consumed_at_ms IS NULL', [now(), action.identityId]);
      } else {
        await db.execute('UPDATE user_auth_identities SET verified_at=UTC_TIMESTAMP() WHERE id=?', [action.identityId]);
        await db.execute('UPDATE email_action_tokens SET consumed_at_ms=? WHERE identity_id=? AND kind=? AND consumed_at_ms IS NULL',
          [now(), action.identityId, kind]);
      }
      return {email: action.email};
    });
    if (kind === 'reset-password') {
      mail.sendPasswordChanged({to: result.email, requestId: `changed-${hash}`})
        .catch(() => console.warn('[account-mail] password change notification unavailable'));
    }
    return {completed: true};
  }
  return {ready, status, requestVerification: userId => issue({userId, kind: 'verify-email'}),
    requestReset: email => issue({email, kind: 'reset-password'}),
    verify: token => consume(token, 'verify-email'),
    reset: (token, password) => consume(token, 'reset-password', password)};
}

export function registerEmailAccountRoutes(app, service, {privateRoutes = false, production = false} = {}) {
  const handle = work => async (req, res, next) => {
    try {
      res.set('Cache-Control', 'no-store');
      if (production && !req.secure) return res.status(426).json({error: 'secure_transport_required'});
      await work(req, res);
    } catch (error) {
      if (['account_mail_unavailable', 'email_resend_cooldown', 'invalid_or_expired_email_link',
        'invalid_new_password', 'invalid_email'].includes(error.code)) {
        return res.status(error.status).json({error: error.code});
      }
      // Do not forward SQL exceptions containing token/password parameters.
      console.warn('[account-mail] operation unavailable');
      res.status(503).json({error: 'account_mail_unavailable'});
    }
  };
  if (privateRoutes) {
    app.get('/api/me/email-status', handle(async (req, res) => res.json(await service.status(req.userId))));
    app.post('/api/me/email-verification', handle(async (req, res) => res.json(await service.requestVerification(req.userId))));
    return;
  }
  app.post('/api/auth/forgot-password', handle(async (req, res) => {
    const email = normalizeAccountEmail(req.body.email);
    if (!email) fail('invalid_email');
    service.ready();
    // Response does not depend on account existence or email-provider latency.
    setImmediate(() => service.requestReset(email).catch(() => console.warn('[account-mail] reset delivery unavailable')));
    res.status(202).json({requested: true});
  }));
  app.post('/api/auth/verify-email', handle(async (req, res) => res.json(await service.verify(req.body.token))));
  app.post('/api/auth/reset-password', handle(async (req, res) => res.json(await service.reset(req.body.token, req.body.password))));
}
