# LINE Login: Android / iOS

## Status

Production API and web deployment completed on 2026-10-08.
Android debug test build is installed on Pixel 9a; existing Email session and the live login-methods page were verified.
The user will complete LINE authorization later. Successful real-account LINE binding/login is not yet verified.
iOS configuration is present, but compilation/install remain blocked by missing full Xcode and an iOS test device.
The SDK exchanges a LINE access token for a CosCircle session through the existing social login endpoint.
The backend verifies the expected channel, token expiry and profile scope before reading the LINE profile.
No email scope is requested; no email-based account merge is performed.
Account identity separation and Email-to-LINE linking are deployed; production DB migration is complete.
Existing Email users sign in with Email, then open Settings > Login methods and bind LINE after password reauthentication.
First LINE login without prior binding creates a separate account. No automatic account merge occurs.
LINE-only users cannot add Email/password yet, because email verification is not available.
Unlinking, multiple-device sessions, email verification, password reset and account merging remain pending.

## Account migration

Back up the production DB before deployment. `backend/db/migrate_auth_identities.sql` creates
`user_auth_identities` and copies existing provider identities without changing `users.id`.
Backend startup also ensures the table and performs the idempotent backfill.
Legacy email identities are not marked verified. The old provider/password fields remain temporarily
for compatibility, but login lookup uses the identity table. Email registration and social registration
write the user and identity within one transaction.
After enabling binding, do not roll back to the old identity-unaware backend: it cannot log into
the original Email account using its newly linked LINE identity. Keep identity-aware rollback releases.
Production LINE login and binding endpoints reject insecure transport.

## LINE Developers Console

Channel ID: `2011925571`.
Enable Mobile app and configure:

| Setting | Value |
| --- | --- |
| Android package name | `com.coscircle.coscircle` |
| iOS bundle ID | `com.coscircle.coscircle` |
| iOS callback scheme (configured in App) | `line3rdp.com.coscircle.coscircle` |

Android package signatures are optional according to the SDK documentation.
If configured, use the actual debug/release certificate fingerprint, and the Play App Signing certificate for Play-distributed builds.
Do not copy a placeholder fingerprint.
Keep Developing status while testing and add testers to the channel.
Web login and web callback URLs are outside this native-mobile implementation.

## Backend / Transport

Set `LINE_LOGIN_CHANNEL_ID=2011925571` in the restricted GCP API environment.
Do not include a Channel Secret in the App; this access-token verification flow does not require it.
Use HTTPS for `API_BASE_URL`. The repository refuses to send LINE tokens over HTTP, even in debug builds.
Production API: `https://34.187.168.222/api`. Source default API also uses HTTPS.
The existing IP was reserved as `coscircle-production-ip`, and port 443 is open only for the web VM tag.
Let’s Encrypt IP certificate is installed at `/etc/letsencrypt/live/coscircle-ip/`.
`coscircle-cert-renew.timer` checks twice daily; renewal dry-run and nginx reload passed.
HTTP remains available for older clients, but production LINE login/binding rejects HTTP, including spoofed forwarding headers.
The native button is gated by `--dart-define=ENABLE_LINE_LOGIN=true` and disabled by default.
Enable only after the backend, HTTPS and LINE Console settings are ready.

## SDK / Platform

Pinned official `flutter_line_sdk` 2.6.2 for the existing Flutter 3.35.6 toolchain.
Android minimum API level is at least 24. iOS retains the existing 13.0 deployment target.
iOS Info.plist includes the callback scheme and `lineauth2` query scheme.
SDK initializes lazily once, before authorization; browser/LINE app routing is managed by the SDK.
Cancellation does not call CosCircle login or create an account.

## Acceptance

Test installed/uninstalled LINE app, canceled/rejected authorization, offline mode,
wrong-channel/expired tokens, first login, repeated login, OOBE resume, and suspended accounts.
Build both native targets and validate return-to-App on physical Android/iOS before release.
LINE support also requires considering Apple's App Review 4.8 login-services requirements before App Store submission.

Verification on 2026-10-08: six new Flutter SDK/transport tests, two existing error-message tests,
and eight backend LINE-verification tests passed. Info.plist syntax and backend syntax checks passed.
Android debug compilation and the full Flutter regression suite were blocked by disk exhaustion
(approximately 51 MB free). iOS compilation was blocked by the missing full Xcode installation;
the selected developer directory is CommandLineTools. No system settings or user files were removed.

Final rollout checks: all 50 Node tests, all 193 Flutter tests and static analysis passed.
Android debug build succeeded after a project-local compileSdk override for LINE SDK 2.6.2.
Only this rollout's Android intermediate build files were removed after preserving/installing the APK to unblock web deployment.
Real LINE authorization remains deferred by the user; iOS remains unbuilt.

## Production rollout record

- Full DB/config backup: `/var/backups/coscircle/20261008-line-084845/` (root-only).
- DB dump SHA-256: `7134cd6c5aca458ade9b1ecbda1b92520100e3a3423f897c969250eb0a4654ae`.
- Original `users` row fingerprint stayed unchanged after migration and initial deployment: 2 users, 2 identities, no missing legacy identity.
- Web release: `20261008165727`.
- Active API release: `20261008165727-auth-patch`.
- Patch changes only `@fastify/busboy` to 3.2.2 and `proxy-addr` to 2.0.8; production npm audit reports zero vulnerabilities.
- GCP runtime Channel ID is configured; CORS permits both existing HTTP origin and the new HTTPS origin.
- Daily activity scheduler was temporarily paused during rollout, then restored.
- External API health and `/app/`, `/admin/` HTTPS checks passed without ignoring certificate validation.
- Invalid LINE token returned 401; HTTP/spoofed-forwarding requests returned 426.
- APK: `build/app/outputs/flutter-apk/app-debug.apk`, installed with `adb install -r` preserving App data. This is a debug test build, not a signed store release.
- LINE-only Email/password addition, email verification and account merging are not enabled.

## Sources

- https://pub.dev/packages/flutter_line_sdk
- https://developers.line.biz/en/docs/line-login/secure-login-process/
- https://developers.line.biz/en/reference/line-login/
- https://developer.apple.com/app-store/review/guidelines/#login-services
