# Resend transactional email

## Current state

The Resend transport, Traditional Chinese verification/reset templates and an
operator-only test tool are implemented. There are no new public send endpoints.
Resend domain verification has been confirmed from the owner's dashboard.
The approved test recipient is `idick7069jp@gmail.com`; the owner confirmed
delivery. The key is saved on GCP with root/coscircle ownership and mode 0640.
Account flows are documented in `email-account-flows.md`.

## Secure initial setup

An isolated operator bundle is staged under `/opt/coscircle/mail-tools/current`
on the production VM. It reuses the existing API's dotenv dependency and does
not switch the API/web release or restart the service. Once staging checks
pass, the owner can run this local launcher in an interactive terminal:

```sh
bash /Users/frank/FlutterProjects/coscircle/deploy/gcp/setup-resend-on-gcp.sh
```

It opens an encrypted SSH terminal on the specified production VM. The owner
pastes the key only at the hidden `Resend API key:` prompt on that VM. The key
is not placed in local files, chat, shell history, process arguments or output.
Do not type it until the prompt is present. The tool sends one test to the
approved recipient, then only after provider acceptance:

- Backs up `/etc/coscircle/api.env` in a root-only backup directory.
- Writes only mail settings, preserving the other production values.
- Stores the key in the root-controlled environment file with its existing
  root/service ownership and restricted read permissions.
- Reports provider acceptance, not inbox delivery or account-flow activation.

If the send is uncertain, rerunning the tool with the same key and recipient
within 23 hours reuses the recorded idempotency key. The root-only retry record
stores a key fingerprint, never the raw key. Verify the inbox/spam folder
before treating delivery as successful. Existing login behavior is unchanged.

### Deployment entry regression

The initial setup silently exited because Node resolved the ESM module to the
release's real path while `process.argv[1]` retained the `current` symlink. The
entry comparison now resolves the argument's real path too. A subprocess
regression test launches the CLI through a symlink and checks that argument
validation actually executes (without touching configuration or sending mail).
Secret-input cancellation now has an explicit diagnostic instead of a silent
shell exit. The initial failed attempt did not persist a key or record a send.

The transport alone does not verify accounts: the account service manages
token storage, expiry, one-time consumption, resend limits and frontend routes.
Do not send templates with invented links or mark users verified just because
an email was accepted. Existing Email users are not automatically verified,
locked out or merged with LINE accounts.

## Account and DNS setup

1. The owner creates/signs into a [Resend account](https://resend.com/).
2. Add `coscircle.app` in Domains and enable sending, not email receiving.
3. Add the exact DNS records supplied by Resend in Cloudflare. Do not guess
   DKIM values, overwrite the website A record, or change apex MX records.
   The SPF/return-path records must use the specific names Resend supplies.
   TXT and MX records are not proxied; any required CNAME must be DNS only.
4. Verify the domain in Resend. Disable click/open tracking for account emails.
5. Create a dedicated sending-only API key restricted to this domain, if the
   dashboard offers these restrictions. Do not share the key in chat or git.
6. Provision the key in the root-controlled `/etc/coscircle/api.env` on GCP.
   Preserve its existing values/ownership, back it up with restricted access,
   and permit only root and the API service account to read the file.

Follow the current [verified domains documentation](https://resend.com/docs/dashboard/domains/introduction)
and [API key documentation](https://resend.com/docs/dashboard/api-keys/introduction).
Domain verification is not a mailbox purchase: `no-reply@coscircle.app` is a
sender, not a monitored support inbox. Do not add a reply-to address until a
real inbox is available.

## Configuration

```env
MAIL_ENABLED=false
MAIL_PROVIDER=resend
MAIL_FROM="CosCircle <no-reply@coscircle.app>"
RESEND_API_KEY=
PUBLIC_APP_URL=https://coscircle.app/app
```

Keep mail disabled until the domain and secret have been provisioned. Set
`MAIL_ENABLED=true` explicitly for the controlled delivery test. Never add
the secret to Flutter defines, client assets, screenshots or command arguments.

Configuration status (does not send, verify DNS or validate the key remotely):

```sh
sudo node /opt/coscircle/api/current/scripts/mail-check.js --status /etc/coscircle/api.env
```

The current production API release contains this command. It only reports
configuration status and does not send an email.

Send a single test to an explicitly approved address, not an arbitrary user:

```sh
sudo node /opt/coscircle/api/current/scripts/mail-check.js --send-test /etc/coscircle/api.env APPROVED_RECIPIENT
```

The test tool prints a request ID, then only the accepted message ID or a
sanitized error. Provider acceptance is not proof of inbox delivery; check the
recipient inbox and Resend delivery status. If delivery is uncertain, retry
with the same recipient and printed request ID as the fourth argument, within
Resend's 24-hour idempotency window. Do not repeatedly generate new IDs.

## Transport guarantees

- Fixed `https://api.resend.com/emails` endpoint; no redirects.
- Ten-second timeout and a mandatory stable idempotency key per message.
- Plain text and HTML versions, with action-link HTML escaping.
- Account links must use HTTPS and exactly match the configured app origin.
- No key, recipient, token URL or provider response body in error messages.
- Disabled/missing configuration fails closed; no fake success or fallback
  sender. Throttling, provider failures and uncertain delivery are distinguished.
- No automatic retries, background sender or unauthenticated send API.

API contract: [Send Email](https://resend.com/docs/api-reference/emails/send-email).

## Local verification

```sh
cd backend
node --test src/mail-service.test.js
node --check scripts/mail-check.js
node scripts/mail-check.js --status .env.production.example
```

All tests stub the provider. No real recipients or external requests are used.
