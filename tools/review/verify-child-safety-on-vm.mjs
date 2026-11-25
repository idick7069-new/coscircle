import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {createPool} from '/opt/coscircle/api/current/src/db.js';
if(process.getuid?.()!==0 || !process.argv.includes('--run-production-qa')) throw Error('explicit_root_qa_required');
const db=createPool(),namespace='qa_child_safety',marker='child-safety-qa-'+crypto.randomUUID();
const users=[],reports=[],passed=[];let eventId,circleId;
async function user(label,admin=false){const token=crypto.randomBytes(32).toString('hex');const [r]=await db.execute(`INSERT INTO users (provider,provider_user_id,public_code,nickname,session_token,is_admin,bio,onboarding_completed,booking_visibility) VALUES (?,?,?,?,?,?,?,TRUE,'public')`,[namespace,marker+'-'+label,marker+'-'+label,'Disposable safety QA '+label,token,Number(admin),'文字測試資料，不含真實兒少內容']);const u={id:String(r.insertId),token};users.push(u);return u;}
async function api(method,url,u,body,status){const r=await fetch('http://127.0.0.1:8080/api'+url,{method,headers:{'Content-Type':'application/json','X-Forwarded-Proto':'https',...(u?{Authorization:'Bearer '+u.token}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});assert.equal(r.status,status,method+' '+url+' status '+r.status);return r.status===204?null:r.json();}
try{
 const reporter=await user('reporter'),target=await user('target'),admin=await user('admin',true);
 const [e]=await db.execute(`INSERT INTO events (source_key,source_type,source_name,category,name,start_date,end_date,venue,status) VALUES (?,3,'QA','QA',?,UTC_DATE(),UTC_DATE(),'QA','pending')`,[marker,marker]);eventId=String(e.insertId);
 const [c]=await db.execute('INSERT INTO circles (owner_user_id,name,description,invite_code,invite_url) VALUES (?,?,?,?,?)',[target.id,marker,'Disposable QA',marker.slice(-32),'https://coscircle.app/app']);circleId=String(c.insertId);
 await db.execute('INSERT INTO circle_members (circle_id,user_id) VALUES (?,?),(?,?)',[circleId,target.id,circleId,reporter.id]);
 await db.execute("INSERT INTO event_bookings (event_id,user_id,day_index,role,character_name,message) VALUES (?,?,1,'coser','QA','文字測試預定')",[eventId,target.id]);
 await api('POST','/reports',null,{},401);await api('GET','/admin/reports',reporter,undefined,403);passed.push('anonymous reporting and non-admin queue access rejected');
 const bodies=[{targetType:'user',targetUserId:target.id,reason:'sexual_content'},{targetType:'booking',targetUserId:target.id,eventId,dayIndex:1,reason:'other'},{targetType:'circle',circleId,reason:'other'}];
 for(const body of bodies){const r=await api('POST','/reports',reporter,{...body,details:'兒童安全／純文字 QA，不含真實事件或違法影像。'+marker},201);reports.push(r.id);assert.equal(r.status,'pending');}
 await api('POST','/reports',reporter,bodies[0],409);passed.push('all three report targets accept current child-safety reporting instructions; duplicates rejected');
 const queue=await api('GET','/admin/reports?status=pending',admin,undefined,200);for(const id of reports){const item=queue.items.find(i=>i.id===id);assert(item?.snapshot);assert.match(item.details,/兒童安全/);}
 passed.push('reports reach the real administrator queue with context and snapshots');
 for(const i of [1,2,0]){const id=reports[i];await api('POST','/admin/reports/'+id+'/review',admin,{status:'reviewing',action:'none',expectedVersion:1,note:'QA triage only'},200);await api('POST','/admin/reports/'+id+'/review',admin,{status:'resolved',action:'none',expectedVersion:1},409);await api('POST','/admin/reports/'+id+'/review',admin,{status:'resolved',action:['suspend_user','remove_booking','remove_circle'][i],expectedVersion:2,note:'QA only: no real content'},200);}
 const closed=await api('GET','/admin/reports?status=resolved',admin,undefined,200);for(const id of reports){const item=closed.items.find(i=>i.id===id);assert.equal(item?.reviews.length,2);assert.equal(item.status,'resolved');}
 const [[b]]=await db.execute('SELECT COUNT(*) AS n FROM event_bookings WHERE event_id=?',[eventId]);assert.equal(b.n,0);
 const [[c2]]=await db.execute('SELECT COUNT(*) AS n FROM circles WHERE id=?',[circleId]);assert.equal(c2.n,0);
 const [[u]]=await db.execute('SELECT account_status AS status,session_token AS token FROM users WHERE id=?',[target.id]);assert.equal(u.status,'suspended');assert.equal(u.token,null);await api('GET','/me',target,undefined,401);
 passed.push('reviewing/resolved history, stale version protection, booking/circle removal and suspension with revoked session');
}finally{
 for(const id of reports)await db.execute('DELETE FROM content_reports WHERE id=? AND reporter_user_id IN (SELECT id FROM users WHERE provider=? AND provider_user_id LIKE ?)',[id,namespace,marker+'%']);
 if(circleId)await db.execute('DELETE FROM circles WHERE id=? AND name=?',[circleId,marker]);
 if(eventId)await db.execute('DELETE FROM events WHERE id=? AND source_key=?',[eventId,marker]);
 for(const u of users)await db.execute('DELETE FROM users WHERE id=? AND provider=? AND provider_user_id LIKE ?',[u.id,namespace,marker+'%']);
 const [[left]]=await db.execute('SELECT COUNT(*) AS n FROM users WHERE provider=? AND provider_user_id LIKE ?',[namespace,marker+'%']);assert.equal(left.n,0);await db.end();
}
console.log(JSON.stringify({date:'2026-11-19',production:true,passed,disposableFixturesCleaned:true,realUserContentModified:false},null,2));
