#!/usr/bin/env python3
"""Overlay Apple auth only onto a verified production source snapshot."""
from pathlib import Path
import shutil, hashlib, tarfile
root=Path(__file__).resolve().parents[2];baseline=root/'build/private/ios/production-baseline';out=root/'build/private/ios/apple-payload';out.mkdir(exist_ok=True)
s=(baseline/'src/server.js').read_text()
def replace(old,new):
 global s
 assert s.count(old)==1,old[:100]
 s=s.replace(old,new,1)
s="import {createAppleAuth, registerAppleRoutes, appleAuthTables} from './apple-auth.js';\n"+s
replace('const pool = createPool();',"""const pool = createPool();
const appleAuth = createAppleAuth(pool, {verifyPassword,
  authenticateApple: (profile, saveIdentity) => authenticateSocialProfile('apple', profile, {saveIdentity}),
});""")
replace('  verifyPassword, fetchLineProfile, uploadDir,',"""  verifyPassword, fetchLineProfile, uploadDir,
  fetchAppleProfile: (body, context) => appleAuth.credential(body, context),
  revokeAppleIdentity: (db, id) => appleAuth.revoke(db, id),""")
replace("app.use('/api/auth', createRateLimiter({ windowMs: 15 * 60 * 1000, max: 30 }));","app.use('/api/auth', createRateLimiter({ windowMs: 15 * 60 * 1000, max: 30 }));\nregisterAppleRoutes(app, appleAuth, {production: isProduction});")
replace("async function authenticateSocialProfile(provider, socialProfile) {","async function authenticateSocialProfile(provider, socialProfile, {saveIdentity = async () => {}} = {}) {")
replace("    return {token: sessionToken, user: await fetchUserProfile(userId), isNewUser};", "    return {token: sessionToken, user: await fetchUserProfile(userId), isNewUser};")
anchor="    });\n    return {token: sessionToken, user: await fetchUserProfile(userId), isNewUser};"
replace(anchor,"      await saveIdentity(db, userId);\n"+anchor)
replace('registerLegalRoutes(app, createLegalService(pool));',"""registerLegalRoutes(app, createLegalService(pool));
app.use('/api/me/auth-identities/apple', createRateLimiter({windowMs: 15 * 60 * 1000, max: 30}));
registerAppleRoutes(app, appleAuth, {privateRoutes: true, production: isProduction});""")
replace('await ensureAuthIdentities(pool);','await ensureAuthIdentities(pool);\nif (appleAuth.enabled) { for (const sql of appleAuthTables) await pool.execute(sql); }')
(out/'server.js').write_text(s)
for f in ['account-deletion.js','apple-auth.js','apple-auth.test.js','account-deletion.test.js','auth-identity-unlink.test.js']:
 shutil.copyfile(root/'backend/src'/f,out/f)
shutil.copyfile(root/'backend/db/migrate_apple_login.sql',out/'migrate_apple_login.sql')
expected={f:hashlib.sha256((baseline/'src'/f).read_bytes()).hexdigest() for f in ['server.js','account-deletion.js','auth-identities.js']}
import json
(out/'baseline-hashes.json').write_text(json.dumps(expected))
archive=root/'build/private/ios/apple-api.tar.gz'
with tarfile.open(archive,'w:gz') as t:
 for f in out.iterdir():t.add(f,arcname=f.name)
print('Prepared isolated Apple API payload against current production baseline.')
