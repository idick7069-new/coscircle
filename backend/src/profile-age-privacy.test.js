import test from 'node:test';
import assert from 'node:assert/strict';
import {agePublicUpdate, publicProfileAge} from './profile-age-privacy.js';

test('private age never appears in the public payload; owner input remains intact', () => {
  const owner = {id: 17, age: '24', agePublic: 0, nickname: 'QA'};
  const result = publicProfileAge(owner);
  assert.equal(result.age, '');
  assert.equal(result.agePublic, false);
  assert.equal(result.nickname, 'QA');
  assert.equal(owner.age, '24');
  assert.ok(!JSON.stringify(result).includes('24'));
});
test('public ages stay visible with both DB and JSON booleans', () => {
  for (const agePublic of [1, true]) assert.equal(publicProfileAge({age:'24',agePublic}).age, '24');
  assert.equal(publicProfileAge({age:'24', agePublic:false}).age, '');
});
test('old clients do not overwrite a privacy choice and invalid values are rejected', () => {
  assert.equal(agePublicUpdate(undefined),null);
  assert.equal(agePublicUpdate(false),0);
  assert.equal(agePublicUpdate(true),1);
  for (const value of ['false','true',0,1,null,{},[]]) assert.throws(()=>agePublicUpdate(value),{code:'invalid_age_public',status:400});
});
