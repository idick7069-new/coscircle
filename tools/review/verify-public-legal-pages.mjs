import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import crypto from 'node:crypto';
const {chromium}=await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const output=path.resolve('build/legal-pages-20261119');await fs.mkdir(output,{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
const cases=[['privacy.html','隱私政策 | CosCircle','隱私政策'],['terms.html','使用條款 | CosCircle','使用條款'],['delete-account.html','刪除帳號 | CosCircle','刪除 CosCircle 帳號']];
const checks=[];
try {
 for(const [label,width,height] of [['mobile',390,844],['desktop',1280,900]]) {
  const context=await browser.newContext({viewport:{width,height}});
  for(const [file,title,heading] of cases) {
   const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
   const response=await page.goto('https://coscircle.app/'+file,{waitUntil:'networkidle'});
   assert.equal(response.status(),200);assert.match(response.headers()['content-type'],/text\/html/);
   assert.equal(await page.title(),title);assert.equal(await page.locator('h1').innerText(),heading);
   assert.equal(crypto.createHash('sha256').update(await response.body()).digest('hex'),crypto.createHash('sha256').update(await fs.readFile('web/official/'+file)).digest('hex'));
   const layout=await page.evaluate(()=>({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,lineHeight:getComputedStyle(document.body).lineHeight,images:[...document.images].every(i=>i.complete&&i.naturalWidth>0)}));
   assert(layout.scrollWidth<=layout.width);assert(layout.images);assert(parseFloat(layout.lineHeight)>20);
   if(file==='delete-account.html') {assert(await page.locator('#login-form').isVisible());assert(await page.locator('#delete-form').isHidden());assert(await page.locator('#delete-button').isDisabled());}
   await page.screenshot({path:path.join(output,file.replace('.html','')+'-'+label+'.png'),fullPage:true});
   assert.deepEqual(errors,[]);checks.push({file,viewport:label,status:response.status(),title,noHorizontalOverflow:true,imagesLoaded:true});
   await page.close();
  }
  await context.close();
 }
 const account=JSON.parse(await fs.readFile(process.env.LEGAL_QA_ACCOUNT,'utf8'));
 assert.equal(account.namespace,'public-legal-page-qa');assert(account.email.endsWith('@example.invalid'));
 const context=await browser.newContext({viewport:{width:390,height:844}});const page=await context.newPage();
 await page.goto('https://coscircle.app/delete-account.html',{waitUntil:'networkidle'});
 async function login() {
  await page.locator('#email').fill(account.email);await page.locator('#login-password').fill(account.password);await page.locator('#login-button').click();await page.locator('#delete-form').waitFor({state:'visible'});
  assert((await page.locator('#account-label').innerText()).includes(account.email));
  assert(await page.evaluate(()=>localStorage.length===0&&sessionStorage.length===0));
 }
 await login();await page.locator('#cancel-button').click();assert(await page.locator('#login-form').isVisible());
 await login();await page.locator('#delete-password').fill(account.password);await page.locator('#confirmation').fill('delete');await page.locator('#understood').check();assert(await page.locator('#delete-button').isDisabled());
 await page.locator('#confirmation').fill('DELETE');await page.locator('#delete-password').fill('incorrect-password');
 const wrong=page.waitForResponse(r=>r.url().endsWith('/api/me/delete-account')&&r.request().method()==='POST');await page.locator('#delete-button').click();assert.equal((await wrong).status(),403);
 await page.waitForFunction(()=>document.getElementById('status').textContent.includes('密碼驗證未通過'));
 assert(await page.locator('#delete-form').isVisible());await page.locator('#delete-password').fill(account.password);
 const success=page.waitForResponse(r=>r.url().endsWith('/api/me/delete-account')&&r.request().method()==='POST');await page.locator('#delete-button').click();assert.equal((await success).status(),204);
 await page.locator('#done').waitFor({state:'visible'});assert(await page.locator('#delete-form').isHidden());
 await page.screenshot({path:path.join(output,'delete-complete-mobile.png'),fullPage:true});
 const cannotLogin=await context.request.post('https://coscircle.app/api/auth/login',{data:{email:account.email,password:account.password}});assert.equal(cannotLogin.status(),401);
 await context.close();
 const report={pages:checks,deletion:{disposableAccountOnly:true,cancelPassed:true,confirmationGuardPassed:true,wrongPasswordRejected:true,deletedStatus:204,loginAfterDelete:401,noWebStorageToken:true}};
 await fs.writeFile(path.join(output,'verification.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
} finally {await browser.close();}
