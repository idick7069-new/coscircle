import {chromium} from '/private/tmp/coscircle-legal-browser/node_modules/playwright/index.mjs';
import assert from 'node:assert/strict';import fs from 'node:fs/promises';import crypto from 'node:crypto';
const dir='build/child-safety-20261119';await fs.mkdir(dir,{recursive:true});
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});const checks=[];
try{
 for(const [label,width,height] of [['mobile',390,844],['desktop',1280,900]]){
  const c=await browser.newContext({viewport:{width,height},javaScriptEnabled:false});
  const p=await c.newPage();const response=await p.goto('https://coscircle.app/child-safety.html',{waitUntil:'networkidle'});
  assert.equal(response.status(),200);assert.match(response.headers()['content-type'],/text\/html/);
  const expected=crypto.createHash('sha256').update(await fs.readFile('web/official/child-safety.html')).digest('hex');const actual=crypto.createHash('sha256').update(await response.body()).digest('hex');assert.equal(actual,expected);
  assert.equal(await p.title(),'兒童安全政策 | CosCircle');assert.equal(await p.locator('h1').innerText(),'兒童安全政策');
  const text=await p.locator('main').innerText();for(const word of ['CosCircle｜同坑認親・場次預定','CSAE','CSAM','grooming','檢舉名片或使用者','檢舉這筆預定','檢舉小圈圈','主管機關','idick7069@gmail.com'])assert(text.includes(word),word);
  const layout=await p.evaluate(()=>({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,lineHeight:parseFloat(getComputedStyle(document.body).lineHeight),images:[...document.images].every(i=>i.complete&&i.naturalWidth>0)}));assert(layout.scrollWidth<=layout.width);assert(layout.lineHeight>20);assert(layout.images);
  assert.equal(await p.locator('a[href^="mailto:idick7069@gmail.com"]').count(),1);
  await p.screenshot({path:dir+'/'+label+'.png',fullPage:true});checks.push({viewport:label,status:200,title:await p.title(),sha256:actual,worksWithoutLoginOrJavaScript:true,layout});await c.close();
 }
 const c=await browser.newContext();for(const name of ['privacy.html','terms.html','delete-account.html']){const response=await c.request.get('https://coscircle.app/'+name);assert.equal(response.status(),200);const body=await response.text();assert(body.includes('href="/child-safety.html"'));assert.equal(crypto.createHash('sha256').update(body).digest('hex'),crypto.createHash('sha256').update(await fs.readFile('web/official/'+name)).digest('hex'));}
 for(const name of ['legal.css','delete-account.js']){const response=await c.request.get('https://coscircle.app/'+name);assert.equal(response.status(),200);assert.equal(crypto.createHash('sha256').update(await response.body()).digest('hex'),crypto.createHash('sha256').update(await fs.readFile('web/official/'+name)).digest('hex'));}
 const health=await c.request.get('https://coscircle.app/api/health');assert.equal(health.status(),200);assert.equal((await health.json()).ok,true);await c.close();
 await fs.writeFile(dir+'/verification.json',JSON.stringify({checks,legalPageLinksAndSourceHashesMatch:true,legalAssetsMatch:true,productionApiHealthy:true},null,2));console.log('PASS: public policy mobile/desktop, no-login/no-JavaScript, exact deployed HTML, layout/images, legal navigation and API health');
}finally{await browser.close()}
