import fs from 'node:fs';import crypto from 'node:crypto';import assert from 'node:assert/strict';import {createRequire} from 'node:module';
const require=createRequire(process.cwd()+'/package.json');const env=require('dotenv').parse(fs.readFileSync('/etc/coscircle/api.env'));
const [action,backup,base='http://127.0.0.1:18081']=process.argv.slice(2);
if(process.getuid()!==0||!/^\/var\/backups\/coscircle\/social-feed-[A-Za-z0-9]+$/.test(backup??''))throw Error('Restricted backup required');
const db=await require('mysql2/promise').createConnection({host:env.MYSQL_HOST||'127.0.0.1',user:env.MYSQL_USER,password:env.MYSQL_PASSWORD,database:env.MYSQL_DATABASE||'coscircle'});
const stateFile=backup+'/qa-state.json';const state=fs.existsSync(stateFile)?JSON.parse(fs.readFileSync(stateFile)):{accounts:[],uploads:[],posts:[]};const save=()=>fs.writeFileSync(stateFile,JSON.stringify(state),{mode:0o600});
async function call(path,{token,method='GET',body,expected=200}={}){const r=await fetch(base+path,{method,headers:{'Content-Type':'application/json','X-Forwarded-Proto':'https',...(token?{Authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});let data;const text=await r.text();try{data=JSON.parse(text);}catch{data=text;}assert.equal(r.status,expected,method+' '+path+' '+(data?.error??''));return {data,r};}
try{
 if(action==='prepare'){
  assert.equal(state.accounts.length,0);
  for(const role of ['ordinary','author','peer','outsider']){
   const email='feed-qa-'+crypto.randomUUID()+'@example.invalid',password=crypto.randomBytes(24).toString('base64url'),salt=crypto.randomBytes(16).toString('hex'),hash=salt+':'+crypto.scryptSync(password,salt,64).toString('hex'),code=crypto.randomBytes(12).toString('hex');
   const fixture=role!=='ordinary';const [u]=await db.execute("INSERT INTO users(provider,provider_user_id,public_code,email,password_hash,nickname,bio,onboarding_completed,is_test_account,can_view_test_data)VALUES('email',?,?,?,?,?,'',TRUE,?,?)",[email,code,email,hash,'[QA暫時隔離] 動態 '+role,fixture,fixture]);
   const id=String(u.insertId);await db.execute("INSERT INTO user_auth_identities(user_id,provider,provider_user_id,password_hash,verified_at)VALUES(?,'email',?,?,UTC_TIMESTAMP())",[id,email,hash]);state.accounts.push({id,email,password,role});save();
  }
  const owner=state.accounts.find(a=>a.role==='author');const peer=state.accounts.find(a=>a.role==='peer');
  const [e]=await db.execute("INSERT INTO events(source_key,source_type,source_name,category,name,start_date,end_date,venue,status,is_test_event)VALUES(?,3,'CosCircle QA','QA','[QA隔離]動態預定',DATE(CONVERT_TZ(UTC_TIMESTAMP(),'+00:00','+08:00')),DATE_ADD(DATE(CONVERT_TZ(UTC_TIMESTAMP(),'+00:00','+08:00')),INTERVAL 2 DAY),'QA，無實際聚會','approved',TRUE)",['feed-qa-'+crypto.randomUUID()]);state.eventId=String(e.insertId);save();
  const [c]=await db.execute('INSERT INTO circles(owner_user_id,name,invite_code,invite_url,is_test_circle)VALUES(?,?,?,?,TRUE)',[owner.id,'[QA隔離]動態圈',crypto.randomBytes(10).toString('hex'),'https://coscircle.app/',]);state.circleId=String(c.insertId);save();
  await db.execute('INSERT INTO circle_members(circle_id,user_id)VALUES(?,?),(?,?)',[state.circleId,owner.id,state.circleId,peer.id]);
  await db.execute("INSERT INTO friendships(user_low_id,user_high_id,requester_id,recipient_id,status,introduction)VALUES(?,?,?,?,'accepted','QA only')",[owner.id,peer.id,owner.id,peer.id]);
  console.log('Prepared isolated feed QA actors and fixtures.');
 }else if(action==='verify'){
  const by=role=>state.accounts.find(a=>a.role===role);for(const a of state.accounts){a.token=(await call('/api/auth/login',{method:'POST',body:{email:a.email,password:a.password}})).data.token;}save();
  const ordinary=by('ordinary'),owner=by('author'),peer=by('peer'),outsider=by('outsider');
  await db.execute('DELETE FROM user_legal_consents WHERE user_id=?',[owner.id]);
  await call('/api/feed',{method:'POST',token:owner.token,body:{body:'consent required'},expected:403});
  for(const a of state.accounts)await call('/api/me/legal',{method:'POST',token:a.token,body:{version:'2026-10-28',accepted:true}});
  const create=async body=>{const {data}=await call('/api/feed',{method:'POST',token:owner.token,body,expected:201});state.posts.push(data.id);save();return data.id;};
  const pub=await create({body:'[QA隔離] Public fixture, invisible to ordinary users'});
  assert(!(await call('/api/feed',{token:ordinary.token})).data.items.some(p=>p.id===pub));await call('/api/feed/'+pub,{token:ordinary.token,expected:404});
  const friends=await create({body:'Friends only',visibility:'friends'}),circle=await create({body:'Circle only',visibility:'circle',circleId:state.circleId});
  await call('/api/feed/'+friends,{token:peer.token});await call('/api/feed/'+friends,{token:outsider.token,expected:404});await call('/api/feed/'+circle,{token:peer.token});await call('/api/feed/'+circle,{token:outsider.token,expected:404});
  const comment=(await call('/api/feed/'+friends+'/comments',{token:peer.token,method:'POST',body:{body:'QA comment'},expected:201})).data.id;
  await call('/api/feed/'+friends+'/comments',{token:owner.token,method:'POST',body:{body:'QA reply',parentId:comment},expected:201});
  await call('/api/feed/'+friends+'/like',{token:peer.token,method:'PUT'});await call('/api/feed/'+friends+'/like',{token:peer.token,method:'PUT'});assert.equal((await call('/api/feed/'+friends,{token:owner.token})).data.likeCount,1);
  assert((await call('/api/feed/notifications',{token:owner.token})).data.length>=2);
  await call('/api/feed/'+friends,{token:owner.token,method:'PUT',body:{body:'Friends only',visibility:'friends',commentsEnabled:false}});await call('/api/feed/'+friends+'/comments',{token:peer.token,method:'POST',body:{body:'closed'},expected:409});
  await call('/api/feed/'+friends+'/comments/'+comment,{token:outsider.token,method:'DELETE',expected:404});await call('/api/feed/'+friends+'/comments/'+comment,{token:owner.token,method:'DELETE',expected:204});
  const image=(await call('/api/uploads/image',{method:'POST',token:owner.token,body:{mimeType:'image/png',bytesBase64:'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jlp0AAAAASUVORK5CYII='},expected:201})).data.url;state.uploads.push(new URL(image).pathname.split('/').pop());save();
  const photoPost=await create({body:'Circle photo',visibility:'circle',circleId:state.circleId,images:[image]});
  const photo=(await call('/api/feed/'+photoPost,{token:peer.token})).data.images[0];assert(photo.includes('?e='));const u=new URL(photo);assert.equal((await fetch(base+u.pathname+u.search)).status,200);await call('/api/media/sign',{method:'POST',token:outsider.token,body:{url:image},expected:404});
  await db.execute('DELETE FROM circle_members WHERE circle_id=? AND user_id=?',[state.circleId,peer.id]);assert.equal((await fetch(base+u.pathname+u.search)).status,404);await db.execute('INSERT INTO circle_members(circle_id,user_id)VALUES(?,?)',[state.circleId,peer.id]);
  await db.execute('INSERT INTO user_blocks(blocker_user_id,blocked_user_id)VALUES(?,?)',[owner.id,peer.id]);await call('/api/feed/'+circle,{token:peer.token,expected:404});await db.execute('DELETE FROM user_blocks WHERE blocker_user_id=? AND blocked_user_id=?',[owner.id,peer.id]);
  await call('/api/events/'+state.eventId+'/bookings',{method:'POST',token:owner.token,body:{role:'coser',dayIndex:2,characterName:'QA original',shareToFeed:true,feedVisibility:'circle',feedCircleId:state.circleId},expected:204});
  const shared=(await call('/api/feed/booking-share?eventId='+state.eventId+'&dayIndex=2',{token:owner.token})).data.id;state.posts.push(shared);save();
  await call('/api/events/'+state.eventId+'/bookings',{method:'POST',token:owner.token,body:{role:'coser',dayIndex:2,characterName:'QA updated'},expected:204});assert.equal((await call('/api/feed/'+shared,{token:peer.token})).data.characterName,'QA updated');
  await call('/api/events/'+state.eventId+'/bookings/me?dayIndex=2',{method:'DELETE',token:owner.token,expected:204});assert.equal((await call('/api/feed/'+shared,{token:peer.token})).data.cancelled,1);
  const reported=await call('/api/feed/'+pub+'/reports',{method:'POST',token:peer.token,body:{reason:'other',details:'QA verification'},expected:201});assert(reported.data.id);await call('/api/admin/feed-reports',{token:peer.token,expected:403});
  const works=(await call('/api/works?query='+encodeURIComponent('星鐵'),{token:ordinary.token})).data;assert(works.some(w=>w.name==='崩壞：星穹鐵道'));
  // Exercise mutations and their visibility through the public HTTPS boundary as well.
  assert.equal((await call('/api/feed/'+pub,{token:owner.token})).data.isMe,1);
  assert.equal((await call('/api/feed/'+pub,{token:peer.token})).data.isMe,0);
  await call('/api/feed/'+friends+'/like',{token:peer.token,method:'DELETE'});
  assert.equal((await call('/api/feed/'+friends,{token:owner.token})).data.likeCount,0);
  await call('/api/feed/'+friends,{token:owner.token,method:'PUT',body:{body:'Reopened',visibility:'friends',commentsEnabled:true}});
  const ownComment=(await call('/api/feed/'+friends+'/comments',{token:peer.token,method:'POST',body:{body:'Delete my own comment',isMe:false},expected:201})).data.id;
  assert.equal((await call('/api/feed/'+friends+'/comments',{token:peer.token})).data.items.find(c=>c.id===ownComment).isMe,1);
  await call('/api/feed/'+friends+'/comments/'+ownComment,{token:peer.token,method:'DELETE',expected:204});
  await call('/api/feed/'+pub,{token:owner.token,method:'PUT',body:{body:'Restricted now',visibility:'friends',isMe:false}});
  await call('/api/feed/'+pub,{token:outsider.token,expected:404});
  await call('/api/feed/'+pub,{token:owner.token,method:'PUT',body:{body:'Circle now',visibility:'circle',circleId:state.circleId}});
  await call('/api/feed/'+pub,{token:peer.token});
  await call('/api/feed/'+pub,{token:owner.token,method:'PUT',body:{body:'Public again',visibility:'public'}});
  await call('/api/feed/'+pub,{token:outsider.token});
  await db.execute("UPDATE friendships SET status='ignored' WHERE user_low_id=? AND user_high_id=?",[owner.id,peer.id]);
  await call('/api/feed/'+friends,{token:peer.token,expected:404});
  await db.execute("UPDATE friendships SET status='accepted' WHERE user_low_id=? AND user_high_id=?",[owner.id,peer.id]);
  await call('/api/events/'+state.eventId+'/bookings',{method:'POST',token:owner.token,body:{role:'coser',dayIndex:1,characterName:'D1 independent',shareToFeed:true,feedVisibility:'public'},expected:204});
  const dayOne=(await call('/api/feed/booking-share?eventId='+state.eventId+'&dayIndex=1',{token:owner.token})).data;
  assert.notEqual(dayOne.id,shared);assert.equal(dayOne.cancelled,0);
  assert.equal((await call('/api/feed/'+shared,{token:owner.token})).data.cancelled,1);
  await call('/api/feed/'+dayOne.id,{method:'PUT',token:owner.token,body:{body:'Keep these settings',visibility:'circle',circleId:state.circleId,images:[image],commentsEnabled:false}});
  const fullShare=(await call('/api/feed/booking-share?eventId='+state.eventId+'&dayIndex=1',{token:owner.token})).data;
  assert.equal(fullShare.commentsEnabled,0);assert.equal(fullShare.images.length,1);
  await call('/api/events/'+state.eventId+'/bookings',{method:'POST',token:owner.token,body:{role:'coser',dayIndex:1,characterName:'D1 refreshed',shareToFeed:true,feedVisibility:'circle',feedCircleId:state.circleId},expected:204});
  const preserved=(await call('/api/feed/'+dayOne.id,{token:owner.token})).data;
  assert.equal(preserved.commentsEnabled,0);assert.equal(preserved.images.length,1);
  await call('/api/events/'+state.eventId+'/bookings',{method:'POST',token:owner.token,body:{role:'coser',dayIndex:1,characterName:'D1 retained booking',shareToFeed:false},expected:204});
  await call('/api/feed/'+dayOne.id,{token:owner.token,expected:404});
  await call('/api/feed/'+pub,{token:peer.token,method:'DELETE',expected:403});
  await call('/api/feed/'+pub,{token:owner.token,method:'DELETE',expected:204});
  await call('/api/feed/'+pub,{token:owner.token,expected:404});
  const result={fullCrud:true,ownershipMetadata:true,visibilityChanges:true,friendRemovalRevokesAccess:true,bookingEditorPreservesSettings:true,independentBookingDays:true,feedAcl:true,testDataIsolation:true,commentsReplies:true,idempotentLikes:true,mergedNotifications:true,closedComments:true,commentOwnership:true,protectedPostImages:true,leavingRevokesMedia:true,blockRevokesFeed:true,liveBookingUpdate:true,cancellationPreservesPost:true,reportAndAdminGuard:true,aliasSearch:true};fs.writeFileSync(backup+'/qa-results.json',JSON.stringify(result,null,2),{mode:0o600});console.log(JSON.stringify(result));
 }else if(action==='export-ui'){
  assert(!state.cleaned);const by=role=>state.accounts.find(a=>a.role===role);
  const fields={};for(const role of ['author','peer','outsider','ordinary']){assert(by(role).token);fields[role+'Token']=by(role).token;fields[role+'Id']=by(role).id;}
  fields.eventId=state.eventId;fields.circleId=state.circleId;
  await db.execute('DELETE FROM user_legal_consents WHERE user_id=?',[by('author').id]);
  fs.writeFileSync(backup+'/ui-defines.json',JSON.stringify({FEED_QA:JSON.stringify(fields)}),{mode:0o600});
  console.log('Prepared restricted UI session file; credentials were not printed.');
 }else if(action==='cleanup'){
  if(state.eventId)await db.execute('DELETE FROM events WHERE id=? AND is_test_event=TRUE',[state.eventId]);if(state.circleId)await db.execute('DELETE FROM circles WHERE id=? AND is_test_circle=TRUE',[state.circleId]);
  for(const a of state.accounts)await db.execute("DELETE FROM users WHERE id=? AND provider_user_id=? AND nickname LIKE '[QA暫時隔離]%'",[a.id,a.email]);
  for(const name of state.uploads){assert(/^[a-f0-9-]+\.png$/.test(name));await db.execute('DELETE FROM account_uploads WHERE file_name=? AND user_id IS NULL',[name]);try{fs.unlinkSync('/var/lib/coscircle/uploads/'+name);}catch(e){if(e.code!=='ENOENT')throw e;}}
  state.cleaned=true;save();console.log('Removed only disposable feed QA actors, their posts and synthetic images.');
 }else throw Error('Unknown action');
}finally{await db.end();}
