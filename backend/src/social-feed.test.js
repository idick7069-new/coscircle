import test from 'node:test';import assert from 'node:assert/strict';import {DatabaseSync} from 'node:sqlite';
import {createFeedService,validatePost,feedId,feedMediaAccess} from './social-feed.js';
import {securityBoundary,setAudience} from './release-security.js';
import {requiresCommunityConsent} from './community-consent.js';
function fixture(){
 const db=new DatabaseSync(':memory:');db.function('IF',(c,a,b)=>c?a:b);db.function('UTC_TIMESTAMP',()=>new Date().toISOString());
 db.exec(`CREATE TABLE users(id INTEGER PRIMARY KEY,public_code TEXT,nickname TEXT,avatar_url TEXT,account_status TEXT DEFAULT 'active',is_test_account INTEGER DEFAULT 0,is_admin INTEGER DEFAULT 0,can_view_test_data INTEGER DEFAULT 0,booking_visibility TEXT DEFAULT 'public');
 CREATE TABLE works(id INTEGER PRIMARY KEY,name TEXT,is_test_work INTEGER DEFAULT 0);
 CREATE TABLE events(id INTEGER PRIMARY KEY,name TEXT,start_date TEXT,status TEXT DEFAULT 'approved',is_test_event INTEGER DEFAULT 0);
 CREATE TABLE circles(id INTEGER PRIMARY KEY,is_test_circle INTEGER DEFAULT 0);
 CREATE TABLE circle_members(circle_id INTEGER,user_id INTEGER);
 CREATE TABLE friendships(user_low_id INTEGER,user_high_id INTEGER,status TEXT);
 CREATE TABLE follows(follower_user_id INTEGER,followed_user_id INTEGER);
 CREATE TABLE user_blocks(blocker_user_id INTEGER,blocked_user_id INTEGER);
 CREATE TABLE user_pit_works(user_id INTEGER,work_id INTEGER);
 CREATE TABLE event_bookings(id INTEGER PRIMARY KEY,user_id INTEGER,event_id INTEGER,day_index INTEGER,work_id INTEGER,role TEXT,character_name TEXT,outfit_image_url TEXT);
 CREATE TABLE account_uploads(file_name TEXT,user_id INTEGER);
 CREATE TABLE social_posts(id INTEGER PRIMARY KEY AUTOINCREMENT,author_id INTEGER,kind TEXT,body TEXT,visibility TEXT,circle_id INTEGER,event_id INTEGER,day_index INTEGER,work_id INTEGER,comments_enabled INTEGER DEFAULT 1,deleted_at TEXT,created_at TEXT DEFAULT CURRENT_TIMESTAMP,updated_at TEXT DEFAULT CURRENT_TIMESTAMP,UNIQUE(author_id,event_id,day_index));
 CREATE TABLE social_post_media(post_id INTEGER,url TEXT,ordinal INTEGER);
 CREATE TABLE social_comments(id INTEGER PRIMARY KEY AUTOINCREMENT,post_id INTEGER,author_id INTEGER,parent_id INTEGER,body TEXT,deleted_at TEXT,created_at TEXT DEFAULT CURRENT_TIMESTAMP);
 CREATE TABLE social_likes(post_id INTEGER,user_id INTEGER,UNIQUE(post_id,user_id));
 CREATE TABLE social_notifications(id INTEGER PRIMARY KEY AUTOINCREMENT,recipient_id INTEGER,post_id INTEGER,kind TEXT,is_read INTEGER,updated_at TEXT DEFAULT CURRENT_TIMESTAMP,UNIQUE(recipient_id,post_id,kind));
 CREATE TABLE social_reports(id INTEGER PRIMARY KEY AUTOINCREMENT,reporter_id INTEGER,post_id INTEGER,comment_id INTEGER,target_author_id INTEGER,reason TEXT,details TEXT,evidence_json TEXT,evidence_expires_at TEXT,status TEXT DEFAULT 'pending',reviewed_by INTEGER,reviewed_at TEXT);
 INSERT INTO users(id,public_code,nickname) VALUES(1,'owner','owner'),(2,'friend','friend'),(3,'stranger','stranger'),(4,'blocked','blocked'),(5,'suspended','suspended'),(6,'fixture','fixture'),(7,'review','review');
 UPDATE users SET account_status='suspended' WHERE id=5;UPDATE users SET is_test_account=1 WHERE id IN(6,7);UPDATE users SET can_view_test_data=1 WHERE id=7;
 INSERT INTO works(id,name) VALUES(1,'原神'),(2,'咒術迴戰');INSERT INTO works VALUES(3,'測試作品',1);
 INSERT INTO events(id,name,start_date)VALUES(10,'real event','2027-01-01');INSERT INTO events VALUES(11,'fixture event','2027-01-01','approved',1);
 INSERT INTO circles VALUES(1,0),(2,0);INSERT INTO circle_members VALUES(1,1),(1,2),(2,3);
 INSERT INTO friendships VALUES(1,2,'accepted');INSERT INTO user_pit_works VALUES(2,1);`);
 const translate=sql=>sql.replace(/ FOR UPDATE/g,'').replaceAll('INSERT IGNORE','INSERT OR IGNORE')
  .replace(/DATE_FORMAT\(DATE_ADD\(e.start_date,INTERVAL \(COALESCE\(p.day_index,1\)-1\) DAY\),'%Y-%m-%d'\)/g,"date(e.start_date,'+'||(COALESCE(p.day_index,1)-1)||' day')")
  .replace(/DATE_FORMAT\((\w+\.\w+),'%Y-%m-%dT%H:%i:%sZ'\)/g,'$1')
  .replace(' ON DUPLICATE KEY UPDATE is_read=FALSE,updated_at=CURRENT_TIMESTAMP',' ON CONFLICT(recipient_id,post_id,kind) DO UPDATE SET is_read=FALSE,updated_at=CURRENT_TIMESTAMP')
  .replace("DATE_ADD(UTC_TIMESTAMP(),INTERVAL 90 DAY)","datetime('now','+90 days')")
  .replace('comment_id<=>?','comment_id IS ?');
 const connection={execute:async(sql,params=[])=>{const stmt=db.prepare(translate(sql));return stmt.columns().length?[stmt.all(...params.map(x=>typeof x==='boolean'?Number(x):x))]:[{insertId:Number(stmt.run(...params.map(x=>typeof x==='boolean'?Number(x):x)).lastInsertRowid),affectedRows:db.prepare('SELECT changes() n').get().n}];},beginTransaction:async()=>db.exec('BEGIN'),commit:async()=>db.exec('COMMIT'),rollback:async()=>db.exec('ROLLBACK'),release:()=>{}};
 const pool={...connection,getConnection:async()=>connection};return {db,pool,service:createFeedService(pool)};
}
function asUser(db,id,work){return new Promise((resolve,reject)=>securityBoundary({get:()=>null},{set:()=>{}},()=>{setAudience(db.prepare('SELECT * FROM users WHERE id=?').get(Number(id)));Promise.resolve().then(work).then(resolve,reject);}));}
const post=(extra={})=>({kind:'general',body:'同坑一起聊',visibility:'public',...extra});

test('post validation rejects invalid IDs, empty content, excess images and invalid visibility',()=>{
 for(const value of ['0','-1','1 OR 1=1','18446744073709551616'])assert.throws(()=>feedId(value));
 for(const input of [post({body:''}),post({body:'a'.repeat(2001)}),post({visibility:'circle'}),post({visibility:'friends',circleId:'1'}),post({images:['https://evil.example/photo.png']}),post({kind:'booking',eventId:'10',dayIndex:0})])assert.throws(()=>validatePost(input));
 assert.equal(validatePost(post()).body,'同坑一起聊');
});
test('all community feed writes require consent, while reports/deletion/read notifications remain accessible',()=>{
 for(const [method,url]of [['POST','/api/feed'],['POST','/api/feed/1/comments'],['PUT','/api/feed/1'],['PUT','/api/feed/1/like']])assert.equal(requiresCommunityConsent(method,url),true);
 for(const [method,url]of [['POST','/api/feed/1/reports'],['DELETE','/api/feed/1'],['POST','/api/feed/notifications/1/read']])assert.equal(requiresCommunityConsent(method,url),false);
});
test('friends and exact circle ACL apply to list, detail, comments and media; leaving revokes access',async()=>{
 const f=fixture();try{
 const friends=await f.service.create('1',post({visibility:'friends'})),circle=await f.service.create('1',post({visibility:'circle',circleId:'1'}));
 assert.equal((await f.service.list('2')).items.length,2);assert.equal((await f.service.list('3')).items.length,0);
 await assert.rejects(f.service.detail('3',circle.id),{code:'feed_post_not_found'});await assert.rejects(f.service.comments('3',friends.id),{code:'feed_post_not_found'});
 const url='https://coscircle.app/uploads/00000000-0000-4000-8000-000000000001.png';f.db.prepare('INSERT INTO social_post_media VALUES(?,?,0)').run(Number(circle.id),url);
 assert.equal((await feedMediaAccess(f.pool,url,{id:'2'})).allowed,true);assert.equal((await feedMediaAccess(f.pool,url,{id:'3'})).allowed,false);
 f.db.exec('DELETE FROM circle_members WHERE user_id=2');assert.equal((await feedMediaAccess(f.pool,url,{id:'2'})).allowed,false);await assert.rejects(f.service.comment('2',circle.id,{body:'cannot post'}),{code:'feed_post_not_found'});
 }finally{f.db.close();}
});
test('blocked, suspended and review fixtures are excluded from wall and direct links',async()=>{
 const f=fixture();try{await f.service.create('1',post());await asUser(f.db,6,()=>f.service.create('6',post()));f.db.exec("INSERT INTO social_posts(author_id,kind,body,visibility)VALUES(5,'general','suspended','public')");
 assert.equal((await f.service.list('3')).items.length,1);
 assert.equal((await asUser(f.db,7,()=>f.service.list('7'))).items.length,2);
 for(const [a,b]of [[1,3],[3,1]]){f.db.exec('DELETE FROM user_blocks');f.db.prepare('INSERT INTO user_blocks VALUES(?,?)').run(a,b);assert.equal((await f.service.list('3')).items.length,0);}
 }finally{f.db.close();}
});
test('booking cards read live data, keep independent days, mark cancellation and never broaden circle visibility',async()=>{
 const f=fixture();try{f.db.exec("INSERT INTO event_bookings VALUES(1,1,10,1,1,'coser','first',''),(2,1,10,2,1,'coser','second','')");
 const one=await f.service.create('1',post({kind:'booking',eventId:'10',dayIndex:1}));const two=await f.service.create('1',post({kind:'booking',eventId:'10',dayIndex:2}));
 assert.notEqual(one.id,two.id);f.db.exec("UPDATE event_bookings SET character_name='updated' WHERE id=1");assert.equal((await f.service.detail('2',one.id)).characterName,'updated');
 f.db.exec('DELETE FROM event_bookings WHERE id=1');assert.equal((await f.service.detail('2',one.id)).cancelled,1);assert.equal((await f.service.detail('2',two.id)).cancelled,0);
 await f.service.update('1',one.id,post({commentsEnabled:false}));assert.equal((await f.service.detail('2',one.id)).commentsEnabled,0);
 f.db.exec("UPDATE users SET booking_visibility='circle' WHERE id=1");assert.equal((await f.service.list('3')).items.length,0);await assert.rejects(f.service.create('1',post({kind:'booking',eventId:'10',dayIndex:2})),{code:'booking_visibility_restricted'});
 }finally{f.db.close();}
});
test('comments support replies, reject closed/cross-post replies, and restrict deleting other users content',async()=>{
 const f=fixture();try{const p=await f.service.create('1',post()),other=await f.service.create('1',post());const c=await f.service.comment('2',p.id,{body:'hello'});await f.service.comment('1',p.id,{body:'reply',parentId:c.id});
 assert.equal((await f.service.comments('2',p.id)).items[0].replyTo,'friend');await assert.rejects(f.service.comment('3',other.id,{body:'bad parent',parentId:c.id}),{code:'feed_comment_not_found'});
 await assert.rejects(f.service.removeComment('3',p.id,c.id),{code:'feed_owner_required'});await f.service.removeComment('1',p.id,c.id);assert.equal((await f.service.comments('2',p.id)).items.length,1);
 await f.service.update('1',p.id,post({commentsEnabled:false}));await assert.rejects(f.service.comment('2',p.id,{body:'closed'}),{code:'feed_comments_closed'});
 }finally{f.db.close();}
});
test('likes are idempotent, notifications merge and blocked interaction counts disappear',async()=>{
 const f=fixture();try{const p=await f.service.create('1',post());await f.service.like('2',p.id,true);await f.service.like('2',p.id,true);assert.equal((await f.service.detail('1',p.id)).likeCount,1);assert.equal((await f.service.notifications('1')).length,1);
 await f.service.like('3',p.id,true);assert.equal((await f.service.notifications('1')).length,1);await f.service.comment('2',p.id,{body:'hi'});assert.equal((await f.service.notifications('1')).length,2);
 f.db.exec('INSERT INTO user_blocks VALUES(1,2)');assert.equal((await f.service.detail('1',p.id)).likeCount,1);assert.equal((await f.service.detail('1',p.id)).commentCount,0);assert.equal((await f.service.notifications('1')).length,1);
 await f.service.like('3',p.id,false);assert.equal((await f.service.notifications('1')).length,0);
 }finally{f.db.close();}
});
test('paging uses stable non-overlapping cursors, follows and same-work filter use current tags',async()=>{
 const f=fixture();try{for(let i=0;i<23;i++)await f.service.create('1',post({workId:i%2?'1':'2'}));const first=await f.service.list('2'),next=await f.service.list('2',{before:first.nextCursor});assert.equal(first.items.length,20);assert.equal(next.items.length,3);assert(!next.items.some(x=>first.items.some(y=>x.id===y.id)));
 assert.equal((await f.service.list('2',{scope:'same-work'})).items.length,11);assert.equal((await f.service.list('3',{scope:'following'})).items.length,0);f.db.exec('INSERT INTO follows VALUES(3,1)');assert.equal((await f.service.list('3',{scope:'following'})).items.length,20);
 }finally{f.db.close();}
});
test('images must belong to author; only owners edit or remove posts',async()=>{
 const f=fixture();try{const name='00000000-0000-4000-8000-000000000001.png',url='https://coscircle.app/uploads/'+name;f.db.prepare('INSERT INTO account_uploads VALUES(?,2)').run(name);await assert.rejects(f.service.create('1',post({images:[url]})),{code:'feed_image_not_owned'});const p=await f.service.create('2',post({images:[url]}));assert.deepEqual((await f.service.detail('2',p.id)).images,[url]);await assert.rejects(f.service.update('1',p.id,post()),{code:'feed_owner_required'});await f.service.remove('2',p.id);await assert.rejects(f.service.detail('1',p.id),{code:'feed_post_not_found'});
 }finally{f.db.close();}
});
test('reports are deduplicated, preserve evidence, reject stale removal and allow reviewed takedown',async()=>{
 const f=fixture();try{const p=await f.service.create('1',post());const r=await f.service.report('2',p.id,{reason:'harassment',details:'QA evidence'});assert.equal((await f.service.report('2',p.id,{reason:'harassment'})).id,r.id);
 assert.equal(JSON.parse(f.db.prepare('SELECT evidence_json FROM social_reports WHERE id=?').get(Number(r.id)).evidence_json).body,'同坑一起聊');
 await f.service.update('1',p.id,post({body:'updated by author'}));await assert.rejects(f.service.review('1',r.id,{action:'remove'}),{code:'report_target_changed'});await f.service.review('1',r.id,{action:'dismiss'});
 const fresh=await f.service.report('2',p.id,{reason:'harassment'});await f.service.review('1',fresh.id,{action:'remove'});await assert.rejects(f.service.detail('2',p.id),{code:'feed_post_not_found'});assert.equal(f.db.prepare('SELECT status FROM social_reports WHERE id=?').get(Number(fresh.id)).status,'resolved');
 }finally{f.db.close();}
});
test('reply notifications require a visible reply to this recipient, unrelated comments cannot keep them visible',async()=>{
 const f=fixture();try{const p=await f.service.create('1',post());const c=await f.service.comment('2',p.id,{body:'parent'});const r=await f.service.comment('3',p.id,{body:'reply',parentId:c.id});await f.service.comment('1',p.id,{body:'unrelated'});assert.equal((await f.service.notifications('2')).filter(x=>x.kind==='reply').length,1);await f.service.removeComment('3',p.id,r.id);assert.equal((await f.service.notifications('2')).filter(x=>x.kind==='reply').length,0);
 }finally{f.db.close();}
});

test('ownership is supplied per viewer, cannot be spoofed, and booking editor preserves images and comment settings',async()=>{
 const f=fixture();try{
 f.db.exec("INSERT INTO event_bookings VALUES(1,1,10,1,1,'coser','first','')");
 const url='https://coscircle.app/uploads/00000000-0000-4000-8000-000000000001.png';
 f.db.prepare('INSERT INTO account_uploads VALUES(?,1)').run(url.split('/').pop());
 const p=await f.service.create('1',post({kind:'booking',eventId:'10',dayIndex:1,images:[url],commentsEnabled:false,isMe:false}));
 assert.equal((await f.service.detail('1',p.id)).isMe,1);
 assert.equal((await f.service.detail('2',p.id)).isMe,0);
 const settings=await f.service.bookingShare('1','10',1);
 assert.equal(settings.commentsEnabled,0);assert.deepEqual(settings.images,[url]);assert.equal(settings.isMe,1);
 assert.equal(await f.service.bookingShare('1','10',2),null);
 await f.service.update('1',p.id,post({commentsEnabled:true}));
 await f.service.comment('2',p.id,{body:'peer comment',isMe:true});
 assert.equal((await f.service.comments('1',p.id)).items[0].isMe,0);
 assert.equal((await f.service.comments('2',p.id)).items[0].isMe,1);
 }finally{f.db.close();}
});
