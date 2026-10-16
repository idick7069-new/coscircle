import fs from 'node:fs';
import {randomUUID} from 'node:crypto';
import dotenv from 'dotenv';
import {createMailService} from '../src/mail-service.js';

try {
  const args = process.argv.slice(2);
  const [mode, envFile, to, existingId] = args;
  if (!['--status', '--send-test'].includes(mode) || !envFile ||
      (mode === '--status' && args.length !== 2) ||
      (mode === '--send-test' && (![3, 4].includes(args.length) || !to))) {
    throw Object.assign(new Error(), {code: 'usage: mail-check.js --status ENV_FILE | --send-test ENV_FILE RECIPIENT [REQUEST_ID]'});
  }
  const mail = createMailService({env: dotenv.parse(fs.readFileSync(envFile))});
  if (mode === '--status') {
    console.log(JSON.stringify(mail.status()));
  } else {
    const requestId = existingId || randomUUID();
    console.log(JSON.stringify({requestId}));
    console.log(JSON.stringify(await mail.sendTest({to, requestId})));
  }
} catch (error) {
  console.error(JSON.stringify({error: error.code?.startsWith('mail_') ||
    error.code?.startsWith('invalid_mail_') || error.code?.startsWith('usage:')
    ? error.code : 'mail_check_failed', retryable: error.retryable === true}));
  process.exitCode = 1;
}
