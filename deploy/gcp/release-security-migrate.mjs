import fs from 'node:fs';
import crypto from 'node:crypto';
import {createRequire} from 'node:module';
const require=createRequire(process.cwd()+'/package.json');
const env=require('dotenv').parse(fs.readFileSync('/etc/coscircle/api.env'));
const mysql=require('mysql2/promise');
const db=await mysql.createConnection({host:env.MYSQL_HOST||'127.0.0.1',port:Number(env.MYSQL_PORT||3306),user:env.MYSQL_USER,password:env.MYSQL_PASSWORD,database:env.MYSQL_DATABASE||'coscircle'});
const [action,backup]=process.argv.slice(2);
if(process.getuid()!==0||!/^\/var\/backups\/coscircle\/release-security-[A-Za-z0-9]+$/.test(backup||''))throw Error('Restricted backup required');
const snapshots=backup+'/sessions-before.json';
try {
 if(action==='prepare') {
  const fixtureIds=[7,8,9,10,11,12,13,14,15,16,17,18,28,29,30,31,33];
  const [users]=await db.query('SELECT id,nickname,is_admin,session_token FROM users');
  for(const id of fixtureIds){const u=users.find(u=>String(u.id)===String(id));if(!u||u.is_admin||!/測試|QA|審查|示範|CosTester/.test(u.nickname))throw Error('Fixture manifest mismatch for '+id);}
  const review=JSON.parse(fs.readFileSync('/etc/coscircle/google-play-review-accounts.json'));
  for(const key of ['main','backup']){const a=review.accounts.find(a=>a.key===key);const [[u]]=await db.execute("SELECT id FROM user_auth_identities WHERE user_id=? AND provider='email' AND provider_user_id=?",[a.id,a.email]);if(!u)throw Error('Review identity mismatch');}
  if(!fs.existsSync(snapshots))fs.writeFileSync(snapshots,JSON.stringify(users.map(u=>({id:u.id,sessionToken:u.session_token}))),{mode:0o600,flag:'wx'});
  const changes={users:[['is_test_account','BOOLEAN NOT NULL DEFAULT FALSE'],['can_view_test_data','BOOLEAN NOT NULL DEFAULT FALSE'],['session_expires_at','DATETIME NULL']],events:[['is_test_event','BOOLEAN NOT NULL DEFAULT FALSE']],circles:[['is_test_circle','BOOLEAN NOT NULL DEFAULT FALSE']],works:[['is_test_work','BOOLEAN NOT NULL DEFAULT FALSE']]};
  for(const [table,columns] of Object.entries(changes))for(const [column,definition]of columns){const [[exists]]=await db.execute('SELECT COUNT(*) AS n FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?',[table,column]);if(!exists.n)await db.query(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);}
  await db.beginTransaction();
  await db.query('UPDATE users SET is_test_account=TRUE WHERE id IN (?)',[fixtureIds]);
  await db.query('UPDATE users SET can_view_test_data=TRUE WHERE id IN (28,29)');
  await db.query("UPDATE events SET is_test_event=TRUE WHERE id IN (617,627,631) AND name REGEXP '測試|QA|審查'");
  await db.query("UPDATE circles SET is_test_circle=TRUE WHERE id IN (1,2,5) AND name REGEXP '測試|QA|審查|GooglePlayDemo'");
  await db.query("UPDATE works SET is_test_work=TRUE WHERE id IN (4,5) AND name REGEXP '測試'");
  // Canonicalize only the service's former public upload origins, preserving filenames and ownership.
  for(const [table,column]of [['users','avatar_url'],['users','other_photo_urls_json'],['event_bookings','outfit_image_url'],['events','image_url']]) {
   await db.query(`UPDATE ${table} SET ${column}=REPLACE(REPLACE(REPLACE(${column},'http://34.187.168.222/uploads/','https://coscircle.app/uploads/'),'https://34.187.168.222/uploads/','https://coscircle.app/uploads/'),'http://coscircle.app/uploads/','https://coscircle.app/uploads/') WHERE ${column} LIKE '%/uploads/%'`);
  }
  await db.commit();
  console.log('Prepared explicit fixture isolation; review credentials and existing sessions unchanged.');
 } else if(action==='activate') {
  await db.query("UPDATE users SET session_token=CONCAT('sha256:',SHA2(session_token,256)),session_expires_at=DATE_ADD(UTC_TIMESTAMP(),INTERVAL 30 DAY) WHERE session_token IS NOT NULL AND session_token NOT LIKE 'sha256:%'");
  const [[row]]=await db.query("SELECT COUNT(*) AS raw FROM users WHERE session_token IS NOT NULL AND session_token NOT LIKE 'sha256:%'");if(row.raw)throw Error('Raw session remains');
  console.log('Activated session digests and absolute expiration.');
 } else if(action==='rollback-sessions') {
  const before=JSON.parse(fs.readFileSync(snapshots));
  for(const u of before){if(!u.sessionToken||u.sessionToken.startsWith('sha256:'))continue;const digest='sha256:'+crypto.createHash('sha256').update(u.sessionToken).digest('hex');await db.execute('UPDATE users SET session_token=?,session_expires_at=NULL WHERE id=? AND session_token=?',[u.sessionToken,u.id,digest]);}
  console.log('Restored only unchanged pre-deployment sessions; concurrent logins/logout are not overwritten.');
 } else throw Error('Unknown migration action');
} finally {await db.end();}
