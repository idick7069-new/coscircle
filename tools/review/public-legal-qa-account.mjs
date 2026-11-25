import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import {createPool} from '/opt/coscircle/api/current/src/db.js';
const file='/etc/coscircle/public-legal-page-qa.json';
if(process.getuid?.()!==0) throw new Error('root_required');
const mode=process.argv[2];assert(['--create','--cleanup'].includes(mode));
const pool=createPool();
try {
 if(mode==='--create') {
  try {await fs.access(file);throw new Error('existing_qa_manifest_requires_cleanup');} catch(e) {if(e.code!=='ENOENT') throw e;}
  const a={namespace:'public-legal-page-qa',email:'legal-page-qa-'+crypto.randomUUID()+'@example.invalid',password:crypto.randomBytes(24).toString('base64url'),publicCode:crypto.randomBytes(12).toString('hex')};
  const salt=crypto.randomBytes(16).toString('hex');const hash=salt+':'+crypto.scryptSync(a.password,salt,64).toString('hex');
  await fs.writeFile(file,JSON.stringify(a)+'\n',{flag:'wx',mode:0o600});
  const db=await pool.getConnection();
  try {
   await db.beginTransaction();
   const [user]=await db.execute("INSERT INTO users (provider,provider_user_id,public_code,nickname) VALUES ('qa_public_legal',?,?,'Disposable Legal Page QA')",[a.email,a.publicCode]);a.id=String(user.insertId);
   await db.execute("INSERT INTO user_auth_identities (user_id,provider,provider_user_id,password_hash) VALUES (?,'email',?,?)",[a.id,a.email,hash]);
   await db.commit();await fs.writeFile(file,JSON.stringify(a)+'\n',{mode:0o600});
   console.log(JSON.stringify({created:true,userId:a.id,namespace:a.namespace}));
  } catch(e) {await db.rollback();throw e;} finally {db.release();}
 } else {
  const a=JSON.parse(await fs.readFile(file,'utf8'));assert.equal(a.namespace,'public-legal-page-qa');assert(a.email.endsWith('@example.invalid'));
  const [[row]]=await pool.execute("SELECT id FROM users WHERE provider='qa_public_legal' AND provider_user_id=? AND public_code=?",[a.email,a.publicCode]);
  if(row) await pool.execute("DELETE FROM users WHERE id=? AND provider='qa_public_legal' AND public_code=?",[row.id,a.publicCode]);
  const [[left]]=await pool.execute('SELECT COUNT(*) AS n FROM users WHERE public_code=?',[a.publicCode]);assert.equal(left.n,0);
  await fs.rm(file);console.log(JSON.stringify({cleaned:true,wasAlreadyDeleted:!row}));
 }
} finally {await pool.end();}
