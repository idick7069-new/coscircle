// Run on the production VM with its protected API env file. Never commit credentials.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';

async function main() {

if(!process.argv.includes('--prepare')) throw new Error('Pass --prepare explicitly');
if(process.getuid?.()!==0) throw new Error('Root is required for protected review credentials');
if(!/^coscircle-free-vm(?:\.|$)/.test(os.hostname())) throw new Error('Production VM required');
const {createPool}=await import('/opt/coscircle/api/current/src/db.js');
const {LEGAL_VERSION}=await import('/opt/coscircle/api/current/src/legal-consent.js');
const credentialPath='/etc/coscircle/apple-review-accounts.json';
const namespace='coscircle-apple-review-v1';
const asset='https://coscircle.app/app/assets/assets/mimi/cute-v1/';
let state;
try {state=JSON.parse(await fs.readFile(credentialPath,'utf8'));}
catch(error) {if(error.code!=='ENOENT') throw error;}
if(!state) {
 state={namespace,createdAt:new Date().toISOString(),inviteCode:crypto.randomBytes(12).toString('hex'),accounts:[
  {key:'main',email:'apple-review@coscircle.app',nickname:'Apple TestFlight Reviewer（審查測試）',role:'coser'},
  {key:'backup',email:'apple-review-backup@coscircle.app',nickname:'Apple TestFlight Backup（審查測試）',role:'photographer'},
  {key:'coser',email:'apple-review-demo-coser@coscircle.app',nickname:'[審查示範] 希希 Coser',role:'coser'},
  {key:'photographer',email:'apple-review-demo-photo@coscircle.app',nickname:'[審查示範] 小圈攝影',role:'photographer'},
 ].map(a=>({...a,password:crypto.randomBytes(24).toString('base64url'),publicCode:crypto.randomBytes(12).toString('hex')}))};
 await fs.writeFile(credentialPath,JSON.stringify(state,null,2)+'\n',{mode:0o600,flag:'wx'});
}
assert.equal(state.namespace,namespace);assert.equal(state.accounts.length,4);
await fs.chmod(credentialPath,0o600);
async function saveState() {
 const temp=credentialPath+'.next';await fs.writeFile(temp,JSON.stringify(state,null,2)+'\n',{mode:0o600});await fs.rename(temp,credentialPath);
}
const pool=createPool();let db;
try {
 db=await pool.getConnection();
 const [originalGoogleReview]=await db.execute("SELECT id,password_hash,session_token,can_view_test_data FROM users WHERE id IN (28,29) ORDER BY id");
 await db.beginTransaction();
 const [[dates]]=await db.execute("SELECT DATE_FORMAT(DATE(CONVERT_TZ(UTC_TIMESTAMP(),'+00:00','+08:00')),'%Y-%m-%d') AS today");
 for(const a of state.accounts) {
  const [[existing]]=await db.execute("SELECT id,public_code AS publicCode,is_admin AS isAdmin,is_test_account AS isTest,can_view_test_data AS canView FROM users WHERE provider='email' AND provider_user_id=? FOR UPDATE",[a.email]);
  if(existing) {assert.equal(existing.publicCode,a.publicCode,'Refusing to alter a non-review account');assert.equal(Number(existing.isAdmin),0);assert.equal(Number(existing.isTest),1);assert.equal(Boolean(existing.canView),['main','backup'].includes(a.key));a.id=String(existing.id);continue;}
  const salt=crypto.randomBytes(16).toString('hex');const hash=salt+':'+crypto.scryptSync(a.password,salt,64).toString('hex');
  const [created]=await db.execute(`INSERT INTO users
   (provider,provider_user_id,public_code,email,password_hash,nickname,avatar_url,bio,age,age_public,
    regions_json,travel_regions_json,travel_same_region,landmine,gender,profile_roles_json,other_photo_urls_json,
    booking_visibility,onboarding_completed,is_admin,is_test_account,can_view_test_data)
   VALUES ('email',?,?,?,?,?,?,?,'20',FALSE,?,?,TRUE,?,'private',?,?,'circle',TRUE,FALSE,TRUE,?)`,
   [a.email,a.publicCode,a.email,hash,a.nickname,asset+'portrait.png',
    'Apple TestFlight review demo account / 審查示範資料，非真實使用者。Enjoys cosplay events, shared works and photography.',
    JSON.stringify(['北部']),JSON.stringify(['北部']),'Demo only; please respect personal boundaries.',JSON.stringify([a.role]),JSON.stringify([asset+'reading-still.png']),['main','backup'].includes(a.key)]);
  a.id=String(created.insertId);
  await db.execute("INSERT INTO user_auth_identities (user_id,provider,provider_user_id,password_hash) VALUES (?,'email',?,?)",[a.id,a.email,hash]);
  await db.execute('INSERT INTO user_legal_consents (user_id,version) VALUES (?,?)',[a.id,LEGAL_VERSION]);
 }
 let [works]=await db.execute("SELECT id,name FROM works WHERE name<>'' ORDER BY id LIMIT 3");
 for(let i=works.length;i<3;i++) {
  const name='[Review Demo] Work '+String.fromCharCode(65+i);const [w]=await db.execute('INSERT INTO works (name) VALUES (?)',[name]);works.push({id:w.insertId,name});
 }
 state.works=works.map(w=>({id:String(w.id),name:w.name}));
 for(const a of state.accounts) for(const w of works.slice(0,a.key==='photographer'?1:2)) await db.execute("INSERT IGNORE INTO user_pit_works (user_id,work_id,depth) VALUES (?,?,'deep')",[a.id,w.id]);
 const [[event]]=await db.execute("SELECT id,DATE_FORMAT(start_date,'%Y-%m-%d') AS startDate,DATE_FORMAT(end_date,'%Y-%m-%d') AS endDate FROM events WHERE source_key=? FOR UPDATE",[namespace]);
 if(event) state.event={id:String(event.id),startDate:event.startDate,endDate:event.endDate};
 else {
  const startDate=dates.today;const endDate=new Date(Date.parse(startDate+'T00:00:00Z')+29*86400000).toISOString().slice(0,10);
  const [e]=await db.execute(`INSERT INTO events (source_key,source_type,source_name,category,name,start_date,end_date,venue,detailed_address,fee,organizer,description,status,is_test_event)
   VALUES (?,3,'CosCircle Review Demo','審查測試','[審查示範] Apple TestFlight Demo — 非真實活動',?,?,?,'Taipei map reference only','Free / 示範資料','CosCircle Review Demo',?,'approved',TRUE)`,
   [namespace,startDate,endDate,'Review demo only / 非真實活動・請勿前往現場',
    'Apple TestFlight review fixture only. This is not a real convention, booking or physical gathering. All demo bookings are circle-only. 審查示意活動，不對外招募，不代表真實活動。']);
  state.event={id:String(e.insertId),startDate,endDate};
 }
 const [[circle]]=await db.execute('SELECT id,owner_user_id AS ownerId FROM circles WHERE invite_code=? FOR UPDATE',[state.inviteCode]);
 const main=state.accounts.find(a=>a.key==='main');const backup=state.accounts.find(a=>a.key==='backup');const coser=state.accounts.find(a=>a.key==='coser');const photo=state.accounts.find(a=>a.key==='photographer');
 if(circle) {assert(state.accounts.some(a=>a.id===String(circle.ownerId)));state.circleId=String(circle.id);}
 else {const [c]=await db.execute('INSERT INTO circles (owner_user_id,name,description,invite_code,invite_url,is_test_circle) VALUES (?,?,?,?,?,TRUE)',
  [main.id,'[審查示範] Apple TestFlight Demo Circle','Review fixtures only; all members are demo accounts.',state.inviteCode,'https://coscircle.app/app/#/join/'+state.inviteCode]);state.circleId=String(c.insertId);}
 for(const a of state.accounts) await db.execute('INSERT IGNORE INTO circle_members (circle_id,user_id) VALUES (?,?)',[state.circleId,a.id]);
 const dayCount=Math.round((Date.parse(state.event.endDate)-Date.parse(state.event.startDate))/86400000)+1;assert(dayCount>=1&&dayCount<=31);
 for(let day=1;day<=dayCount;day++) {
  for(const a of state.accounts) await db.execute(`INSERT IGNORE INTO event_bookings
   (event_id,user_id,day_index,role,work_id,character_name,outfit_image_url,interaction_tags,available_time,presence_status,message)
   VALUES (?,?,?,?,?,?,?,?,?,'open',?)`,[state.event.id,a.id,day,a.role,works[0].id,a.role==='coser'?'Review demo character / 示範角色':'Review demo photographer',
   asset+'portrait.png',JSON.stringify(['歡迎認親','可合照']),'11:00–16:00','Review demo booking only / 審查示範，非真實出席']);
  const date=new Date(Date.parse(state.event.startDate+'T00:00:00Z')+(day-1)*86400000).toISOString().slice(0,10);
  const [[meetup]]=await db.execute('SELECT id FROM event_meeting_points WHERE event_id=? AND circle_id=? AND DATE(meet_at)=? LIMIT 1',[state.event.id,state.circleId,date]);
  if(!meetup) await db.execute(`INSERT INTO event_meeting_points (event_id,circle_id,creator_user_id,latitude,longitude,description,meet_at)
   VALUES (?,?,?,25.0339,121.5645,'Review demo map pin / 審查示意集合點，非真實集合',?)`,[state.event.id,state.circleId,main.id,date+' 06:00:00']);
 }
 for(const reviewer of [main,backup]) {
  await db.execute('INSERT IGNORE INTO follows (follower_user_id,followed_user_id) VALUES (?,?),(?,?)',[reviewer.id,photo.id,coser.id,reviewer.id]);
  for(const [peer,status] of [[coser,'accepted'],[photo,'pending']]) {
   const pair=[reviewer.id,peer.id].sort((a,b)=>BigInt(a)<BigInt(b)?-1:1);
   await db.execute(`INSERT IGNORE INTO friendships
    (user_low_id,user_high_id,requester_id,recipient_id,status,introduction,event_id,day_index,event_name,event_date,accepted_at)
    VALUES (?,?,?,?,?,?,?,?,?,?,${status==='accepted'?'UTC_TIMESTAMP()':'NULL'})`,[...pair,peer.id,reviewer.id,status,
    'Review demo invitation / 我是示範活動入口旁的攝影，這是審查用邀請。',state.event.id,1,'[審查示範] Apple TestFlight Demo — 非真實活動',state.event.startDate]);
  }
 }
 const [afterGoogleReview]=await db.execute("SELECT id,password_hash,session_token,can_view_test_data FROM users WHERE id IN (28,29) ORDER BY id");
 assert.ok(JSON.stringify(afterGoogleReview)===JSON.stringify(originalGoogleReview),'Original Google review accounts must remain unchanged');
 // Seed only this private review namespace, without touching ordinary users.
 for(const [who,kind,body] of [[main,'booking','[Apple 審查示範] 我的場次預定'],[coser,'booking','[Apple 審查示範] 一起出角'],[photo,'general','[Apple 審查示範] 場後一起聊聊拍照']]) {
  const [[old]]=await db.execute('SELECT id FROM social_posts WHERE author_id=? AND body=?',[who.id,body]);
  if(!old)await db.execute("INSERT INTO social_posts(author_id,kind,body,visibility,circle_id,event_id,day_index,work_id)VALUES(?,?,?,'circle',?,?,?,?)",[who.id,kind,body,state.circleId,state.event.id,kind==='booking'?1:null,works[0].id]);
 }
 await db.commit();state.preparedAt=new Date().toISOString();await saveState();
 console.log(JSON.stringify({prepared:true,eventId:state.event.id,circleId:state.circleId,originalGoogleReviewAccountsUnchanged:true,isolatedFixtures:true,reviewAccounts:2,demoAccounts:2,credentialsStoredPrivately:true}));
} catch(error) {if(db) await db.rollback().catch(()=>{});throw error;}
finally {db?.release();await pool.end();}
}

main().catch(() => {
 console.error('Review fixture preparation failed. Credential values and database errors are not displayed.');
 process.exitCode=1;
});
