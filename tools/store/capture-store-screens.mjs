import {chromium} from '/private/tmp/coscircle-legal-browser/node_modules/playwright/index.mjs';
import fs from 'node:fs/promises';
import path from 'node:path';
const root=path.resolve('output/google-play/2026-11-19');
const account=JSON.parse(await fs.readFile('/private/tmp/coscircle-store-capture.json','utf8'));
const owned=new Set(['28','29','30','31']);
const labels=new Map([
 ['Google Play Reviewer（審查測試）','小葵 Aoi'],['Google Play Backup（審查測試）','阿青'],['[審查示範] 希希 Coser','希希 CC'],['[審查示範] 小圈攝影','小圈攝影'],
 ['[審查示範] Google Play Demo — 非真實活動','同好小圈圈交流日'],['[審查示範] Google Play Demo Circle','一起跑場的小圈圈'],['審查測試','同好交流'],['Review demo only / 非真實活動・請勿前往現場','同好廣場'],['Taipei map reference only','台北・同好廣場'],
 ['Review demo booking only / 審查示範，非真實出席','歡迎一起合照，聊聊喜歡的作品！'],['Review demo character / 示範角色','芙莉蓮'],['Review demo photographer','攝影交流'],
 ['Google Play review demo account / 審查示範資料，非真實使用者。Enjoys cosplay events, shared works and photography.','喜歡出角，也喜歡認識同坑的你。下一場，一起跑吧！'],
 ['Review fixtures only; all members are demo accounts.','一起準備出角、分享預定，場次後也保持聯絡。'],['Review demo invitation / 我是示範活動入口旁的攝影，這是審查用邀請。','我是上次在入口一起合照的攝影，下次也一起跑場！'],
 ['我英','葬送的芙莉蓮'],['re0','原神'],['魔法少女小圓','SPY×FAMILY']]);
function transform(x) {
 if(typeof x==='string') return labels.get(x)??x;
 if(Array.isArray(x)) return x.map(transform);
 if(x&&typeof x==='object') {
  const y=Object.fromEntries(Object.entries(x).map(([k,v])=>[k,transform(v)]));
  if(y.inviteCode) {y.inviteCode='COSCIRCLE-DEMO';y.inviteUrl='https://coscircle.app/app/#/join/COSCIRCLE-DEMO';}
  return y;
 }
 return x;
}
const browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
let context,token;
try {
 context=await browser.newContext({viewport:{width:360,height:720},deviceScaleFactor:3,reducedMotion:'reduce'});
 const login=await context.request.post('https://coscircle.app/api/auth/login',{data:{email:account.email,password:account.password}});if(!login.ok())throw new Error('Demo login failed: '+login.status());token=(await login.json()).token;
 let captureEvents;
 await context.route('https://coscircle.app/api/**',async route=>{
  const request=route.request(),u=new URL(request.url()),p=u.pathname;
  if(request.method()!=='GET') {await route.fulfill({status:204});return;}
  const response=await route.fetch();if(!response.ok()){await route.fulfill({response});return;}
  let data;try{data=await response.json();}catch{await route.fulfill({response});return;}
  data=transform(data);
  if(p==='/api/me') {
   const shallow={id:'3',name:'SPY×FAMILY',depth:'shallow'};
   data={...data,profileRoles:['coser','photographer'],shallowPitWorks:[shallow],pitWorks:[...(data.pitWorks??[]),shallow]};
  }
  if(p==='/api/events') {
   const base=data.find(e=>String(e.id)===account.eventId);if(!base)throw new Error('Owned demo event missing');
   const date=base.startDate;const plus=n=>new Date(Date.parse(date+'T00:00:00Z')+86400000*n).toISOString().slice(0,10);
   captureEvents=[{...base,startDate:date,endDate:date,joinedDayIndexes:[1],circleDayIndexes:[1],followedDayIndexes:[1],friendDayIndexes:[1],category:'同人活動',description:'發佈預定、遇見同坑，和熟悉的小圈圈一起出發。'},
    {...base,id:'store-demo-2',name:'週末出角同樂會',startDate:plus(2),endDate:plus(2),isJoined:false,joinedDayIndexes:[],category:'Cosplay活動'},
    {...base,id:'store-demo-3',name:'同坑攝影交流日',startDate:plus(9),endDate:plus(9),isJoined:false,joinedDayIndexes:[],category:'攝影交流'}];data=captureEvents;
  }
  if(p==='/api/me/bookings') data=data.filter(b=>String(b.eventId)===account.eventId&&Number(b.dayIndex)===1);
  if(p.endsWith('/participants')) { data=data.filter(b=>owned.has(String(b.userId))&&Number(b.dayIndex)===1).map(b=>({...b,isMe:String(b.userId)===String(account.id)})); console.log('Demo participant rows', data.length, 'self',data.filter(b=>b.isMe).length); }
  if(['/api/friends','/api/following'].includes(p)) data=data.filter(b=>owned.has(String(b.userId)));
  if(p==='/api/social/same-works'||/^\/api\/social\/partner-works\/[^/]+\/users$/.test(p)) data={...data,items:(data.items??[]).filter(b=>owned.has(String(b.userId))),hasMore:false,nextOffset:null};
  await route.fulfill({response,json:data});
 });
 await context.addInitScript(({token})=>{localStorage.setItem('flutter.auth_token',JSON.stringify(token));localStorage.setItem('flutter.coscircle_pixel_theme_mode_v1',JSON.stringify('neon_dark'));},{token});
 const page=await context.newPage();
 async function ready(){await page.waitForTimeout(1000);await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());await page.waitForTimeout(500);}
 async function go(url){await page.goto('https://coscircle.app/app/#/'+url,{waitUntil:'networkidle'});await ready();}
 async function click(name){const button=page.getByRole('button',{name:new RegExp('^'+name)});await button.last().click({timeout:7000});await page.waitForTimeout(700);}
 async function snap(name){await page.mouse.move(1,1);await page.waitForTimeout(1100);await page.screenshot({path:path.join(root,'raw',name+'.png')});console.log('Captured',name);}
 if(process.env.CAPTURE_SHARE_ONLY){await go('events/'+account.eventId);await page.getByRole('button',{name:/修改預定/}).first().click();await page.waitForTimeout(800);await page.mouse.move(180,450);for(let i=0;i<3;i++){await page.mouse.wheel(0,950);await page.waitForTimeout(700);}await snap('03-booking');}
 if(!process.env.CAPTURE_SHARE_ONLY){
 await go('');await page.mouse.move(180,450);await page.mouse.wheel(0,950);await page.waitForTimeout(1500);await page.mouse.wheel(0,600);await page.waitForTimeout(1200);await snap('02-events');
 await click('名片');await snap('01-profile');
 await click('同好');await snap('05-circle');
 const tabs=page.getByRole('tab');console.log('Tabs',await tabs.allTextContents());
 await page.getByRole('tab',{name:/尋找夥伴/}).click();await page.waitForTimeout(900);await page.getByRole('button',{name:/原神/}).first().click();await page.waitForTimeout(900);await snap('04-fandom');
 await go('events/'+account.eventId);await page.getByRole('button',{name:/修改預定/}).first().click();await page.waitForTimeout(800);await page.mouse.move(180,450);for(let i=0;i<3;i++){await page.mouse.wheel(0,950);await page.waitForTimeout(700);}await snap('03-booking');
 }
 await go('events/'+account.eventId);await page.reload({waitUntil:'networkidle'});await ready();
 const share=page.getByRole('button',{name:/產生預訂分享圖/});
 for(let i=0;i<25 && !(await share.count());i++){await page.mouse.move(180,450);await page.mouse.wheel(0,500);await page.waitForTimeout(500);}
 await share.click();await page.waitForTimeout(1400);await page.mouse.move(180,450);await page.mouse.wheel(0,500);await page.waitForTimeout(700);await snap('06-share');
 await fs.writeFile(path.join(root,'capture-provenance.json'),JSON.stringify({renderer:'Production Flutter Web App',viewport:{width:360,height:720,deviceScaleFactor:3},data:'Owned review demo account; illustrative names and events overridden only in this isolated browser. No production content edits or mutations.',rawSize:[1080,2160],captureDate:'2026-11-19'},null,2));
}finally {
 if(context&&token) await context.request.post('https://coscircle.app/api/auth/logout',{headers:{Authorization:'Bearer '+token},data:{}}).catch(()=>{});
 await browser.close();
}
