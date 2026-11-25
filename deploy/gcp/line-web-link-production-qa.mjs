import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {createPool} from '../src/db.js';
if (!process.argv.includes('--run-production-qa')) throw new Error('explicit_qa_flag_required');
const pool=createPool();
const marker='qa-line-link-'+crypto.randomUUID();
const token=crypto.randomBytes(32).toString('hex');
let userId;
async function api(path,{authenticated=true,origin='https://coscircle.app',cookie='',body={},method='POST'}={}) {
 return fetch('http://127.0.0.1:8080/api'+path,{method,redirect:'manual',headers:{'Content-Type':'application/json','X-Forwarded-Proto':'https',Origin:origin,Cookie:cookie,...(authenticated?{Authorization:'Bearer '+token}:{})},...(method==='POST'?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(15000)});
}
try {
 const [created]=await pool.execute("INSERT INTO users (provider,provider_user_id,public_code,nickname,session_token,onboarding_completed) VALUES ('qa_line_link',?,?,?, ?,TRUE)",[marker,marker,'QA Web LINE link',token]);
 userId=created.insertId;
 const salt=crypto.randomBytes(16).toString('hex');
 const passwordHash=salt+':'+crypto.scryptSync(crypto.randomBytes(32),salt,64).toString('hex');
 await pool.execute("INSERT INTO user_auth_identities (user_id,provider,provider_user_id,password_hash) VALUES (?,'email',?,?)",[userId,marker+'@example.invalid',passwordHash]);
 const legalResponse=await api('/me/legal',{method:'GET'});assert.equal(legalResponse.status,200);const legal=await legalResponse.json();
 assert.equal((await api('/me/legal',{body:{version:legal.version,accepted:true}})).status,200);
 for(const path of ['/me/auth-identities/line/web/start','/me/auth-identities/line/web/complete']) assert.equal((await api(path,{authenticated:false})).status,401);
 assert.equal((await api('/me/auth-identities/line/web/start',{origin:'https://foreign.invalid'})).status,403);
 const start=await api('/me/auth-identities/line/web/start');assert.equal(start.status,200);
 const cookie=start.headers.get('set-cookie').split(';')[0];const url=new URL((await start.json()).url);
 assert.equal(url.hostname,'access.line.me');assert.equal(url.searchParams.get('client_id'),'2012627208');
 assert.equal(url.searchParams.get('redirect_uri'),'https://coscircle.app/api/auth/line/web/callback');
 const [[attempt]]=await pool.execute('SELECT purpose,link_user_id,link_session_hash FROM line_web_logins WHERE link_user_id=?',[userId]);
 assert.equal(attempt.purpose,'link');assert.equal(String(attempt.link_user_id),String(userId));assert.equal(attempt.link_session_hash,crypto.createHash('sha256').update(token).digest('hex'));
 const callback=await api('/auth/line/web/callback?'+new URLSearchParams({state:url.searchParams.get('state'),error:'access_denied'}),{method:'GET',cookie});
 assert.equal(callback.status,303);assert(callback.headers.get('location').startsWith('https://coscircle.app/app/#/login-methods?line=failed'));
 const expired=await api('/me/auth-identities/line/web/complete',{body:{password:'unused'}});assert.equal(expired.status,410);assert.equal((await expired.json()).error,'line_login_expired');
 const me=await api('/me',{method:'GET'});assert.equal(me.status,200);assert.equal(String((await me.json()).id),String(userId));
 const [[identities]]=await pool.execute("SELECT COUNT(*) AS n FROM user_auth_identities WHERE user_id=? AND provider='line'",[userId]);assert.equal(identities.n,0);
 console.log('PASS production: authenticated Web link start, browser/session binding, cancellation redirect, anonymous/origin rejection, expired link preserves Email session; no LINE identity added');
} finally {
 if(userId) {
  await pool.execute('DELETE FROM line_web_logins WHERE link_user_id=?',[userId]);
  await pool.execute("DELETE FROM users WHERE id=? AND provider='qa_line_link' AND provider_user_id=?",[userId,marker]);
  const [[remaining]]=await pool.execute('SELECT COUNT(*) AS n FROM users WHERE id=?',[userId]);assert.equal(remaining.n,0);
  console.log('PASS temporary QA account and attempts cleaned');
 }
 await pool.end();
}
