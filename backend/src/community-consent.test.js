import assert from 'node:assert/strict';
import test from 'node:test';
import express from 'express';
import {requiresCommunityConsent, communityConsentGuard} from './community-consent.js';

test('community writes require consent while deletion, safety and reads remain accessible', () => {
  for (const [method, path] of [
    ['PUT','/api/me'], ['POST','/api/uploads/image'], ['POST','/api/works'],
    ['POST','/api/circles'], ['PUT','/api/circles/5/'], ['POST','/api/friend-invites/5'],
    ['POST','/api/events/submissions'], ['POST','/api/events/7/bookings'],
    ['POST','/api/events/7/meetups'], ['PUT','/api/events/7/meetups/3'],
    ['PUT','/api/events/7/location'], ['PUT','/api/events/7/location/coordinates'],
    ['POST','/api/recognitions/8/respond'],
  ]) assert.equal(requiresCommunityConsent(method,path), true, `${method} ${path}`);
  assert.equal(requiresCommunityConsent('PUT', '/API/ME'), true);
  assert.equal(requiresCommunityConsent('POST', '/API/EVENTS/7/BOOKINGS/'), true);
  for (const [method,path] of [
    ['GET','/api/me'], ['POST','/api/me/delete-account'], ['POST','/api/reports'],
    ['POST','/api/me/legal'], ['POST','/api/auth/logout'], ['POST','/api/users/3/block'],
    ['DELETE','/api/events/3/location'], ['POST','/api/admin/reports/4/review'],
    ['POST','/api/me/push-tokens'],
  ]) assert.equal(requiresCommunityConsent(method,path), false, `${method} ${path}`);
});

test('Express case-insensitive routes cannot bypass consent with mixed-case or trailing-slash URLs', async () => {
  for (const path of ['/api/me', '/API/ME', '/api/ME/']) {
    const router = express.Router();
    router.use(communityConsentGuard({status:async()=>({accepted:false})}));
    let published = false;
    router.put('/api/me', (_req,res)=>{ published=true; res.status(204).json({}); });
    const code = await new Promise((resolve,reject)=>{
      const res = {set(){return this;},status(code){this.code=code;return this;},json(){resolve(this.code);}};
      router.handle({method:'PUT', url:path, path, userId:1, get:()=> 'Bearer test-session', headers:{}},res,reject);
    });
    assert.equal(code,403,path);
    assert.equal(published,false,path);
  }
});

test('unaccepted users cannot publish but can report or delete', async () => {
  const guard = communityConsentGuard({status: async () => ({accepted:false})});
  let passed = 0;
  const res = {set(){return this;}, status(code){this.code=code;return this;}, json(body){this.body=body;return this;}};
  await guard({method:'PUT',path:'/api/me', userId:1, get:()=> 'Bearer test-session'},res,(error)=>{
    assert.equal(error, undefined);
    passed++;
  });
  assert.equal(passed,0);
  assert.equal(res.code,403);
  assert.equal(res.body.error,'legal_acceptance_required');
  await guard({method:'POST',path:'/api/reports'},res,()=>passed++);
  await guard({method:'POST',path:'/api/me/delete-account'},res,()=>passed++);
  assert.equal(passed,2);
});
