# Email verification and password reset

## Behavior

- Email registration queues a verification email without delaying account creation.
- Existing Email users can request verification in Settings > Login methods.
- Verification is currently non-blocking: old users retain access, and there is
  no implicit migration marking old emails verified. New users can complete OOBE
  while waiting for mail. This is not an enforced verified-email signup gate.
- Forgot password is public and returns the same 202 response for every valid
  email, including unknown, suspended and LINE-only accounts. Provider latency
  and account existence do not determine the HTTP response time.
- Only `user_auth_identities.provider='email'` is a recovery identity. Social
  profile emails are never used to create identities, link or merge accounts.
- Verification lasts one hour; reset lasts fifteen minutes. Links are single-use.
- The recipient explicitly confirms verification; GET/navigation does not
  consume links, so ordinary email scanners cannot verify an account.
- Password reset requires matching passwords on the frontend, and 8-1024
  characters on the backend, using the existing salted scrypt format.
- Reset also proves Email ownership, sets the identity's verified timestamp,
  invalidates every pending Email action for that identity, clears the account's
  session token and registered push tokens, and attempts a password-change
  notification. No automatic login follows a reset.
- Bound LINE identities, friendships, profiles and bookings are retained.

## API

Public HTTPS routes, under the existing auth IP limit:

- POST `/api/auth/forgot-password`: `{email}`.
- POST `/api/auth/verify-email`: `{token}`.
- POST `/api/auth/reset-password`: `{token,password}`.

Authenticated HTTPS routes:

- GET `/api/me/email-status`: `{email,verified,available}`.
- POST `/api/me/email-verification`: queues/sends to the stored identity only;
  there is no client-controlled recipient or action URL.

Frontend public routes: `/forgot-password`, `/verify-email`, `/reset-password`.
Mail links use the configured `PUBLIC_APP_URL`, with tokens inside the Flutter
URL fragment (`/app/#/...`) rather than the nginx URL query/access log.

## Storage and abuse controls

Additive migration: `backend/db/migrate_email_actions.sql`. Startup also ensures
this table exists. The table stores a SHA-256 token digest, identity reference,
email snapshot and millisecond issuance/expiry/consumption timestamps. Raw
tokens only exist in memory and outgoing mail, not database records or logs.

Issuance and consumption serialize by locking the owning user first. A token's
purpose, Email snapshot, current identity provider, expiry, unused state and
active account are checked again inside the transaction. Every prior link is
revoked after a successful reset. Merely requesting a new link does not revoke
older valid links or account sessions.

The shared per-identity mail budget is one request per 60 seconds and at most
six per rolling 24 hours, enforced in the DB across restarts/processes. Failed
deliveries still count to prevent quota abuse. Definitive provider rejection
revokes its link; uncertain delivery keeps it valid in case the mail arrives.
Forgot-password throttling does not reveal whether an account exists.

Mail failures never roll back registration or a completed password change.
Background initial/reset sends are best-effort in the running API process, not
a durable outbox. An API restart between acceptance and background delivery
can lose a send; the user can request again after the cooldown. Durable queued
delivery and operational alerts remain a future reliability improvement.

## Deployment and verification

`deploy/gcp/deploy-email-account-on-vm.sh` backs up the full production DB and
restricted environment, clones current API/web releases, applies the additive
table, validates the candidate, then switches API and user Web. TLS/nginx and
Resend secrets are unchanged. On failure, it restores API/web symlinks without
restoring the whole live DB or deleting the additive table.

Local validation uses provider stubs and an isolated SQLite adapter. It covers
hash-only storage, replay, expiry, wrong purpose, changed identities, suspended
accounts, unknown/LINE users, throttling, mail errors, session revocation, and
frontend confirmation/password/cooldown/error states. Production smoke checks
use invalid links and invalid email input; they do not reset a real user's
password or create test users. Actual account confirmation is a user action.

Security reference: [OWASP Forgot Password](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html).

## Production activation 2026-10-13

- API: `/opt/coscircle/api/releases/20261013T064446Z-email-359136`.
- Web: `/var/www/coscircle/releases/20261013T064446Z-email-359136`.
- Backup: `/var/backups/coscircle/20261013T064437Z-email-Bf3NsW`.
- DB backup SHA-256: `9b205c78d5e1eb02f2605eb9d3146dee272c764cd5dbd83743afbb4c4c14ca45`.
- Accounts, identities, sessions, friendships, follows, circle membership and
  bookings matched before/after deployment; the new action table was empty.
- Both domain and IP HTTPS health succeeded. Invalid verification/reset links
  return 400, invalid email returns 400, unauthenticated status returns 401.
- Resend configuration is enabled/configured with no missing fields.
- Deployed app JS matched local SHA-256:
  `664c279c47dc0d2c4d3cfb8914db595f9e9243094833dfe2d88b35f3b98aee95`.
- 219 Flutter tests, 62 Node tests and Flutter analysis passed locally. The
  candidate passed 25 mail/account-service tests on GCP before activation.
- Browser rendering verified public forgot-password and incomplete-link
  verification pages. No provider submissions or real credentials were used.
- Android arm64 debug APK using the production domain was installed with
  `install -r` on Pixel 9a. Its process launched without observed Flutter or
  AndroidRuntime errors. Screen was dozing, so physical-screen confirmation
  awaits owner unlock. iOS/store-signed releases were not built.
