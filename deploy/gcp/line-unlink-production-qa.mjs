import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {createPool} from '../src/db.js';
import {legacyIdentityBackfillSql} from '../src/auth-identities.js';
if(!process.argv.includes('--run-production-qa')) throw new Error('explicit_qa_flag_required');
const pool=createPool();const marker='qa-line-unlink-'+crypto.randomUUID();const users=[];let eventId,circleId;
async function seed(label,{email=true,legacy=false}={}) {
 const subject=marker+'-'+label;const token=crypto.randomBytes(32).toString('hex');const password=crypto.randomBytes(24).toString('hex');
 const salt=crypto.randomBytes(16).toString('hex');const hash=salt+':'+crypto.scryptSync(password,salt,64).toString('hex');
 const [result]=await pool.execute(`INSERT INTO users (provider,provider_user_id,public_code,nickname,bio,session_token,onboarding_completed)
 VALUES (?,?,?,?,?,?,TRUE)`,[legacy?'line':'email',legacy?subject:subject+'@example.invalid',subject,'QA unlink '+label,marker,token]);
 const user={id:result.insertId,subject,token,password};users.push(user);
 await pool.execute("INSERT INTO user_auth_identities (user_id,provider,provider_user_id) VALUES (?,'line',?)",[user.id,subject]);
 if(email) await pool.execute("INSERT INTO user_auth_identities (user_id,provider,provider_user_id,password_hash) VALUES (?,'email',?,?)",[user.id,subject+'@example.invalid',hash]);
 const legal=await api('/me/legal',user,undefined,200,'GET');await api('/me/legal',user,{accepted:true,version:legal.version},200,'POST');
 return user;
}
async function api(path,user,body,expected,method='DELETE') {
 const r=await fetch('http://127.0.0.1:8080/api'+path,{method,headers:{'Content-Type':'application/json','X-Forwarded-Proto':'https',...(user?{Authorization:'Bearer '+user.token}:{})},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(15000)});
 assert.equal(r.status,expected,method+' '+path+' status '+r.status);return r.json();
}
async function lineCount(user) {const [[row]]=await pool.execute("SELECT COUNT(*) AS n FROM user_auth_identities WHERE user_id=? AND provider='line'",[user.id]);return row.n;}
try {
 const email=await seed('email');const only=await seed('only',{email:false,legacy:true});const legacy=await seed('legacy',{legacy:true});
 const [event]=await pool.execute("INSERT INTO events (source_key,source_type,source_name,category,name,start_date,end_date,venue,status) VALUES (?,3,'QA','QA',?,UTC_DATE(),UTC_DATE(),'QA','pending')",[marker,marker]);eventId=event.insertId;
 await pool.execute("INSERT INTO event_bookings (event_id,user_id,day_index,role,character_name,message) VALUES (?,?,1,'coser','QA','QA')",[eventId,email.id]);
 await pool.execute('INSERT INTO follows (follower_user_id,followed_user_id) VALUES (?,?)',[email.id,only.id]);
 const [circle]=await pool.execute('INSERT INTO circles (owner_user_id,name,description,invite_code,invite_url) VALUES (?,?,?,?,?)',[email.id,marker,'QA',marker.slice(-32),'https://coscircle.app/app']);circleId=circle.insertId;
 await pool.execute('INSERT INTO circle_members (circle_id,user_id) VALUES (?,?)',[circleId,email.id]);
 await api('/me/auth-identities/line',null,{password:'wrong'},401);
 assert.equal((await api('/me/auth-identities/line',only,{password:only.password},409)).error,'email_login_required');assert.equal(await lineCount(only),1);
 for(const password of ['wrong','']) {assert.equal((await api('/me/auth-identities/line',email,{password},403)).error,'reauthentication_required');assert.equal(await lineCount(email),1);}
 for(const user of [email,legacy]) {
  const before=await api('/me',user,undefined,200,'GET');
  assert.equal((await api('/me/auth-identities/line',user,{password:user.password},200)).unlinked,true);assert.equal(await lineCount(user),0);
  const after=await api('/me',user,undefined,200,'GET');assert.equal(String(after.id),String(user.id));assert.equal(after.nickname,before.nickname);assert.equal(after.bio,before.bio);
  await pool.execute(legacyIdentityBackfillSql+' WHERE id=?',[user.id]);assert.equal(await lineCount(user),0);
  const login=await api('/auth/login',null,{email:user.subject+'@example.invalid',password:user.password},200,'POST');assert.equal(String(login.user.id),String(user.id));user.token=login.token;
 }
 const [[bookings]]=await pool.execute('SELECT COUNT(*) AS n FROM event_bookings WHERE user_id=? AND event_id=?',[email.id,eventId]);assert.equal(bookings.n,1);
 const [[follows]]=await pool.execute('SELECT COUNT(*) AS n FROM follows WHERE follower_user_id=? AND followed_user_id=?',[email.id,only.id]);assert.equal(follows.n,1);
 const [[members]]=await pool.execute('SELECT COUNT(*) AS n FROM circle_members WHERE circle_id=? AND user_id=?',[circleId,email.id]);assert.equal(members.n,1);
 console.log('PASS production: unlink requires authentication and correct Email password, blocks LINE-only account, preserves profile/session/bookings/follows/circle, Email login returns original user, legacy backfill cannot restore LINE');
} finally {
 if(circleId) await pool.execute('DELETE FROM circles WHERE id=? AND name=?',[circleId,marker]);
 if(eventId) await pool.execute('DELETE FROM events WHERE id=? AND source_key=?',[eventId,marker]);
 for(const user of users) {await pool.execute('DELETE FROM line_web_logins WHERE link_user_id=?',[user.id]);await pool.execute('DELETE FROM users WHERE id=? AND bio=?',[user.id,marker]);}
 const [[left]]=await pool.execute('SELECT COUNT(*) AS n FROM users WHERE bio=?',[marker]);assert.equal(left.n,0);
 console.log('PASS temporary QA accounts and related data cleaned');await pool.end();
}
