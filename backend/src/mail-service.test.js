import test from 'node:test';
import assert from 'node:assert/strict';
import {createMailService} from './mail-service.js';

const env = {MAIL_ENABLED: 'true', MAIL_PROVIDER: 'resend',
  MAIL_FROM: 'CosCircle <no-reply@coscircle.app>', RESEND_API_KEY: 'test-key-not-a-real-secret',
  PUBLIC_APP_URL: 'https://coscircle.app/app'};
const recipient = 'tester@example.invalid';
const requestId = 'test-request-123';
const actionUrl = 'https://coscircle.app/app/#/verify-email?token=test-only&source=email';
const response = (body, status = 200) => ({ok: status >= 200 && status < 300,
  status, json: async () => body});
const never = () => assert.fail('HTTP must not run');

test('sends through the fixed HTTPS API with auth, timeout and an idempotency key', async () => {
  let call;
  const mail = createMailService({env, fetcher: async (url, options) => {
    call = {url, options}; return response({id: 'message-123'});
  }});
  assert.deepEqual(await mail.sendVerification({to: recipient, actionUrl, requestId}),
    {accepted: true, messageId: 'message-123'});
  assert.equal(call.url, 'https://api.resend.com/emails');
  assert.equal(call.options.method, 'POST');
  assert.equal(call.options.redirect, 'error');
  assert.ok(call.options.signal instanceof AbortSignal);
  assert.equal(call.options.headers.Authorization, `Bearer ${env.RESEND_API_KEY}`);
  assert.equal(call.options.headers['Idempotency-Key'], `coscircle-${requestId}`);
  const body = JSON.parse(call.options.body);
  assert.deepEqual(body.to, [recipient]);
  assert.equal(body.from, env.MAIL_FROM);
  assert.match(body.text, /test-only&source=email/);
  assert.match(body.html, /test-only&amp;source=email/);
  assert.ok(!body.html.includes(env.RESEND_API_KEY));
});

test('password reset has a distinct subject and both HTML and plain text', async () => {
  const mail = createMailService({env, fetcher: async (_, options) => {
    const body = JSON.parse(options.body);
    assert.match(body.subject, /重設/);
    assert.match(body.text, /重設/);
    assert.match(body.html, /重設/);
    return response({id: 'reset-123'});
  }});
  await mail.sendPasswordReset({to: recipient, actionUrl, requestId});
});

test('disabled mail fails closed without sending', async () => {
  const mail = createMailService({env: {...env, MAIL_ENABLED: 'false'}, fetcher: never});
  await assert.rejects(mail.sendTest({to: recipient, requestId}), {code: 'mail_disabled'});
});

for (const field of ['MAIL_PROVIDER', 'MAIL_FROM', 'RESEND_API_KEY', 'PUBLIC_APP_URL']) {
  test(`missing ${field} is reported without leaking secrets`, async () => {
    const mail = createMailService({env: {...env, [field]: ''}, fetcher: never});
    assert.ok(mail.status().missing.includes(field));
    assert.equal(mail.status().configured, false);
    assert.ok(!JSON.stringify(mail.status()).includes(env.RESEND_API_KEY));
    await assert.rejects(mail.sendTest({to: recipient, requestId}), {code: 'mail_not_configured'});
  });
}

test('configuration rejects header injection, unsupported provider and HTTP app URLs', () => {
  for (const invalid of [
    {MAIL_FROM: 'Sender\r\nBcc: secret@example.com'},
    {MAIL_PROVIDER: 'smtp'},
    {RESEND_API_KEY: 'key\nsecret'},
    {PUBLIC_APP_URL: 'http://coscircle.app/app'},
    {PUBLIC_APP_URL: 'https://secret@coscircle.app/app'},
  ]) assert.equal(createMailService({env: {...env, ...invalid}}).status().configured, false);
});

test('recipients must be a single address and message IDs must be header safe', async () => {
  const mail = createMailService({env, fetcher: never});
  for (const to of ['', [recipient], `${recipient},other@example.com`, `a@example.com\r\nBcc: ${recipient}`]) {
    await assert.rejects(mail.sendTest({to, requestId}), {code: 'invalid_mail_recipient'});
  }
  for (const id of ['', undefined, 'bad\r\nheader', 'x'.repeat(129)]) {
    await assert.rejects(mail.sendTest({to: recipient, requestId: id}), {code: 'invalid_mail_request_id'});
  }
});

test('action URLs must stay on the configured HTTPS origin without credentials', async () => {
  const mail = createMailService({env, fetcher: never});
  for (const url of [undefined, 'javascript:alert(1)', 'http://coscircle.app/app',
    'https://coscircle.app.evil.invalid/app', 'https://secret@coscircle.app/app',
    'https://evil.invalid/?next=https://coscircle.app']) {
    await assert.rejects(mail.sendVerification({to: recipient, requestId, actionUrl: url}),
      {code: 'invalid_mail_action_url'});
  }
});

for (const [status, code, retryable] of [
  [401, 'mail_provider_configuration_error', false],
  [403, 'mail_provider_configuration_error', false],
  [422, 'mail_provider_rejected', false],
  [429, 'mail_rate_limited', true],
  [500, 'mail_provider_unavailable', true],
]) test(`HTTP ${status} is sanitized and classified`, async () => {
  const mail = createMailService({env, fetcher: async () => response({message: env.RESEND_API_KEY}, status)});
  await assert.rejects(mail.sendTest({to: recipient, requestId}), {code, message: code, retryable});
});

test('network and malformed success responses have unknown delivery, not false success', async () => {
  for (const fetcher of [
    async () => { throw new Error(`${env.RESEND_API_KEY} ${recipient} ${actionUrl}`); },
    async () => ({ok: true, json: async () => {throw new Error('bad body');}}),
    async () => response({}),
    async () => response({id: {nested: 'invalid'}}),
    async () => response({id: 'unsafe\nmessage'}),
  ]) {
    const mail = createMailService({env, fetcher});
    await assert.rejects(mail.sendTest({to: recipient, requestId}),
      {code: 'mail_delivery_unknown', message: 'mail_delivery_unknown', retryable: true});
  }
});

test('retries preserve the same idempotency key and content', async () => {
  const calls = [];
  const mail = createMailService({env, fetcher: async (_, options) => {
    calls.push(options); return response({id: 'same-message'});
  }});
  await mail.sendTest({to: recipient, requestId});
  await mail.sendTest({to: recipient, requestId});
  assert.equal(calls[0].headers['Idempotency-Key'], calls[1].headers['Idempotency-Key']);
  assert.equal(calls[0].body, calls[1].body);
});
