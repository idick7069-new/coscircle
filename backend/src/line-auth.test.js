import test from 'node:test';
import assert from 'node:assert/strict';
import {fetchLineProfile} from './line-auth.js';

const accessToken = 'test-token-not-a-real-secret';
const channelId = '2011925571';
const response = (data, status = 200) => ({ok: status === 200, status, json: async () => data});

test('verifies the expected channel before reading the profile, without trusting client identity', async () => {
  const calls = [];
  const profile = await fetchLineProfile(accessToken, {channelId, fetcher: async (url, options) => {
    calls.push({url: String(url), options});
    return calls.length === 1 ? response({client_id: channelId, expires_in: 60, scope: 'profile'})
      : response({userId: 'LINE-ID', displayName: 'Tester', pictureUrl: 'https://example.invalid/photo'});
  }});
  assert.equal(profile.id, 'LINE-ID');
  assert.equal(profile.email, null);
  assert.equal(calls.length, 2);
  assert.equal(new URL(calls[0].url).searchParams.get('access_token'), accessToken);
  assert.equal(calls[1].options.headers.Authorization, `Bearer ${accessToken}`);
});

for (const token of [
  {client_id: 'other-channel', expires_in: 60, scope: 'profile'},
  {client_id: channelId, expires_in: 0, scope: 'profile'},
  {client_id: channelId, expires_in: 60, scope: 'openid'},
]) test(`invalid token metadata stops before profile lookup: ${JSON.stringify(token)}`, async () => {
  let calls = 0;
  await assert.rejects(fetchLineProfile(accessToken, {channelId, fetcher: async () => {
    calls++; return response(token);
  }}), {code: 'invalid_social_token'});
  assert.equal(calls, 1);
});

test('missing backend channel fails closed without HTTP', async () => {
  await assert.rejects(fetchLineProfile(accessToken, {channelId: '', fetcher: () => assert.fail()}),
    {code: 'line_login_not_configured'});
});

test('provider rejection does not become a successful login', async () => {
  await assert.rejects(fetchLineProfile(accessToken, {channelId, fetcher: async () => response({}, 401)}),
    {code: 'invalid_social_token'});
});

test('network errors are sanitized so access tokens cannot leak in exception logs', async () => {
  await assert.rejects(fetchLineProfile(accessToken, {channelId, fetcher: async () => {
    throw new Error(`request failed ${accessToken}`);
  }}), {code: 'line_login_unavailable', message: 'line_login_unavailable'});
});

test('missing identity and malformed responses fail closed', async () => {
  let calls = 0;
  await assert.rejects(fetchLineProfile(accessToken, {channelId, fetcher: async () => ++calls === 1
    ? response({client_id: channelId, expires_in: 60, scope: 'profile'}) : response({})}),
  {code: 'invalid_social_token'});
  await assert.rejects(fetchLineProfile(accessToken, {channelId, fetcher: async () => ({ok: true,
    json: async () => {throw new Error('bad json');}})}), {code: 'line_login_unavailable'});
});
