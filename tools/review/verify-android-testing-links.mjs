import {chromium} from '/private/tmp/coscircle-legal-browser/node_modules/playwright/index.mjs';
import assert from 'node:assert/strict';import fs from 'node:fs/promises';import crypto from 'node:crypto';
const output='build/android-testing-links-20261119';await fs.mkdir(output,{recursive:true});
const opt='https://play.google.com/apps/testing/com.hikakineame.coscircle',store='https://play.google.com/store/apps/details?id=com.hikakineame.coscircle';
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});const results=[];
try{
 for(const [label,width,height,js] of [['mobile',390,844,true],['desktop',1280,900,true],['no-js',390,844,false]]){
  const c=await browser.newContext({viewport:{width,height},javaScriptEnabled:js});
  for(const [url,file] of [['/','index.html'],['/android-testing.html','android-testing.html']]){
   const p=await c.newPage();const errors=[];p.on('pageerror',e=>errors.push(e.message));const r=await p.goto('https://coscircle.app'+url,{waitUntil:'networkidle'});assert.equal(r.status(),200);
   assert.equal(crypto.createHash('sha256').update(await r.body()).digest('hex'),crypto.createHash('sha256').update(await fs.readFile('web/official/'+file)).digest('hex'));
   for(const href of [opt,store]){const a=p.locator(`a[href="${href}"]`).first();assert(await a.isVisible());assert.equal(await a.getAttribute('target'),'_blank');assert((await a.getAttribute('rel')).includes('noopener'));}
   const body=await p.locator('body').innerText();assert(!body.includes('Android 測試即將開放'));assert(!body.includes('測試邀請連結準備中'));assert(body.includes('以 Google Play 顯示為準'));
   const layout=await p.evaluate(()=>({width:innerWidth,scrollWidth:document.documentElement.scrollWidth}));assert(layout.scrollWidth<=layout.width);assert.deepEqual(errors,[]);
   await p.screenshot({path:output+'/'+label+'-'+file+'.png',fullPage:file!=='index.html'});results.push({viewport:label,page:url,status:200,linksVisible:true,exactHtml:true,noOverflow:true});await p.close();
  }
  await c.close();
 }
 const c=await browser.newContext();const r=await c.request.get('https://coscircle.app/official/android-testing.json?v=20261119-2');assert.equal(r.status(),200);const config=await r.json();assert.equal(config.optIn,opt);assert.equal(config.store,store);assert.equal(config.enroll,null);
 const p=await c.newPage();await p.goto('https://coscircle.app/android-testing.html',{waitUntil:'networkidle'});
 const opened=[];for(const href of [opt,store]){const waiting=c.waitForEvent('page');await p.locator(`a[href="${href}"]`).click();const tab=await waiting;await tab.waitForURL(url=>/^(play\.google\.com|accounts\.google\.com)$/.test(url.hostname),{timeout:20000});opened.push({requested:href,openedHost:new URL(tab.url()).hostname});await tab.close();}
 await c.close();await fs.writeFile(output+'/verification.json',JSON.stringify({results,configurationMatches:true,opened,googleAccountEligibilityNotVerified:true},null,2));console.log('PASS: exact public HTML, both links on homepage/guide, mobile/desktop/no-JS, no overflow, live config and Google destination tabs.');
}finally{await browser.close()}
