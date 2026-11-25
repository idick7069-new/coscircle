import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import crypto from 'node:crypto';
import {createLineWebLogin} from './line-web-login.js';
const origin='https://coscircle.app';
const sha=x=>crypto.createHash('sha256').update(x).digest('hex');
function fixture(overrides={}) {
 const db=new DatabaseSync(':memory:');
 let sql=readFileSync(new URL('../db/migrate_line_web_login.sql',import.meta.url),'utf8');
 db.exec(sql.replace(/ CHARACTER SET \w+| COLLATE \w+/g,'').replace(/ENUM\([^)]*\)/g,'TEXT').replace(/^\s*KEY .*\n/gm,'').replace(/,\s*\)/g,')').replace(/ ENGINE=InnoDB/g,''));
 const pool={async execute(query,params=[]){
  query=query.replace(/DATE_ADD\(UTC_TIMESTAMP\(\), INTERVAL 10 MINUTE\)/g,"datetime('now','+10 minutes')").replace(/DATE_ADD\(UTC_TIMESTAMP\(\), INTERVAL 1 MINUTE\)/g,"datetime('now','+1 minute')").replace(/DATE_ADD\(UTC_TIMESTAMP\(\), INTERVAL 5 MINUTE\)/g,"datetime('now','+5 minutes')").replace(/UTC_TIMESTAMP\(\)/g,"datetime('now')");
  const statement=db.prepare(query);return statement.columns().length?[statement.all(...params)]:[{affectedRows:Number(statement.run(...params).changes)}];
 }};
 const requests=[];let currentNonce;
 const service=createLineWebLogin(pool,{enabled:true,channelId:'1234567890',channelSecret:'test-only-channel-secret',origin,
  authenticateLine:async profile=>({token:'coscircle-session',user:{id:profile.id},isNewUser:false}),
  fetcher:async(url,options)=>{
   requests.push({url:String(url),options});
   const body=String(url).endsWith('/token')?{access_token:'line-access-token',id_token:'line-id-token'}:
    String(url).includes('verify?')?{client_id:'1234567890',expires_in:60,scope:'profile'}:
    String(url).endsWith('/profile')?{userId:'line-user',displayName:'CC'}:
    {sub:'line-user',aud:'1234567890',nonce:currentNonce,iss:'https://access.line.me',exp:Date.now()/1000+60};
   return {ok:true,json:async()=>body};
  },...overrides});
 const req=(cookie='',query={},reqOrigin=origin)=>({secure:true,userId:5,query,body:{returnPath:'/events/123'},get:key=>({cookie,origin:reqOrigin,authorization:'Bearer original-session'})[key]});
 const response=()=>({cookies:[],append(_,value){this.cookies.push(value);},redirect(status,url){this.status=status;this.url=url;}});
 return {db,service,requests,req,response,setNonce:n=>currentNonce=n};
}
async function start(f) {
 const res=f.response();const {url}=await f.service.start(f.req(),res);const authorization=new URL(url);
 f.setNonce(authorization.searchParams.get('nonce'));
 return {authorization,cookie:res.cookies[0].split(';')[0]};
}
test('web start uses secure browser binding, state, nonce, PKCE and fixed redirect',async()=>{
 const f=fixture();const {authorization,cookie}=await start(f);
 assert.equal(authorization.origin,'https://access.line.me');
 assert.equal(authorization.searchParams.get('redirect_uri'),origin+'/api/auth/line/web/callback');
 assert.equal(authorization.searchParams.get('code_challenge_method'),'S256');
 const row=f.db.prepare('SELECT * FROM line_web_logins').get();
 assert.equal(row.state_hash,sha(authorization.searchParams.get('state')));
 assert.equal(authorization.searchParams.get('code_challenge'),crypto.createHash('sha256').update(row.verifier).digest('base64url'));
 assert(!cookie.includes(row.verifier));
});
test('callback verifies tokens and nonce, complete consumes browser-bound result once',async()=>{
 const f=fixture();const {authorization,cookie}=await start(f);const res=f.response();
 await f.service.callback(f.req(cookie,{state:authorization.searchParams.get('state'),code:'auth-code'}),res);
 assert.equal(res.status,303);assert.equal(new URL(res.url).search,'');assert(!res.url.includes('line-access-token'));
 assert(!res.url.includes('coscircle-session'));
 const completed=await f.service.complete(f.req(cookie),f.response());assert.equal(completed.user.id,'line-user');
 await assert.rejects(f.service.complete(f.req(cookie),f.response()),{code:'line_login_expired'});
 assert.equal(f.requests.length,4);
 assert(f.requests[0].options.body.get('code_verifier'));
});
test('wrong state, wrong browser and callback replay never authenticate',async()=>{
 const f=fixture();const {authorization,cookie}=await start(f);
 await assert.rejects(f.service.callback(f.req(cookie,{state:'a'.repeat(64),code:'x'}),f.response()),{code:'invalid_line_state'});
 await assert.rejects(f.service.callback(f.req('',{state:authorization.searchParams.get('state'),code:'x'}),f.response()),{code:'invalid_line_state'});
 await f.service.callback(f.req(cookie,{state:authorization.searchParams.get('state'),code:'x'}),f.response());
 await assert.rejects(f.service.callback(f.req(cookie,{state:authorization.searchParams.get('state'),code:'x'}),f.response()),{code:'invalid_line_state'});
});
test('expired attempts and missing browser proof reject completion',async()=>{
 const f=fixture();const {cookie}=await start(f);f.db.exec("UPDATE line_web_logins SET phase='complete',expires_at='2000-01-01'");
 await assert.rejects(f.service.complete(f.req(cookie),f.response()),{code:'line_login_expired'});
 await assert.rejects(f.service.complete(f.req(),f.response()),{code:'line_login_expired'});
});
test('origin and HTTPS required; configuration fails closed',async()=>{
 const f=fixture();await assert.rejects(f.service.start(f.req('','','https://foreign.invalid'),f.response()),{code:'invalid_login_origin'});
 const req=f.req();req.secure=false;await assert.rejects(f.service.start(req,f.response()),{code:'secure_transport_required'});
 const unavailable=fixture({channelSecret:''});assert.equal(unavailable.service.config().webEnabled,false);
 await assert.rejects(unavailable.service.start(unavailable.req(),unavailable.response()),{code:'line_login_not_configured'});
});
test('cancellation and wrong nonce redirect safely without creating an account',async()=>{
 for(const cancel of [true,false]) {
  const f=fixture();const {authorization,cookie}=await start(f);f.setNonce('wrong');const res=f.response();
  await f.service.callback(f.req(cookie,{state:authorization.searchParams.get('state'),...(cancel?{error:'access_denied'}:{code:'x'})}),res);
  assert(res.url.includes('line=failed'));assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM line_web_logins').get().n,0);
 }
});

async function authorizedLink(f) {
 const response=f.response();const {url}=await f.service.startLink(f.req(),response);
 const authorization=new URL(url);f.setNonce(authorization.searchParams.get('nonce'));
 const cookie=response.cookies[0].split(';')[0];const callback=f.response();
 await f.service.callback(f.req(cookie,{state:authorization.searchParams.get('state'),code:'code'}),callback);
 assert(callback.url.startsWith(origin+'/app/#/login-methods?line=complete'));
 return cookie;
}
test('Web linking reuses original account, requires password, and never starts a login session',async()=>{
 let links=0;
 const f=fixture({authenticateLine:()=>assert.fail('link must not log in or register'),
  linkLine:async options=>{assert.deepEqual(options,{userId:5,lineUserId:'line-user',password:'original-password'});links++;return {linked:true};}});
 const cookie=await authorizedLink(f);
 const row=f.db.prepare('SELECT * FROM line_web_logins').get();
 assert.equal(row.purpose,'link');assert.equal(row.link_user_id,5);assert.equal(row.link_session_hash,sha('original-session'));
 const req=f.req(cookie);req.body={password:'original-password'};
 assert.deepEqual(await f.service.completeLink(req,f.response()),{linked:true});assert.equal(links,1);
 await assert.rejects(f.service.completeLink(req,f.response()),{code:'line_login_expired'});
});
test('login and link completion cannot be interchanged',async()=>{
 const f=fixture({authenticateLine:()=>assert.fail('must not authenticate'),linkLine:()=>assert.fail('must not link')});
 const cookie=await authorizedLink(f);
 await assert.rejects(f.service.complete(f.req(cookie),f.response()),{code:'line_link_session_changed'});
 const g=fixture();const login=await start(g);await g.service.callback(g.req(login.cookie,{state:login.authorization.searchParams.get('state'),code:'x'}),g.response());
 await assert.rejects(g.service.completeLink(g.req(login.cookie),g.response()),{code:'line_link_session_changed'});
});
test('changed account or changed session cannot complete an earlier link',async()=>{
 const f=fixture({linkLine:()=>assert.fail('must not link')});const cookie=await authorizedLink(f);
 for(const sameUser of [true,false]) {
  const req=f.req(cookie);req.body={password:'correct'};
  if(sameUser) {const get=req.get;req.get=key=>key==='authorization'?'Bearer different-session':get(key);} else req.userId=9;
  await assert.rejects(f.service.completeLink(req,f.response()),{code:'line_link_session_changed'});
 }
});
test('linking needs authenticated browser, HTTPS, exact origin and password',async()=>{
 const f=fixture({linkLine:()=>assert.fail('must not link')});
 const anonymous=f.req();delete anonymous.userId;
 await assert.rejects(f.service.startLink(anonymous,f.response()),{code:'authentication_required'});
 await assert.rejects(f.service.startLink(f.req('','','https://foreign.invalid'),f.response()),{code:'invalid_login_origin'});
 const insecure=f.req();insecure.secure=false;
 await assert.rejects(f.service.startLink(insecure,f.response()),{code:'secure_transport_required'});
 const cookie=await authorizedLink(f);
 await assert.rejects(f.service.completeLink(f.req(cookie),f.response()),{code:'reauthentication_required'});
});
test('wrong password and conflicting LINE cannot become a new account or a login',async()=>{
 for(const code of ['reauthentication_required','line_identity_already_linked','account_suspended']) {
  const f=fixture({authenticateLine:()=>assert.fail('must not log in'),linkLine:async()=>{throw Object.assign(new Error(code),{code});}});
  const cookie=await authorizedLink(f);const req=f.req(cookie);req.body={password:'wrong'};
  await assert.rejects(f.service.completeLink(req,f.response()),{code});
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM line_web_logins').get().n,0);
 }
});

test('expired linking does not return an invalid-session status or change the account',async()=>{
 const f=fixture({linkLine:()=>assert.fail('expired link')});const cookie=await authorizedLink(f);
 f.db.exec("UPDATE line_web_logins SET expires_at='2000-01-01'");
 await assert.rejects(f.service.completeLink(f.req(cookie),f.response()),{code:'line_login_expired',status:410});
});
