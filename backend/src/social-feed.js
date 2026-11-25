import {currentAudience,setAudience, visibleRow, canonicalMediaUrl} from './release-security.js';
import {inTransaction} from './db-transaction.js';

function fail(status,code){throw Object.assign(new Error(code),{status,code});}
export function feedId(value,nullable=false){
 if(nullable&&(value==null||value===''))return null;
 const id=String(value??'');if(!/^[1-9]\d{0,19}$/.test(id)||BigInt(id)>18446744073709551615n)fail(400,'invalid_feed_id');return id;
}
function text(value,max,required=false){if(typeof value!=='string'||[...value].length>max||(required&&!value.trim()))fail(400,'invalid_feed_text');return value.trim();}
export function validatePost(body){
 if(!body||typeof body!=='object')fail(400,'invalid_feed_post');
 const kind=body.kind??'general',visibility=body.visibility??'public';
 if(!['booking','general'].includes(kind)||!['public','friends','circle'].includes(visibility))fail(400,'invalid_feed_post');
 const circleId=feedId(body.circleId,true),eventId=feedId(body.eventId,true),workId=feedId(body.workId,true);
 if(visibility==='circle'&&!circleId||visibility!=='circle'&&circleId)fail(400,'invalid_feed_circle');
 let dayIndex=null;if(kind==='booking'){dayIndex=Number(body.dayIndex);if(!eventId||!Number.isSafeInteger(dayIndex)||dayIndex<1||dayIndex>366)fail(400,'invalid_day_index');}
 const images=body.images??[];if(!Array.isArray(images)||images.length>4||images.some(x=>typeof x!=='string'))fail(400,'invalid_feed_images');
 const media=images.map(canonicalMediaUrl);if(media.some(x=>!/^https:\/\/coscircle\.app\/uploads\/[a-f0-9-]{36}\.(png|jpg|webp)$/.test(x))||new Set(media).size!==media.length)fail(400,'invalid_feed_images');
 const content=text(body.body??'',2000);if(kind==='general'&&!content&&!media.length)fail(400,'empty_feed_post');
 if(body.commentsEnabled!==undefined&&typeof body.commentsEnabled!=='boolean')fail(400,'invalid_feed_post');
 return {kind,visibility,circleId,eventId,dayIndex,workId,body:content,images:media,commentsEnabled:body.commentsEnabled??true};
}
export function feedUserVisible(alias,userId){
 const v=feedId(userId);
 return `${visibleRow(alias,'user')} AND NOT EXISTS(SELECT 1 FROM user_blocks fb WHERE (fb.blocker_user_id=${v} AND fb.blocked_user_id=${alias}.id) OR (fb.blocker_user_id=${alias}.id AND fb.blocked_user_id=${v}))`;
}
// All public surfaces, including media and notifications, use this predicate.
export function feedVisible(userId,{post='p',author='a'}={}){
 if(!/^[a-z_]+$/.test(post)||!/^[a-z_]+$/.test(author))throw Error('Unsafe SQL alias');
 const v=feedId(userId),p=post,a=author;
 const shared=`EXISTS(SELECT 1 FROM circle_members cm JOIN circle_members ca ON ca.circle_id=cm.circle_id AND ca.user_id=${a}.id WHERE cm.user_id=${v})`;
 return `${p}.deleted_at IS NULL AND ${feedUserVisible(a,v)}
 AND (${p}.event_id IS NULL OR EXISTS(SELECT 1 FROM events e WHERE e.id=${p}.event_id AND ${visibleRow('e','event')} AND e.status='approved'))
 AND (${p}.work_id IS NULL OR EXISTS(SELECT 1 FROM works fw WHERE fw.id=${p}.work_id AND ${visibleRow('fw','work')}))
 AND (${p}.visibility='public' OR ${p}.author_id=${v}
   OR (${p}.visibility='friends' AND EXISTS(SELECT 1 FROM friendships f WHERE f.status='accepted' AND ((f.user_low_id=${v} AND f.user_high_id=${p}.author_id) OR (f.user_high_id=${v} AND f.user_low_id=${p}.author_id))))
   OR (${p}.visibility='circle' AND EXISTS(SELECT 1 FROM circle_members cm JOIN circle_members ca ON ca.circle_id=cm.circle_id AND ca.user_id=${p}.author_id JOIN circles fc ON fc.id=cm.circle_id WHERE cm.user_id=${v} AND cm.circle_id=${p}.circle_id AND ${visibleRow('fc','circle')})))
 AND NOT EXISTS(SELECT 1 FROM event_bookings wb JOIN works hidden_work ON hidden_work.id=wb.work_id WHERE ${p}.kind='booking' AND wb.user_id=${p}.author_id AND wb.event_id=${p}.event_id AND wb.day_index=${p}.day_index AND NOT (${visibleRow('hidden_work','work')}))
 AND (${p}.kind<>'booking' OR ${p}.author_id=${v} OR ${a}.booking_visibility='public' OR (${a}.booking_visibility='circle' AND ${shared}))`;
}
export async function feedMediaAccess(pool,url,user){
 const v=user?.id;
 if(v)setAudience(user);
 if(!v){const [[row]]=await pool.execute('SELECT 1 n FROM social_post_media WHERE url=? LIMIT 1',[url]);return {referenced:Boolean(row),allowed:false};}
 const [rows]=await pool.execute(`SELECT p.id,(${feedVisible(v)}) AS allowed FROM social_post_media m JOIN social_posts p ON p.id=m.post_id JOIN users a ON a.id=p.author_id WHERE m.url=?`,[url]);
 return {referenced:rows.length>0,allowed:rows.some(r=>Boolean(r.allowed))};
}
const joins=`FROM social_posts p JOIN users a ON a.id=p.author_id
 LEFT JOIN event_bookings b ON p.kind='booking' AND b.user_id=p.author_id AND b.event_id=p.event_id AND b.day_index=p.day_index
 LEFT JOIN events e ON e.id=p.event_id LEFT JOIN works w ON w.id=IF(p.kind='booking',b.work_id,p.work_id)`;
function postSelect(v){return `SELECT CAST(p.id AS CHAR) id,(p.author_id=${v}) AS isMe,CAST(p.author_id AS CHAR) authorId,a.public_code publicCode,a.nickname,a.avatar_url avatarUrl,
 p.kind,p.body,p.visibility,CAST(p.circle_id AS CHAR) circleId,CAST(p.event_id AS CHAR) eventId,p.day_index dayIndex,
 CAST(IF(p.kind='booking',b.work_id,p.work_id) AS CHAR) workId,w.name workName,p.comments_enabled commentsEnabled,
 e.name eventName,DATE_FORMAT(DATE_ADD(e.start_date,INTERVAL (COALESCE(p.day_index,1)-1) DAY),'%Y-%m-%d') eventDate,
 b.role,b.character_name characterName,b.outfit_image_url outfitImageUrl,(p.kind='booking' AND b.id IS NULL) cancelled,
 DATE_FORMAT(p.created_at,'%Y-%m-%dT%H:%i:%sZ') createdAt,
 EXISTS(SELECT 1 FROM social_likes l WHERE l.post_id=p.id AND l.user_id=${v}) liked,
 EXISTS(SELECT 1 FROM user_pit_works mine WHERE mine.user_id=${v} AND mine.work_id=IF(p.kind='booking',b.work_id,p.work_id)) sameWork,
 (SELECT COUNT(*) FROM social_likes l JOIN users lu ON lu.id=l.user_id WHERE l.post_id=p.id AND ${feedUserVisible('lu',v)}) likeCount,
 (SELECT COUNT(*) FROM social_comments c JOIN users cu ON cu.id=c.author_id WHERE c.post_id=p.id AND c.deleted_at IS NULL AND ${feedUserVisible('cu',v)}) commentCount ${joins}`;}
async function getPost(db,v,id,lock=false){
 const [[p]]=await db.execute(`${postSelect(v)} WHERE p.id=? AND ${feedVisible(v)}${lock?' FOR UPDATE':''}`,[feedId(id)]);if(!p)fail(404,'feed_post_not_found');return p;
}
async function validateReferences(db,v,data,{allowCancelled=false}={}){
 if(data.circleId){const [[c]]=await db.execute(`SELECT c.id FROM circles c JOIN circle_members m ON m.circle_id=c.id WHERE c.id=? AND m.user_id=? AND ${visibleRow('c','circle')}`,[data.circleId,v]);if(!c)fail(404,'feed_circle_not_found');}
 if(data.eventId){const [[e]]=await db.execute(`SELECT e.id FROM events e WHERE e.id=? AND e.status='approved' AND ${visibleRow('e','event')}`,[data.eventId]);if(!e)fail(404,'event_not_found');}
 if(data.workId){const [[w]]=await db.execute(`SELECT w.id FROM works w WHERE w.id=? AND ${visibleRow('w','work')}`,[data.workId]);if(!w)fail(404,'work_not_found');}
 if(data.kind==='booking'){
  const [[b]]=await db.execute('SELECT b.id,u.booking_visibility FROM event_bookings b JOIN users u ON u.id=b.user_id WHERE b.user_id=? AND b.event_id=? AND b.day_index=? FOR UPDATE',[v,data.eventId,data.dayIndex]);
  if(!b&&!allowCancelled)fail(409,'booking_required');
  const [[owner]]=await db.execute('SELECT booking_visibility FROM users WHERE id=?',[v]);
  if(owner.booking_visibility==='circle'&&data.visibility!=='circle')fail(400,'booking_visibility_restricted');
 }
 for(const image of data.images){const [[m]]=await db.execute('SELECT user_id FROM account_uploads WHERE file_name=? FOR UPDATE',[image.split('/').pop()]);if(String(m?.user_id)!==v)fail(403,'feed_image_not_owned');}
}
async function saveMedia(db,id,images){await db.execute('DELETE FROM social_post_media WHERE post_id=?',[id]);for(const [i,url]of images.entries())await db.execute('INSERT INTO social_post_media(post_id,url,ordinal)VALUES(?,?,?)',[id,url,i]);}
async function assertInteraction(db,author){
 if(!currentAudience().fixtureActor)return;
 const [[user]]=await db.execute('SELECT is_test_account,is_admin FROM users WHERE id=?',[author]);
 if(!user?.is_test_account&&!user?.is_admin)fail(404,'feed_post_not_found');
}
async function notification(db,recipient,postId,kind,actor){
 if(String(recipient)===String(actor))return;
 await db.execute(`INSERT INTO social_notifications(recipient_id,post_id,kind,is_read)VALUES(?,?,?,FALSE) ON DUPLICATE KEY UPDATE is_read=FALSE,updated_at=CURRENT_TIMESTAMP`,[recipient,postId,kind]);
}
export function createFeedService(pool){
 async function list(v,query={}){
  v=feedId(v);const kind=query.kind??'all',scope=query.scope??'all';
  if(!['all','booking','general'].includes(kind)||!['all','following','same-work','circle'].includes(scope))fail(400,'invalid_feed_filter');
  const before=feedId(query.before,true),eventId=feedId(query.eventId,true);let where=feedVisible(v);const args=[];
  if(kind!=='all'){where+=' AND p.kind=?';args.push(kind);}if(before){where+=' AND p.id<?';args.push(before);}if(eventId){where+=' AND p.event_id=?';args.push(eventId);}
  if(scope==='following')where+=` AND (p.author_id=${v} OR EXISTS(SELECT 1 FROM follows f WHERE f.follower_user_id=${v} AND f.followed_user_id=p.author_id) OR EXISTS(SELECT 1 FROM friendships f WHERE f.status='accepted' AND ((f.user_low_id=${v} AND f.user_high_id=p.author_id) OR (f.user_high_id=${v} AND f.user_low_id=p.author_id))))`;
  if(scope==='same-work')where+=` AND EXISTS(SELECT 1 FROM user_pit_works mine WHERE mine.user_id=${v} AND mine.work_id=IF(p.kind='booking',b.work_id,p.work_id))`;
  if(scope==='circle')where+=` AND EXISTS(SELECT 1 FROM circle_members mine JOIN circle_members theirs ON theirs.circle_id=mine.circle_id WHERE mine.user_id=${v} AND theirs.user_id=p.author_id)`;
  const [rows]=await pool.execute(`${postSelect(v)} WHERE ${where} ORDER BY p.id DESC LIMIT 21`,args);const items=rows.slice(0,20);await attachMedia(items);
  return {items,nextCursor:rows.length>20?items.at(-1).id:null};
 }
 async function attachMedia(posts){if(!posts.length)return;const ids=posts.map(x=>x.id);const [media]=await pool.execute(`SELECT CAST(post_id AS CHAR) postId,url FROM social_post_media WHERE post_id IN (${ids.map(()=>'?').join(',')}) ORDER BY ordinal`,ids);for(const p of posts)p.images=media.filter(x=>x.postId===p.id).map(x=>x.url);}
 async function bookingShare(v,eventId,dayIndex){
  if(!Number.isSafeInteger(Number(dayIndex))||Number(dayIndex)<1)fail(400,'invalid_day_index');
  const [[row]]=await pool.execute("SELECT CAST(id AS CHAR) id,body,visibility,CAST(circle_id AS CHAR) circleId FROM social_posts WHERE author_id=? AND event_id=? AND day_index=? AND deleted_at IS NULL",[feedId(v),feedId(eventId),Number(dayIndex)]);return row?detail(v,String(row.id)):null;
 }
 async function detail(v,id){const p=await getPost(pool,feedId(v),id);await attachMedia([p]);return p;}
 async function create(v,body,db=null){
  v=feedId(v);const data=validatePost(body);
  const run=async connection=>{
   await validateReferences(connection,v,data);
   let id;
   if(data.kind==='booking'){
    const [[old]]=await connection.execute('SELECT id FROM social_posts WHERE author_id=? AND event_id=? AND day_index=? FOR UPDATE',[v,data.eventId,data.dayIndex]);
    if(old){id=old.id;await connection.execute('UPDATE social_posts SET body=?,visibility=?,circle_id=?,comments_enabled=IF(?,comments_enabled,?),deleted_at=NULL WHERE id=?',[data.body,data.visibility,data.circleId,body.preserveExisting===true,data.commentsEnabled,id]);}
   }
   if(!id){const [r]=await connection.execute('INSERT INTO social_posts(author_id,kind,body,visibility,circle_id,event_id,day_index,work_id,comments_enabled)VALUES(?,?,?,?,?,?,?,?,?)',[v,data.kind,data.body,data.visibility,data.circleId,data.eventId,data.dayIndex,data.workId,data.commentsEnabled]);id=r.insertId;}
   if(body.preserveExisting!==true)await saveMedia(connection,id,data.images);return {id:String(id)};
  };
  return db?run(db):inTransaction(pool,run);
 }
 async function update(v,id,body){
  v=feedId(v);return inTransaction(pool,async db=>{const old=await getPost(db,v,id,true);if(old.authorId!==v)fail(403,'feed_owner_required');
   const data=validatePost({...body,kind:old.kind,...(old.kind==='booking'?{eventId:old.eventId,dayIndex:old.dayIndex}:{})});await validateReferences(db,v,data,{allowCancelled:true});
   await db.execute('UPDATE social_posts SET body=?,visibility=?,circle_id=?,work_id=?,comments_enabled=? WHERE id=?',[data.body,data.visibility,data.circleId,data.workId,data.commentsEnabled,id]);await saveMedia(db,id,data.images);return {id};
  });
 }
 async function remove(v,id){v=feedId(v);const p=await getPost(pool,v,id);if(p.authorId!==v)fail(403,'feed_owner_required');await pool.execute('UPDATE social_posts SET deleted_at=UTC_TIMESTAMP(),body=\'\' WHERE id=?',[id]);}
 async function comments(v,id,before){v=feedId(v);await getPost(pool,v,id);const cursor=feedId(before,true);
  const [rows]=await pool.execute(`SELECT CAST(c.id AS CHAR) id,(c.author_id=${v}) AS isMe,CAST(c.author_id AS CHAR) authorId,cu.public_code publicCode,cu.nickname,cu.avatar_url avatarUrl,c.body,CAST(c.parent_id AS CHAR) parentId,
   CASE WHEN parent.deleted_at IS NULL AND ${feedUserVisible('pa',v)} THEN pa.nickname ELSE NULL END replyTo,
   DATE_FORMAT(c.created_at,'%Y-%m-%dT%H:%i:%sZ') createdAt
   FROM social_comments c JOIN users cu ON cu.id=c.author_id LEFT JOIN social_comments parent ON parent.id=c.parent_id LEFT JOIN users pa ON pa.id=parent.author_id
   WHERE c.post_id=? AND c.deleted_at IS NULL AND ${feedUserVisible('cu',v)} ${cursor?'AND c.id<?':''} ORDER BY c.id DESC LIMIT 31`,cursor?[id,cursor]:[id]);
  return {items:rows.slice(0,30),nextCursor:rows.length>30?String(rows[29].id):null};
 }
 async function comment(v,id,body){v=feedId(v);const content=text(body?.body,1000,true),parentId=feedId(body?.parentId,true);
  return inTransaction(pool,async db=>{const p=await getPost(db,v,id,true);await assertInteraction(db,p.authorId);if(!p.commentsEnabled)fail(409,'feed_comments_closed');let parent;
   if(parentId){const [[row]]=await db.execute(`SELECT c.author_id authorId FROM social_comments c JOIN users cu ON cu.id=c.author_id WHERE c.id=? AND c.post_id=? AND c.deleted_at IS NULL AND ${feedUserVisible('cu',v)} FOR UPDATE`,[parentId,id]);if(!row)fail(404,'feed_comment_not_found');parent=row;}
   const [r]=await db.execute('INSERT INTO social_comments(post_id,author_id,parent_id,body)VALUES(?,?,?,?)',[id,v,parentId,content]);
   await notification(db,p.authorId,id,'comment',v);if(parent&&String(parent.authorId)!==p.authorId)await notification(db,parent.authorId,id,'reply',v);
   return {id:String(r.insertId)};
  });
 }
 async function removeComment(v,id,commentId){v=feedId(v);const p=await getPost(pool,v,id);const [[c]]=await pool.execute('SELECT author_id authorId FROM social_comments WHERE id=? AND post_id=?',[feedId(commentId),id]);if(!c)fail(404,'feed_comment_not_found');if(String(c.authorId)!==v&&p.authorId!==v)fail(403,'feed_owner_required');await pool.execute("UPDATE social_comments SET deleted_at=UTC_TIMESTAMP(),body='' WHERE id=? AND post_id=?",[commentId,id]);}
 async function like(v,id,enabled){v=feedId(v);return inTransaction(pool,async db=>{const p=await getPost(db,v,id,true);await assertInteraction(db,p.authorId);if(enabled){const [r]=await db.execute('INSERT IGNORE INTO social_likes(post_id,user_id)VALUES(?,?)',[id,v]);if(r.affectedRows)await notification(db,p.authorId,id,'like',v);}else await db.execute('DELETE FROM social_likes WHERE post_id=? AND user_id=?',[id,v]);return {liked:enabled};});}
 async function notifications(v){v=feedId(v);const [rows]=await pool.execute(`SELECT CAST(n.id AS CHAR) id,CAST(n.post_id AS CHAR) postId,n.kind,n.is_read isRead,DATE_FORMAT(n.updated_at,'%Y-%m-%dT%H:%i:%sZ') updatedAt FROM social_notifications n JOIN social_posts p ON p.id=n.post_id JOIN users a ON a.id=p.author_id WHERE n.recipient_id=? AND ${feedVisible(v)}
 AND ((n.kind='like' AND EXISTS(SELECT 1 FROM social_likes l JOIN users actor ON actor.id=l.user_id WHERE l.post_id=p.id AND l.user_id<>${v} AND ${feedUserVisible('actor',v)}))
 OR (n.kind='comment' AND EXISTS(SELECT 1 FROM social_comments c JOIN users actor ON actor.id=c.author_id WHERE c.post_id=p.id AND c.author_id<>${v} AND c.deleted_at IS NULL AND ${feedUserVisible('actor',v)}))
 OR (n.kind='reply' AND EXISTS(SELECT 1 FROM social_comments c JOIN social_comments parent ON parent.id=c.parent_id JOIN users actor ON actor.id=c.author_id WHERE c.post_id=p.id AND parent.author_id=${v} AND parent.deleted_at IS NULL AND c.author_id<>${v} AND c.deleted_at IS NULL AND ${feedUserVisible('actor',v)}))) ORDER BY n.updated_at DESC,n.id DESC LIMIT 100`,[v]);return rows;}
 async function readNotification(v,id){v=feedId(v);await pool.execute('UPDATE social_notifications SET is_read=TRUE WHERE id=? AND recipient_id=?',[feedId(id),v]);}
 async function report(v,id,body){v=feedId(v);const reason=body?.reason;if(!['spam','harassment','sexual_content','hate','impersonation','privacy','other'].includes(reason))fail(400,'invalid_report');const details=text(body.details??'',1000),commentId=feedId(body.commentId,true);
  return inTransaction(pool,async db=>{const p=await getPost(db,v,id,true);const [images]=await db.execute('SELECT url FROM social_post_media WHERE post_id=? ORDER BY ordinal',[id]);
   let evidence={body:p.body,kind:p.kind,images:images.map(x=>x.url),outfitImageUrl:p.outfitImageUrl??''},author=p.authorId;
   if(commentId){const [[c]]=await db.execute(`SELECT c.body,CAST(c.author_id AS CHAR) authorId FROM social_comments c JOIN users cu ON cu.id=c.author_id WHERE c.id=? AND c.post_id=? AND c.deleted_at IS NULL AND ${feedUserVisible('cu',v)} FOR UPDATE`,[commentId,id]);if(!c)fail(404,'feed_comment_not_found');evidence={body:c.body};author=c.authorId;}
   const [[existing]]=await db.execute("SELECT id FROM social_reports WHERE reporter_id=? AND post_id=? AND comment_id<=>? AND status='pending'",[v,id,commentId]);if(existing)return {id:String(existing.id)};
   const [r]=await db.execute('INSERT INTO social_reports(reporter_id,post_id,comment_id,target_author_id,reason,details,evidence_json,evidence_expires_at)VALUES(?,?,?,?,?,?,?,DATE_ADD(UTC_TIMESTAMP(),INTERVAL 90 DAY))',[v,id,commentId,author,reason,details,JSON.stringify(evidence)]);return {id:String(r.insertId)};
  });
 }
 async function reportList(){const [rows]=await pool.execute("SELECT CAST(id AS CHAR) id,CAST(post_id AS CHAR) postId,CAST(comment_id AS CHAR) commentId,reason,details,status,IF(evidence_expires_at>UTC_TIMESTAMP(),evidence_json,NULL) evidence FROM social_reports ORDER BY id DESC LIMIT 100");return rows;}
 async function review(adminId,id,body){if(!['remove','dismiss'].includes(body?.action))fail(400,'invalid_report_action');return inTransaction(pool,async db=>{const [[r]]=await db.execute("SELECT * FROM social_reports WHERE id=? AND status='pending' FOR UPDATE",[feedId(id)]);if(!r)fail(409,'stale_report');
  if(body.action==='remove'){
   if(new Date(r.evidence_expires_at)<=new Date()||!r.evidence_json)fail(409,'report_evidence_unavailable');
   const snapshot=typeof r.evidence_json==='string'?JSON.parse(r.evidence_json):r.evidence_json;
   const [[current]]=await db.execute(r.comment_id?'SELECT body FROM social_comments WHERE id=? AND post_id=? AND deleted_at IS NULL FOR UPDATE':'SELECT body FROM social_posts WHERE id=? AND deleted_at IS NULL FOR UPDATE',r.comment_id?[r.comment_id,r.post_id]:[r.post_id]);
   if(!current||current.body!==snapshot.body)fail(409,'report_target_changed');
   if(r.comment_id)await db.execute("UPDATE social_comments SET deleted_at=UTC_TIMESTAMP(),body='' WHERE id=? AND post_id=?",[r.comment_id,r.post_id]);else await db.execute("UPDATE social_posts SET deleted_at=UTC_TIMESTAMP(),body='' WHERE id=?",[r.post_id]);}
  await db.execute('UPDATE social_reports SET status=?,reviewed_by=?,reviewed_at=UTC_TIMESTAMP() WHERE id=?',[body.action==='remove'?'resolved':'dismissed',adminId,id]);return {id};});}
 return {list,bookingShare,detail,create,update,remove,comments,comment,removeComment,like,notifications,readNotification,report,reportList,review};
}
function route(handler){return async(req,res,next)=>{res.set('Cache-Control','private, no-store');try{await handler(req,res);}catch(error){if(error.status)res.status(error.status).json({error:error.code});else next(error);}};}
export function registerFeedRoutes(app,service){
 app.get('/api/feed',route(async(q,s)=>s.json(await service.list(q.userId,q.query))));
 app.get('/api/feed/notifications',route(async(q,s)=>s.json(await service.notifications(q.userId))));
 app.post('/api/feed/notifications/:id/read',route(async(q,s)=>{await service.readNotification(q.userId,q.params.id);s.status(204).end();}));
 app.get('/api/feed/booking-share',route(async(q,s)=>s.json(await service.bookingShare(q.userId,q.query.eventId,q.query.dayIndex))));
 app.get('/api/feed/:id',route(async(q,s)=>s.json(await service.detail(q.userId,q.params.id))));
 app.post('/api/feed',route(async(q,s)=>s.status(201).json(await service.create(q.userId,q.body))));
 app.put('/api/feed/:id',route(async(q,s)=>s.json(await service.update(q.userId,q.params.id,q.body))));
 app.delete('/api/feed/:id',route(async(q,s)=>{await service.remove(q.userId,q.params.id);s.status(204).end();}));
 app.get('/api/feed/:id/comments',route(async(q,s)=>s.json(await service.comments(q.userId,q.params.id,q.query.before))));
 app.post('/api/feed/:id/comments',route(async(q,s)=>s.status(201).json(await service.comment(q.userId,q.params.id,q.body))));
 app.delete('/api/feed/:id/comments/:commentId',route(async(q,s)=>{await service.removeComment(q.userId,q.params.id,q.params.commentId);s.status(204).end();}));
 app.put('/api/feed/:id/like',route(async(q,s)=>s.json(await service.like(q.userId,q.params.id,true))));
 app.delete('/api/feed/:id/like',route(async(q,s)=>s.json(await service.like(q.userId,q.params.id,false))));
 app.post('/api/feed/:id/reports',route(async(q,s)=>s.status(201).json(await service.report(q.userId,q.params.id,q.body))));
}
export function registerFeedAdminRoutes(app,service){
 app.get('/api/admin/feed-reports',route(async(q,s)=>s.json(await service.reportList())));
 app.post('/api/admin/feed-reports/:id/review',route(async(q,s)=>s.json(await service.review(q.userId,q.params.id,q.body))));
}
