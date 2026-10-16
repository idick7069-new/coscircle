import assert from 'node:assert/strict';
import os from 'node:os';
import test from 'node:test';
import { fetchSourceHtml } from './curl-fetch.js';

const url = 'https://www.doujin.com.tw/events/alist/all';
const success = { status: 200, headers: { 'content-type': 'text/html; charset=UTF-8' }, data: '<html>events</html>' };

test('local requests stop before starting Python', async (context) => {
  context.mock.method(os, 'hostname', () => 'frank-macbook');
  let calls = 0;
  await assert.rejects(fetchSourceHtml(url, { execute: async () => { calls += 1; } }), {
    code: 'gcp_only_source_fetch',
  });
  assert.equal(calls, 0);
});

test('GCP passes the URL as a process argument and returns HTML', async (context) => {
  context.mock.method(os, 'hostname', () => 'coscircle-free-vm');
  const result = await fetchSourceHtml(url, { execute: async (python, args, options) => {
    assert.ok(python);
    assert.ok(python.endsWith('/.crawler-venv/bin/python') || process.env.EVENT_SCRAPER_PYTHON);
    assert.ok(args[0].endsWith('/curl-fetch.py'));
    assert.equal(args[1], url);
    assert.equal(options.timeout, 190000);
    return { stdout: JSON.stringify(success) };
  } });
  assert.equal(result, success.data);
});

test('403 diagnostics identify website challenges', async (context) => {
  context.mock.method(os, 'hostname', () => 'coscircle-free-vm');
  for (const [response, origin, codes] of [
    [{ ...success, status: 403, headers: { 'cf-mitigated': 'challenge', server: 'cloudflare' }, data: '<title>Just a moment...</title>' }, 'cloudflare-challenge', []],
    [{ ...success, status: 403, data: '<title>Forbidden</title>' }, 'unknown', []],
  ]) {
    await assert.rejects(fetchSourceHtml(url, { execute: async () => ({ stdout: JSON.stringify(response) }) }), (error) => {
      assert.equal(error.response.diagnostics.origin, origin);
      assert.deepEqual(error.response.diagnostics.providerErrorCodes, codes);
      return true;
    });
  }
});

test('HTTP errors and challenges retain source diagnostics without browser fallback', async (context) => {
  context.mock.method(os, 'hostname', () => 'coscircle-free-vm');
  for (const response of [
    { ...success, status: 403, headers: { 'cf-mitigated': 'challenge', 'cf-ray': 'test-ray' } },
    { ...success, status: 200, headers: { 'cf-mitigated': 'challenge' } },
    { ...success, data: '<title>Just a moment...</title>' },
    { ...success, status: 429 },
    { ...success, status: 302 },
  ]) {
    await assert.rejects(fetchSourceHtml(url, { execute: async () => ({ stdout: JSON.stringify(response) }) }), (error) => {
      assert.equal(error.response.status, response.status);
      assert.deepEqual(error.response.headers, response.headers);
      return true;
    });
  }
});

test('configuration, process and malformed-response failures do not launch a browser', async (context) => {
  context.mock.method(os, 'hostname', () => 'coscircle-free-vm');
  for (const [execute, code] of [
    [async () => ({ stdout: '{"error":"curl_cffi_dependency_missing"}' }), 'curl_cffi_dependency_missing'],
    [async () => ({ stdout: '{"error":"curl_zenrows_config_required"}' }), 'curl_zenrows_config_required'],
    [async () => ({ stdout: '{"error":"curl_zenrows_http_error","providerStatus":401}' }), 'curl_zenrows_http_error'],
    [async () => { throw new Error('ENOENT'); }, 'curl_source_transport_failed'],
    [async () => ({ stdout: 'invalid JSON' }), 'curl_source_transport_failed'],
    [async () => ({ stdout: '{}' }), 'curl_source_invalid_response'],
    [async () => ({ stdout: JSON.stringify({ ...success, headers: { 'content-type': 'application/json' } }) }), 'curl_source_not_html'],
  ]) {
    await assert.rejects(fetchSourceHtml(url, { execute }), (error) => {
      assert.equal(error.code, code);
      return true;
    });
  }
});
