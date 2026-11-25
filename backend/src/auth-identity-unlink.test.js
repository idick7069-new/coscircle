import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {unlinkLineIdentity,legacyIdentityBackfillSql,authIdentityUserQuery} from './auth-identities.js';
function fixture({email=true,passwordHash='hash',active=true,legacyLine=false,failCleanup=false}={}) {
 const db=new DatabaseSync(':memory:');
 db.exec(`CREATE TABLE users (id INTEGER PRIMARY KEY,provider TEXT,provider_user_id TEXT,password_hash TEXT,account_status TEXT,session_token TEXT,nickname TEXT,bio TEXT);
 CREATE TABLE user_auth_identities (id INTEGER PRIMARY KEY,user_id INTEGER,provider TEXT,provider_user_id TEXT,password_hash TEXT,UNIQUE(provider,provider_user_id),UNIQUE(user_id,provider));
 CREATE TABLE line_web_logins (link_user_id INTEGER,purpose TEXT);
 CREATE TABLE relationships (user_id INTEGER,data TEXT);`);
 db.prepare('INSERT INTO users VALUES (5,?,?,?,?,?,?,?)').run(legacyLine?'line':'email',legacyLine?'LINE-5':'me@example.invalid',legacyLine?null:'hash',active?'active':'suspended','existing-session','CN','bio');
 db.exec("INSERT INTO user_auth_identities VALUES (1,5,'line','LINE-5',NULL),(2,9,'line','LINE-9',NULL); INSERT INTO line_web_logins VALUES (5,'link'),(9,'link'); INSERT INTO relationships VALUES (5,'friends/bookings/circles');");
 if(email) db.prepare("INSERT INTO user_auth_identities VALUES (3,5,'email','me@example.invalid',?)").run(passwordHash);
 db.exec('ALTER TABLE users ADD COLUMN is_admin INTEGER DEFAULT 0; ALTER TABLE users ADD COLUMN is_test_account INTEGER DEFAULT 0; ALTER TABLE users ADD COLUMN can_view_test_data INTEGER DEFAULT 0;');
 const connection={
  beginTransaction:async()=>db.exec('BEGIN'),commit:async()=>db.exec('COMMIT'),rollback:async()=>db.exec('ROLLBACK'),release:()=>{},
  execute:async(sql,params=[])=>{
   if(failCleanup&&sql.startsWith('DELETE FROM line_web_logins')) throw new Error('cleanup_failed');
   const stmt=db.prepare(sql.replace(/ FOR UPDATE/g,''));
   return stmt.columns().length?[stmt.all(...params)]:[{affectedRows:Number(stmt.run(...params).changes)}];
  }};
 return {db,pool:{getConnection:async()=>connection},options:{userId:5,password:'correct-password',verifyPassword:async(p,h)=>p==='correct-password'&&h==='hash'}};
}
test('unlink preserves Email login, session, profile, relationships and other users',async()=>{
 const f=fixture();const before=f.db.prepare('SELECT * FROM users WHERE id=5').get();
 assert.deepEqual(await unlinkLineIdentity(f.pool,f.options),{unlinked:true});
 assert.equal(f.db.prepare(authIdentityUserQuery).get('email','me@example.invalid').id,5);
 assert.equal(f.db.prepare(authIdentityUserQuery).get('line','LINE-5'),undefined);
 assert.deepEqual(f.db.prepare('SELECT * FROM users WHERE id=5').get(),before);
 assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM relationships WHERE user_id=5').get().n,1);
 assert.equal(f.db.prepare("SELECT COUNT(*) AS n FROM line_web_logins WHERE link_user_id=5").get().n,0);
 assert.equal(f.db.prepare("SELECT COUNT(*) AS n FROM line_web_logins WHERE link_user_id=9").get().n,1);
 assert.equal(f.db.prepare("SELECT provider_user_id FROM user_auth_identities WHERE user_id=9").get().provider_user_id,'LINE-9');
 await unlinkLineIdentity(f.pool,f.options);
});
test('LINE-only accounts and Email identities without passwords cannot lose LINE',async()=>{
 for(const config of [{email:false},{passwordHash:null},{passwordHash:''}]) {
  const f=fixture(config);
  await assert.rejects(unlinkLineIdentity(f.pool,f.options),{code:'email_login_required',status:409});
  assert.equal(f.db.prepare("SELECT COUNT(*) AS n FROM user_auth_identities WHERE user_id=5 AND provider='line'").get().n,1);
 }
});
test('wrong, missing and oversized passwords preserve all identities',async()=>{
 for(const password of ['wrong','',undefined,'x'.repeat(1025)]) {
  const f=fixture();await assert.rejects(unlinkLineIdentity(f.pool,{...f.options,password}),{code:'reauthentication_required',status:403});
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM user_auth_identities WHERE user_id=5').get().n,2);
 }
});
test('suspended and missing accounts cannot unlink',async()=>{
 const f=fixture({active:false});await assert.rejects(unlinkLineIdentity(f.pool,f.options),{code:'account_suspended',status:403});
 await assert.rejects(unlinkLineIdentity(f.pool,{...f.options,userId:123}),{code:'account_suspended',status:403});
});
test('legacy LINE primary identity moves to Email, so a restart cannot restore LINE',async()=>{
 const f=fixture({legacyLine:true});await unlinkLineIdentity(f.pool,f.options);
 const user=f.db.prepare('SELECT * FROM users WHERE id=5').get();assert.equal(user.provider,'email');assert.equal(user.provider_user_id,'me@example.invalid');assert.equal(user.session_token,'existing-session');
 f.db.exec(legacyIdentityBackfillSql.replace('INSERT IGNORE','INSERT OR IGNORE'));
 assert.equal(f.db.prepare(authIdentityUserQuery).get('line','LINE-5'),undefined);
 assert.equal(f.db.prepare(authIdentityUserQuery).get('email','me@example.invalid').id,5);
});
test('failed pending-link cleanup rolls back identity removal and legacy updates',async()=>{
 const f=fixture({legacyLine:true,failCleanup:true});await assert.rejects(unlinkLineIdentity(f.pool,f.options),/cleanup_failed/);
 assert.equal(f.db.prepare('SELECT provider FROM users WHERE id=5').get().provider,'line');
 assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM user_auth_identities WHERE user_id=5').get().n,2);
});
