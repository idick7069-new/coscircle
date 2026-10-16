import fs from 'node:fs';
import crypto from 'node:crypto';
import {pathToFileURL} from 'node:url';
import dotenv from 'dotenv';
import {createMailService} from '../src/mail-service.js';

export function prepareResendEnvironment(content, apiKey) {
  if (!/^re_[A-Za-z0-9_-]{16,200}$/.test(apiKey)) {
    throw Object.assign(new Error('invalid_resend_key'), {code: 'invalid_resend_key'});
  }
  const values = {
    MAIL_ENABLED: 'true', MAIL_PROVIDER: 'resend',
    MAIL_FROM: 'CosCircle <no-reply@coscircle.app>', RESEND_API_KEY: apiKey,
  };
  const parsed = dotenv.parse(content);
  if (parsed.PUBLIC_APP_URL !== 'https://coscircle.app/app') {
    throw Object.assign(new Error('unexpected_app_url'), {code: 'unexpected_app_url'});
  }
  const retained = content.split('\n').filter(line =>
    !Object.keys(values).some(key => new RegExp(`^\\s*(?:export\\s+)?${key}\\s*=`).test(line)));
  const updated = retained.join('\n').trimEnd() + '\n' +
    Object.entries(values).map(([key, value]) => `${key}=${JSON.stringify(value)}`).join('\n') + '\n';
  return {content: updated, env: dotenv.parse(updated)};
}

async function setup() {
  if (process.getuid() !== 0 || process.argv.length !== 3) throw new Error();
  const recipient = process.argv[2];
  if (!/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/.test(recipient)) throw new Error();
  const envPath = '/etc/coscircle/api.env';
  const stat = fs.lstatSync(envPath);
  if (!stat.isFile() || stat.uid !== 0 || (stat.mode & 0o027)) throw new Error();
  let secret = '';
  for await (const chunk of process.stdin) {
    secret += chunk;
    if (secret.length > 256) throw new Error();
  }
  const original = fs.readFileSync(envPath, 'utf8');
  const candidate = prepareResendEnvironment(original, secret.trim());
  const mail = createMailService({env: candidate.env});
  const stateDir = '/var/lib/coscircle/mail-setup';
  fs.mkdirSync(stateDir, {recursive: true, mode: 0o700});
  const stateStat = fs.lstatSync(stateDir);
  if (!stateStat.isDirectory() || stateStat.uid !== 0 || (stateStat.mode & 0o077)) throw new Error();
  const statePath = `${stateDir}/test.json`;
  const fingerprint = crypto.createHash('sha256').update(secret.trim()).digest('hex');
  let previous;
  try { previous = JSON.parse(fs.readFileSync(statePath, 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  // Keep the same request ID on retries within the provider's 24-hour window.
  const reusable = previous?.recipient === recipient && previous?.fingerprint === fingerprint &&
    Number.isFinite(previous.createdAt) && Date.now() - previous.createdAt < 23 * 3600000;
  const state = reusable ? previous : {recipient, fingerprint, createdAt: Date.now(),
    requestId: crypto.randomUUID()};
  fs.writeFileSync(statePath, JSON.stringify(state), {mode: 0o600});
  const result = await mail.sendTest({to: recipient, requestId: state.requestId});
  const backupDir = fs.mkdtempSync('/var/backups/coscircle-resend-');
  fs.chmodSync(backupDir, 0o700);
  fs.writeFileSync(`${backupDir}/api.env`, original, {mode: 0o600});
  const temporary = `${envPath}.resend-${crypto.randomUUID()}`;
  try {
    fs.writeFileSync(temporary, candidate.content, {flag: 'wx', mode: stat.mode & 0o640});
    fs.chownSync(temporary, stat.uid, stat.gid);
    fs.renameSync(temporary, envPath);
  } finally {
    try { fs.unlinkSync(temporary); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  console.log(JSON.stringify({configured: true, ...result, backup: backupDir}));
  console.log('Resend accepted the test email. Check the inbox and spam folder.');
  console.log('No API restart, account verification or password reset was activated.');
}

// Node resolves ESM symlinks; argv retains the deployed `current` path.
if (process.argv[1] && import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href) {
  setup().catch(error => {
    const known = new Set(['invalid_resend_key', 'unexpected_app_url', 'mail_rate_limited',
      'mail_provider_unavailable', 'mail_provider_configuration_error', 'mail_provider_rejected',
      'mail_delivery_unknown', 'invalid_mail_recipient', 'mail_not_configured']);
    console.error(JSON.stringify({error: known.has(error.code) ? error.code : 'resend_setup_failed'}));
    process.exitCode = 1;
  });
}
