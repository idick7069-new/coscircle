export const LEGAL_VERSION = '2026-10-28';

export const legalConsentTableSql = `CREATE TABLE IF NOT EXISTS user_legal_consents (
  user_id BIGINT UNSIGNED NOT NULL,
  version VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  accepted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, version),
  CONSTRAINT fk_legal_consent_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
)`;

function fail(code, status) {
  throw Object.assign(new Error(code), {code, status});
}

function checkSession(userId, token) {
  const validId = typeof userId === 'number'
    ? Number.isSafeInteger(userId) && userId > 0
    : typeof userId === 'string' && /^[1-9][0-9]{0,19}$/.test(userId);
  if (!validId || typeof token !== 'string' || !token || token.length > 191) {
    fail('authentication_required', 401);
  }
}

export function createLegalService(pool) {
  async function status(userId, token) {
    checkSession(userId, token);
    const [[row]] = await pool.execute(
      `SELECT consent.version AS acceptedVersion FROM users AS account
       LEFT JOIN user_legal_consents AS consent
         ON consent.user_id = account.id AND consent.version = ?
       WHERE account.id = ? AND account.session_token = ? AND account.account_status = 'active'
       LIMIT 1`,
      [LEGAL_VERSION, userId, token],
    );
    if (!row) fail('authentication_required', 401);
    return {version: LEGAL_VERSION, accepted: row.acceptedVersion === LEGAL_VERSION};
  }

  async function accept(userId, body, token) {
    checkSession(userId, token);
    if (!body || typeof body !== 'object' || Array.isArray(body) || body.accepted !== true ||
        typeof body.version !== 'string') {
      fail('invalid_legal_acceptance', 400);
    }
    if (body.version !== LEGAL_VERSION) fail('legal_version_mismatch', 409);
    await pool.execute(
      `INSERT INTO user_legal_consents (user_id, version)
       SELECT id, ? FROM users
       WHERE id = ? AND session_token = ? AND account_status = 'active'
       ON DUPLICATE KEY UPDATE user_id = user_legal_consents.user_id`,
      [LEGAL_VERSION, userId, token],
    );
    return status(userId, token);
  }

  return {status, accept};
}

function bearerToken(req) {
  const header = req.get('authorization');
  if (typeof header !== 'string') return '';
  return /^Bearer ([^\s]+)$/i.exec(header)?.[1] ?? '';
}

function handleFailure(error, res, next) {
  if (['authentication_required', 'invalid_legal_acceptance', 'legal_version_mismatch'].includes(error.code)) {
    return res.status(error.status).json({error: error.code, version: LEGAL_VERSION});
  }
  return next(error);
}

export function registerLegalRoutes(app, service) {
  app.get('/api/me/legal', async (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    try {
      res.json(await service.status(req.userId, bearerToken(req)));
    } catch (error) { handleFailure(error, res, next); }
  });
  app.post('/api/me/legal', async (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    try {
      res.json(await service.accept(req.userId, req.body, bearerToken(req)));
    } catch (error) { handleFailure(error, res, next); }
  });
}

export function requireLegalAcceptance(service) {
  return async (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    try {
      const legal = await service.status(req.userId, bearerToken(req));
      if (!legal.accepted) {
        return res.status(403).json({error: 'legal_acceptance_required', version: LEGAL_VERSION});
      }
      next();
    } catch (error) { handleFailure(error, res, next); }
  };
}
