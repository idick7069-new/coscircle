import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
import {patchLegalServer, legalImport, legalMount, legalCheck} from './patch-legal-server.mjs';

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
const fixture = `import { createPool } from './db.js';
const untouched = 'existing product API';
${auth}app.get('/api/me', async (req, res, next) => {});
await ensureAuthIdentities(pool);
app.listen(port, () => {});
`;
const undo = source => source.replace(legalImport, '').replace(legalMount, '').replace(legalCheck, '');

test('standalone VM transform exactly matches the exported transform', () => {
  const deploy = readFileSync(new URL('./deploy-legal-on-vm.sh', import.meta.url), 'utf8');
  const embedded = deploy.split('// BEGIN standalone transform\n')[1].split('// END standalone transform')[0];
  const pure = readFileSync(new URL('./patch-legal-server.mjs', import.meta.url), 'utf8').replace(/^export /gm, '');
  assert.equal(embedded, pure);
});
test('only the three additive insertions change the source', () => {
  assert.equal(undo(patchLegalServer(fixture)), fixture);
});
test('runtime registration occurs after auth and before me; SELECT precedes auth tables and listen', async () => {
  const calls = [];
  const executable = patchLegalServer(fixture).replace("import { createPool } from './db.js';\n", '').replace(legalImport, '');
  await vm.runInNewContext(`(async () => {${executable}})()`, {
    app: {use: () => calls.push('auth'), get: () => calls.push('me'), listen: () => calls.push('listen')},
    pool: {execute: sql => {assert.match(sql, /^SELECT .* LIMIT 0$/); calls.push('select');}},
    createLegalService: pool => pool,
    registerLegalRoutes: () => calls.push('legal'),
    ensureAuthIdentities: () => calls.push('identities'),
    port: 8080,
  });
  assert.deepEqual(calls, ['auth', 'legal', 'me', 'select', 'identities', 'listen']);
});
for (const [name, anchor] of [
  ['import', "import { createPool } from './db.js';\n"],
  ['auth', auth], ['me', "app.get('/api/me', async (req, res, next) => {"],
  ['startup', 'await ensureAuthIdentities(pool);\n'], ['listen', 'app.listen(port, () => {'],
]) {
  test(`rejects missing ${name} anchor`, () => assert.throws(() => patchLegalServer(fixture.replace(anchor, ''))));
  test(`rejects ambiguous ${name} anchor`, () => assert.throws(() => patchLegalServer(fixture + anchor)));
}
test('rejects moved or weakened authentication boundary', () => {
  assert.throws(() => patchLegalServer(fixture.replace(auth, '').replace('app.listen', auth + 'app.listen')));
  assert.throws(() => patchLegalServer(fixture.replace('if (!req.userId)', 'if (false)')));
  assert.throws(() => patchLegalServer(fixture.replace(auth, auth + '// unexpected code\n')));
});
test('rejects moved startup, already patched source, and partial legal code', () => {
  assert.throws(() => patchLegalServer(fixture.replace('await ensureAuthIdentities(pool);\n', '') + 'await ensureAuthIdentities(pool);\n'));
  assert.throws(() => patchLegalServer(patchLegalServer(fixture)));
  assert.throws(() => patchLegalServer(fixture + "\n// registerLegalRoutes"));
});
test('rejects non-string input', () => assert.throws(() => patchLegalServer(null), TypeError));
test('captured production server round trips without unrelated changes', {skip: !process.env.PRODUCTION_SERVER_FIXTURE}, () => {
  const original = readFileSync(process.env.PRODUCTION_SERVER_FIXTURE, 'utf8');
  const patched = patchLegalServer(original);
  assert.equal(undo(patched), original);
  assert.ok(patched.indexOf(legalMount) > patched.indexOf(auth));
  assert.ok(patched.indexOf(legalCheck) < patched.indexOf('await ensureAuthIdentities(pool);'));
});
