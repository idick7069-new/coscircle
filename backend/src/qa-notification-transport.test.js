import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import test from 'node:test';
import {createPool} from './db.js';
import {sendPushBatches} from './push-service.js';

test('new database sessions queue UTC initialization before application commands', () => {
  const pool = new EventEmitter();
  const driver = {createPool(options) {assert.equal(options.timezone, 'Z'); return pool;}};
  assert.equal(createPool(driver), pool);
  const queries = [];
  let destroyed = false;
  pool.emit('connection', {
    query(sql, callback) {queries.push(sql); callback(null);},
    destroy() {destroyed = true;},
  });
  assert.deepEqual(queries, ["SET time_zone = '+00:00'"]);
  assert.equal(destroyed, false);
  pool.emit('connection', {
    query(_, callback) {callback(new Error('cannot initialize'));},
    destroy() {destroyed = true;},
  });
  assert.equal(destroyed, true);
});

test('501 push recipients split at the SDK limit and retain invalid-token identity', async () => {
  const sizes = [];
  const result = await sendPushBatches(Array.from({length: 501}, (_, id) => ({token: `token-${id}`})), {
    async sendEach(batch) {
      assert.ok(batch.length <= 500);
      sizes.push(batch.length);
      return {
        successCount: batch.length - 1, failureCount: 1,
        responses: batch.map((_, i) => i === batch.length - 1
          ? {error: {code: 'messaging/registration-token-not-registered'}} : {success: true}),
      };
    },
  });
  assert.deepEqual(sizes, [500, 1]);
  assert.deepEqual(result, {successCount: 499, failureCount: 2, invalidTokens: ['token-499', 'token-500']});
});

test('a failed push batch does not prevent later recipients from being attempted', async () => {
  let calls = 0;
  const result = await sendPushBatches(Array.from({length: 1001}, (_, id) => ({token: `${id}`})), {
    async sendEach(batch) {
      if (++calls === 1) throw new Error('temporary transport failure');
      return {successCount: batch.length, failureCount: 0, responses: batch.map(() => ({success: true}))};
    },
  });
  assert.equal(calls, 3);
  assert.deepEqual(result, {successCount: 501, failureCount: 500, invalidTokens: []});
});
