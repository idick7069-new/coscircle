import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require=createRequire(process.cwd()+'/package.json');
const env=require('dotenv').parse(fs.readFileSync('/etc/coscircle/api.env'));
const mysql=require('mysql2/promise');
const db=await mysql.createConnection({host:env.MYSQL_HOST||'127.0.0.1',port:Number(env.MYSQL_PORT||3306),user:env.MYSQL_USER,password:env.MYSQL_PASSWORD,database:env.MYSQL_DATABASE||'coscircle'});
const [action,backup,base='http://127.0.0.1:18080']=process.argv.slice(2);
if(process.getuid()!==0||!/^\/var\/backups\/coscircle\/release-security-[A-Za-z0-9]+$/.test(backup||''))throw Error('Restricted backup required');
const statePath=backup+'/qa-state.json';
const state=fs.existsSync(statePath)?JSON.parse(fs.readFileSync(statePath)): {namespace:'release-security-20261124',accounts:[],bookings:[],uploads:[]};
const save=()=>fs.writeFileSync(statePath,JSON.stringify(state),{mode:0o600});
const headers={'Content-Type':'application/json','X-Forwarded-Proto':'https'};
async function call(path,{method='GET',body,token,cookie,web=false,expected=200}={}) {
 const response=await fetch(base+path,{method,headers:{...headers,...(token?{Authorization:'Bearer '+token}:{}),...(cookie?{Cookie:cookie}:{}),...(web?{Origin:'https://coscircle.app','X-CosCircle-Client':'web'}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 let data;const text=await response.text();try{data=JSON.parse(text);}catch{data=text;}
 assert.equal(response.status,expected,method+' '+path+' returned '+response.status+' '+(data?.error??''));
 return {response,data};
}
try {
 if(action==='prepare') {
  assert.equal(state.accounts.length,0,'Do not recreate QA accounts');
  for(const role of ['ordinary','review','reviewPeer']) {
   const email='release-security-'+role+'-'+crypto.randomUUID()+'@example.invalid',password=crypto.randomBytes(24).toString('base64url'),code=crypto.randomBytes(12).toString('hex');
   const salt=crypto.randomBytes(16).toString('hex'),hash=salt+':'+crypto.scryptSync(password,salt,64).toString('hex');
   const [row]=await db.execute(`INSERT INTO users(provider,provider_user_id,public_code,email,password_hash,nickname,bio,booking_visibility,onboarding_completed,is_test_account,can_view_test_data)
    VALUES('email',?,?,?,?,?,'','circle',TRUE,?,?)`,[email,code,email,hash,'[QA短暫驗證] '+role,role!=='ordinary',role!=='ordinary']);
   const id=String(row.insertId);await db.execute("INSERT INTO user_auth_identities(user_id,provider,provider_user_id,password_hash,verified_at)VALUES(?,'email',?,?,UTC_TIMESTAMP())",[id,email,hash]);
   state.accounts.push({id,email,password,publicCode:code,role});save();
  }
  const owner=state.accounts.find(a=>a.role==='review');
  const [event]=await db.execute(`INSERT INTO events(source_key,source_type,source_name,category,name,start_date,end_date,venue,status,is_test_event) VALUES(?,3,'CosCircle QA','安全驗證','[QA安全驗證] 隔離與圖片權限',CURRENT_DATE(),CURRENT_DATE(),'測試資料，無實際聚會','approved',TRUE)`,[state.namespace+'-'+crypto.randomUUID()]);
  state.eventId=String(event.insertId);
  const invite=crypto.randomBytes(12).toString('hex');
  const [circle]=await db.execute('INSERT INTO circles(owner_user_id,name,invite_code,invite_url,is_test_circle)VALUES(?,?,?,?,TRUE)',[owner.id,'[QA安全驗證] 私有圈',invite,'https://coscircle.app/app/#/join/'+invite]);
  state.circleId=String(circle.insertId);state.invite=invite;
  await db.execute('INSERT INTO circle_members(circle_id,user_id)VALUES(?,?)',[state.circleId,owner.id]);save();
  console.log('Created disposable QA actors with no discoverable ordinary profile, and review-only fixtures.');
 } else if(action==='verify') {
  const ordinary=state.accounts.find(a=>a.role==='ordinary'),review=state.accounts.find(a=>a.role==='review'),peer=state.accounts.find(a=>a.role==='reviewPeer');
  await db.execute('DELETE FROM user_legal_consents WHERE user_id=?',[ordinary.id]);
  await db.execute('DELETE FROM circle_members WHERE circle_id=? AND user_id=?',[state.circleId,peer.id]);
  for(const a of state.accounts) {
   const {data}=await call('/api/auth/login',{method:'POST',body:{email:a.email,password:a.password}});a.token=data.token;assert.match(a.token,/^[a-f0-9]{64}$/);
  }save();
  const [[stored]]=await db.execute('SELECT session_token,session_expires_at FROM users WHERE id=?',[ordinary.id]);assert.notEqual(stored.session_token,ordinary.token);assert(stored.session_token.startsWith('sha256:'));assert(stored.session_expires_at);
  await call('/api/me',{token:stored.session_token,expected:401});
  const denied=await call('/api/works',{method:'POST',body:{name:'Must not be inserted'},token:ordinary.token,expected:403});assert.equal(denied.data.error,'legal_acceptance_required');
  for(const a of state.accounts)await call('/api/me/legal',{method:'POST',body:{version:'2026-10-28',accepted:true},token:a.token});
  const normalEvents=(await call('/api/events',{token:ordinary.token})).data;
  assert(!normalEvents.some(e=>[617,627,631,Number(state.eventId)].includes(Number(e.id))));
  const reviewEvents=(await call('/api/events',{token:review.token})).data;for(const id of [617,627,631,Number(state.eventId)])assert(reviewEvents.some(e=>Number(e.id)===id));
  await call('/api/events/'+state.eventId+'/participants',{token:ordinary.token,expected:404});
  await call('/api/circles/join',{method:'POST',body:{invite:state.invite},token:ordinary.token,expected:404});
  await call('/api/admin/stats',{token:ordinary.token,expected:403});
  const [[fixture]]=await db.execute('SELECT public_code FROM users WHERE id=7');
  await call('/api/profiles/'+fixture.public_code,{expected:404});await call('/api/profiles/'+fixture.public_code,{token:ordinary.token,expected:404});await call('/api/profiles/'+fixture.public_code,{token:review.token});
  await call('/api/auth/social',{method:'POST',body:{provider:'facebook',accessToken:'deliberately-invalid-fixture'},expected:400});
  // Upload only synthetic, non-personal pixels. The original owner remains authoritative.
  let image=state.image;
  if(!image){const {data}=await call('/api/uploads/image',{method:'POST',token:review.token,body:{mimeType:'image/png',bytesBase64:'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jlp0AAAAASUVORK5CYII='},expected:201});image=data.url.split('?')[0];state.image=image;state.uploads.push(image.split('/').pop());save();}
  await db.execute(`INSERT INTO event_bookings(event_id,user_id,day_index,role,outfit_image_url)VALUES(?,?,1,'coser',?) ON DUPLICATE KEY UPDATE outfit_image_url=VALUES(outfit_image_url)`,[state.eventId,review.id,image]);
  await call('/api/media/sign',{method:'POST',body:{url:image},token:ordinary.token,expected:404});await call('/api/media/sign',{method:'POST',body:{url:image},token:peer.token,expected:404});
  await db.execute('INSERT IGNORE INTO circle_members(circle_id,user_id)VALUES(?,?)',[state.circleId,peer.id]);
  const signed=(await call('/api/media/sign',{method:'POST',body:{url:image},token:peer.token})).data.url;
  const u=new URL(signed);const file=await fetch(base+u.pathname+u.search,{headers:{'X-Forwarded-Proto':'https'}});assert.equal(file.status,200);assert.match(file.headers.get('cache-control'),/no-store/);await file.arrayBuffer();
  const raw=await fetch(base+u.pathname,{headers:{'X-Forwarded-Proto':'https'}});assert.equal(raw.status,404);
  await db.execute('INSERT IGNORE INTO user_blocks(blocker_user_id,blocked_user_id)VALUES(?,?)',[review.id,peer.id]);
  const blocked=await fetch(base+u.pathname+u.search,{headers:{'X-Forwarded-Proto':'https'}});assert.equal(blocked.status,404);
  await db.execute('DELETE FROM user_blocks WHERE blocker_user_id=? AND blocked_user_id=?',[review.id,peer.id]);
  const browser=await call('/api/auth/login',{method:'POST',body:{email:ordinary.email,password:ordinary.password},web:true});assert.equal(browser.data.token,'cookie-session');const setCookie=browser.response.headers.get('set-cookie');assert.match(setCookie,/HttpOnly/);assert.match(setCookie,/Secure/);const cookie=setCookie.split(';')[0];
  await call('/api/me',{cookie});
  await call('/api/auth/logout',{method:'POST',body:{},cookie,web:true,expected:204});await call('/api/me',{cookie,expected:401});
  const existing=JSON.parse(fs.readFileSync('/etc/coscircle/google-play-review-accounts.json'));
  for(const a of existing.accounts.filter(a=>['main','backup'].includes(a.key))){const [[u]]=await db.execute("SELECT i.password_hash,u.can_view_test_data FROM user_auth_identities i JOIN users u ON u.id=i.user_id WHERE i.user_id=? AND i.provider='email'",[a.id]);const [salt,hash]=u.password_hash.split(':');assert.equal(crypto.scryptSync(a.password,salt,64).toString('hex'),hash);assert.equal(u.can_view_test_data,1);}
  const report={phase:'verified',testEventsHiddenFromOrdinary:true,reviewEventsPreserved:true,reviewPasswordsUnchanged:true,adminGuard:true,facebookDisabled:true,consentEnforced:true,privateMediaAndBlocking:true,sessionDigestAndExpiry:true,digestCannotAuthenticate:true,httpOnlyCookieAndLogout:true};fs.writeFileSync(backup+'/qa-results.json',JSON.stringify(report,null,2),{mode:0o600});console.log(JSON.stringify(report));
 } else if(action==='cleanup') {
  for(const a of state.accounts){const [[u]]=await db.execute('SELECT provider_user_id FROM users WHERE id=?',[a.id]);assert(!u||u.provider_user_id===a.email);}
  if(state.eventId)await db.execute('DELETE FROM events WHERE id=? AND is_test_event=TRUE',[state.eventId]);
  if(state.circleId)await db.execute('DELETE FROM circles WHERE id=? AND is_test_circle=TRUE',[state.circleId]);
  for(const a of state.accounts)await db.execute('DELETE FROM users WHERE id=? AND provider_user_id=?',[a.id,a.email]);
  for(const name of state.uploads){if(!/^[a-f0-9-]+\.png$/.test(name))throw Error('Unexpected upload name');await db.execute('DELETE FROM account_uploads WHERE file_name=? AND user_id IS NULL',[name]);try{fs.unlinkSync('/var/lib/coscircle/uploads/'+name);}catch(error){if(error.code!=='ENOENT')throw error;}}
  state.cleaned=true;save();console.log('Removed only this run’s disposable QA data; original review fixtures retained.');
 } else throw Error('Unknown QA action');
} finally{await db.end();}
