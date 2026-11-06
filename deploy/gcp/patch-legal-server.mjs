export const legalImport = "import { createLegalService, registerLegalRoutes } from './legal-consent.js';\n";
export const legalMount = 'registerLegalRoutes(app, createLegalService(pool));\n\n';
export const legalCheck = "await pool.execute('SELECT user_id, version, accepted_at FROM user_legal_consents LIMIT 0');\n";

const auth = `app.use(async (req, _res, next) => {
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

`;
const me = "app.get('/api/me', async (req, res, next) => {";
const importAnchor = "import { createPool } from './db.js';\n";
const startup = 'await ensureAuthIdentities(pool);\n';
const listen = 'app.listen(port, () => {';

export function patchLegalServer(source) {
  if (typeof source !== 'string') throw new TypeError('Expected server source string');
  if (/legal-consent|createLegalService|registerLegalRoutes|user_legal_consents/.test(source)) {
    throw new Error('Server already contains legal code');
  }
  for (const [name, anchor] of Object.entries({importAnchor, auth, me, startup, listen})) {
    if (source.split(anchor).length !== 2) throw new Error(`Missing or ambiguous ${name} anchor`);
  }
  if (!source.includes(auth + me) || source.indexOf(importAnchor) > source.indexOf(auth) ||
      source.indexOf(me) > source.indexOf(startup) || source.indexOf(startup) > source.indexOf(listen)) {
    throw new Error('Unexpected auth or startup boundary');
  }
  return source.replace(importAnchor, importAnchor + legalImport)
    .replace(auth + me, auth + legalMount + me)
    .replace(startup, legalCheck + startup);
}
