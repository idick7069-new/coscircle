import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {securityBoundary,setAudience,currentAudience,visibleRow,sessionDigest,canonicalMediaUrl,audienceGuard} from './release-security.js';
import {createPrivateMedia,mayReadMedia} from './private-media.js';
import {browserSessionBoundary} from './browser-session.js';

const run=(user,work)=>new Promise((resolve,reject)=>securityBoundary({get:()=>undefined},{set(){}},()=>{setAudience(user);Promise.resolve().then(work).then(resolve,reject);}));
test('request scopes never share review permissions across simultaneous users',async()=>{
 const outputs=await Promise.all([run({id:1,can_view_test_data:1},async()=>{await new Promise(r=>setImmediate(r));return visibleRow('u');}),run({id:2},async()=>{await new Promise(r=>setImmediate(r));return visibleRow('u');})]);
 assert(!outputs[0].includes('is_test_account=FALSE'));assert(outputs[1].includes('is_test_account=FALSE'));
 assert(visibleRow('u').includes('is_test_account=FALSE'));assert.throws(()=>visibleRow('u;DROP TABLE users'));
});
test('session digests preserve existing secrets without making a stolen database digest usable',()=>{
 const raw='a'.repeat(64),digest=sessionDigest(raw);assert.notEqual(digest,raw);assert.equal(digest,sessionDigest(raw));assert.notEqual(sessionDigest(digest),digest);assert.equal(sessionDigest(''),null);
});
test('signed URLs never get persisted as permanent media references',()=>{
 assert.equal(canonicalMediaUrl('https://coscircle.app/uploads/12345678-1234-4123-8123-123456789012.png?e=99&s=signature'),'https://coscircle.app/uploads/12345678-1234-4123-8123-123456789012.png');
 assert.equal(canonicalMediaUrl('https://evil.example/uploads/a.png?x=1'),'https://evil.example/uploads/a.png?x=1');
});
test('private references enforce circle membership, blocking, suspension and review audience',()=>{
 const owner={id:2,account_status:'active',booking_visibility:'circle',is_test_account:0};
 const state={owner,viewer:{userId:1},publicReference:false,bookingReference:true,circleMember:false,blocked:false};
 assert.equal(mayReadMedia(state),false);assert.equal(mayReadMedia({...state,circleMember:true}),true);
 assert.equal(mayReadMedia({...state,circleMember:true,blocked:true}),false);
 assert.equal(mayReadMedia({...state,owner:{...owner,account_status:'suspended'},circleMember:true}),false);
 assert.equal(mayReadMedia({...state,owner:{...owner,is_test_account:1},publicReference:true}),false);
 assert.equal(mayReadMedia({...state,owner:{...owner,is_test_account:1},viewer:{userId:1,includeTestData:true},circleMember:true}),true);
});
function mediaFixture(t){
 const db=new DatabaseSync(':memory:');t.after(()=>db.close());
 db.function('UTC_TIMESTAMP',()=> '2026-11-24 00:00:00');
 db.function('JSON_CONTAINS',(array,value)=>Number(JSON.parse(array).includes(JSON.parse(value))));
 db.exec(`CREATE TABLE users(id INTEGER PRIMARY KEY,is_admin INTEGER DEFAULT 0,is_test_account INTEGER DEFAULT 0,can_view_test_data INTEGER DEFAULT 0,account_status TEXT DEFAULT 'active',session_token TEXT,session_expires_at TEXT DEFAULT '2099-01-01',booking_visibility TEXT DEFAULT 'circle',avatar_url TEXT DEFAULT '',other_photo_urls_json TEXT DEFAULT '[]');
 CREATE TABLE account_uploads(file_name TEXT,user_id INTEGER);CREATE TABLE events(id INTEGER,status TEXT,is_test_event INTEGER DEFAULT 0,image_url TEXT);CREATE TABLE event_bookings(user_id INTEGER,event_id INTEGER,outfit_image_url TEXT);CREATE TABLE circle_members(user_id INTEGER,circle_id INTEGER);CREATE TABLE user_blocks(blocker_user_id INTEGER,blocked_user_id INTEGER);
 INSERT INTO users(id,session_token)VALUES(1,'digest-1'),(2,'digest-2'),(3,'digest-3');INSERT INTO events(id,status,is_test_event) VALUES(10,'approved',0);`);
 const name='12345678-1234-4123-8123-123456789012.png',url='https://coscircle.app/uploads/'+name;
 db.prepare('INSERT INTO account_uploads VALUES(?,2)').run(name);db.prepare('INSERT INTO event_bookings VALUES(2,10,?)').run(url);
 const pool={execute:async(sql,params=[])=>[db.prepare(sql).all(...params.map(v=>typeof v==='boolean'?Number(v):v))]};
 let now=1800000000000;
 const media=createPrivateMedia(pool,{key:Buffer.alloc(32,1).toString('base64'),uploadDir:'/private/media',now:()=>now});
 const response=()=>({code:200,headers:{},set(v){Object.assign(this.headers,v);return this;},sendStatus(n){this.code=n;return this;},sendFile(file){this.file=file;return this;}});
 const download=async(signed)=>{const u=new URL(signed);const res=response();await media.download({params:{file:name},query:Object.fromEntries(u.searchParams)},res);return res;};
 return {db,pool,media,url,download,advance:ms=>now+=ms};
}
test('private images reject unsigned, tampered, expired and revoked grants; valid circle grants are no-store',async t=>{
 const f=mediaFixture(t);assert.equal(await f.media.grant(f.url,{id:1,session_token:'digest-1'}),'');
 f.db.exec('INSERT INTO circle_members VALUES(1,5),(2,5)');
 const signed=await f.media.grant(f.url,{id:1,session_token:'digest-1'});assert(signed.includes('?e='));
 assert.equal((await f.download(f.url)).code,404);assert.equal((await f.download(signed.replace('s=','s=0'))).code,404);
 const allowed=await f.download(signed);assert.equal(allowed.code,200);assert.match(allowed.headers['Cache-Control'],/no-store/);
 f.db.exec("UPDATE users SET session_token='revoked' WHERE id=1");assert.equal((await f.download(signed)).code,404);
 const renewed=await f.media.grant(f.url,{id:1,session_token:'revoked'});f.advance(301000);assert.equal((await f.download(renewed)).code,404);
});
test('ordinary requests cannot address fixture resources by guessing IDs while reviewers retain access',async t=>{
 const pool={execute:async()=>[[{fixture:1,account_status:'active'}]]};
 await assert.rejects(run({id:1},()=>audienceGuard(pool,{path:'/api/events/617/participants'})),{status:404});
 await run({id:2,can_view_test_data:1},()=>audienceGuard(pool,{path:'/api/events/617/participants'}));
});
test('browser logins deliver an HttpOnly cookie and omit the raw bearer secret from JSON',()=>{
 const headers={'origin':'https://coscircle.app','x-coscircle-client':'web'};const req={method:'POST',get:n=>headers[n]};
 const res={headers:{},append(k,v){this.headers[k]=v;},json(body){this.body=body;return this;}};
 browserSessionBoundary(req,res,()=>{});res.json({token:'a'.repeat(64),user:{id:1}});
 assert.equal(res.body.token,'cookie-session');assert.match(res.headers['Set-Cookie'],/Secure; HttpOnly; SameSite=Strict/);
});
