import {inTransaction} from './db-transaction.js';

export const authIdentitiesTableSql = `CREATE TABLE IF NOT EXISTS user_auth_identities (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  provider VARCHAR(32) NOT NULL,
  provider_user_id VARCHAR(191) NOT NULL,
  password_hash TEXT NULL,
  verified_at DATETIME NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_auth_provider_subject (provider, provider_user_id),
  UNIQUE KEY uniq_auth_user_provider (user_id, provider),
  CONSTRAINT fk_auth_identity_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
)`;

export const legacyIdentityBackfillSql = `INSERT IGNORE INTO user_auth_identities
  (user_id, provider, provider_user_id, password_hash)
  SELECT id, provider, provider_user_id, CASE WHEN provider='email' THEN password_hash ELSE NULL END
  FROM users`;

export const authIdentityUserQuery = `SELECT users.id, identities.password_hash AS passwordHash,
  users.account_status AS accountStatus FROM users
  INNER JOIN user_auth_identities AS identities ON identities.user_id=users.id
  WHERE identities.provider=? AND identities.provider_user_id=? LIMIT 1`;

export async function ensureAuthIdentities(pool) {
  await pool.execute(authIdentitiesTableSql);
  // Legacy users keep their IDs, sessions and relationships; email is not marked verified.
  await pool.execute(legacyIdentityBackfillSql);
}

function fail(code, status) {
  throw Object.assign(new Error(code), {code, status});
}

export async function linkLineIdentity(pool, {userId, lineUserId, password, verifyPassword}) {
  try {
    return await inTransaction(pool, async (db) => {
      const [[user]] = await db.execute('SELECT id, account_status AS accountStatus FROM users WHERE id=? FOR UPDATE', [userId]);
      if (!user || user.accountStatus !== 'active') fail('account_suspended', 403);
      const [[email]] = await db.execute(`SELECT password_hash AS passwordHash FROM user_auth_identities
        WHERE user_id=? AND provider='email'`, [userId]);
      if (!email?.passwordHash || !await verifyPassword(password, email.passwordHash)) {
        fail('reauthentication_required', 401);
      }
      const [[existing]] = await db.execute(`SELECT user_id AS userId FROM user_auth_identities
        WHERE provider='line' AND provider_user_id=?`, [lineUserId]);
      if (existing && String(existing.userId) !== String(userId)) fail('line_identity_already_linked', 409);
      if (existing) return {linked: true};
      const [[own]] = await db.execute(`SELECT id FROM user_auth_identities WHERE user_id=? AND provider='line'`, [userId]);
      if (own) fail('line_identity_already_linked', 409);
      await db.execute(`INSERT INTO user_auth_identities (user_id,provider,provider_user_id,verified_at)
        VALUES (?,'line',?,UTC_TIMESTAMP())`, [userId, lineUserId]);
      return {linked: true};
    });
  } catch (error) {
    if (error.code === 'ER_DUP_ENTRY') fail('line_identity_already_linked', 409);
    throw error;
  }
}
