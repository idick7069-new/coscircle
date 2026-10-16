import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {prepareResendEnvironment} from './resend-setup.js';

const key = 're_test_only_not_a_real_key_123';
test('CLI invoked through deployment symlinks runs instead of silently exiting', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'resend-entry-test-'));
  try {
    const alias = path.join(directory, 'setup.js');
    fs.symlinkSync(fileURLToPath(new URL('./resend-setup.js', import.meta.url)), alias);
    // Missing arguments must fail before reading secrets, configuration or HTTP.
    const result = spawnSync(process.execPath, [alias], {encoding: 'utf8'});
    assert.equal(result.status, 1, 'CLI must execute its argument checks');
    assert.match(result.stderr, /resend_setup_failed/);
  } finally { fs.rmSync(directory, {recursive: true, force: true}); }
});
test('updates only mail settings while preserving production values', () => {
  const original = 'PUBLIC_APP_URL="https://coscircle.app/app"\nMYSQL_PASSWORD="keep-me"\n# keep comment\nMAIL_ENABLED=false\n';
  const updated = prepareResendEnvironment(original, key);
  assert.equal(updated.env.RESEND_API_KEY, key);
  assert.equal(updated.env.MAIL_ENABLED, 'true');
  assert.equal(updated.env.MAIL_FROM, 'CosCircle <no-reply@coscircle.app>');
  assert.equal(updated.env.MYSQL_PASSWORD, 'keep-me');
  assert.ok(updated.content.includes('# keep comment'));
  assert.equal((updated.content.match(/^MAIL_ENABLED=/gm) || []).length, 1);
});
test('replaces duplicated and exported mail fields instead of accumulating them', () => {
  const result = prepareResendEnvironment('PUBLIC_APP_URL=https://coscircle.app/app\nexport RESEND_API_KEY=old\n RESEND_API_KEY=older\n', key);
  assert.equal(result.env.RESEND_API_KEY, key);
  assert.equal((result.content.match(/^RESEND_API_KEY=/gm) || []).length, 1);
  assert.ok(!result.content.includes('=older'));
});
test('unsafe keys and unexpected app origins are rejected before writing', () => {
  for (const value of ['', 're_short', `${key}\nOTHER=oops`, `${key}"`, 'some-other-service-key']) {
    assert.throws(() => prepareResendEnvironment('PUBLIC_APP_URL=https://coscircle.app/app', value),
      {code: 'invalid_resend_key', message: 'invalid_resend_key'});
  }
  assert.throws(() => prepareResendEnvironment('PUBLIC_APP_URL=http://localhost/app', key),
    {code: 'unexpected_app_url'});
});
