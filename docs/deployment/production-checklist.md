# Production checklist

Use this checklist before publishing CosCircle to real users. It focuses on
privacy, Android release safety, backend security, and repeatable validation.

## 1. Required production values

- Real API origin, for example `https://api.example.com/api`.
- HTTPS certificate terminated by the hosting platform or reverse proxy.
- MySQL host, database, and an app-only MySQL user with a long random password.
- Android signing keystore in `android/key.properties`.
- Google Maps Android API key passed with `-PGOOGLE_MAPS_API_KEY=...`.
- Browser origins allowed to call the API in `CORS_ORIGINS`.

Do not use the development LAN API, sample MySQL password, or a debug APK for
external testers.

## 2. Database setup

For a new production database, import the schema first:

```sh
mysql -h <host> -u <user> -p <database> < backend/db/schema.sql
```

For an existing database, run every migration that has not been applied yet:

```sh
mysql -h <host> -u <user> -p <database> < backend/db/migrate_auth.sql
mysql -h <host> -u <user> -p <database> < backend/db/migrate_user_public_code.sql
mysql -h <host> -u <user> -p <database> < backend/db/migrate_user_admin.sql
mysql -h <host> -u <user> -p <database> < backend/db/migrate_profile_extended_fields.sql
mysql -h <host> -u <user> -p <database> < backend/db/migrate_event_media.sql
mysql -h <host> -u <user> -p <database> < backend/db/migrate_works.sql
mysql -h <host> -u <user> -p <database> < backend/db/migrate_event_attendance.sql
mysql -h <host> -u <user> -p <database> < backend/db/migrate_event_booking_days.sql
mysql -h <host> -u <user> -p <database> < backend/db/migrate_circle_description.sql
mysql -h <host> -u <user> -p <database> < backend/db/migrate_event_address_and_manager.sql
mysql -h <host> -u <user> -p <database> < backend/db/migrate_privacy_controls.sql
mysql -h <host> -u <user> -p <database> < backend/db/migrate_beta_roadmap.sql
```

After `migrate_user_admin.sql`, verify that only the intended account is admin.
The migration promotes `users.id = 1`; adjust production data manually if that
is not the operator account.

Privacy migration verification:

```sql
SHOW COLUMNS FROM users LIKE 'booking_visibility';
SHOW COLUMNS FROM shared_locations LIKE 'visibility';
SHOW COLUMNS FROM shared_locations LIKE 'expires_at';
SHOW TABLES LIKE 'user_blocks';
```

## 3. Backend environment

Use `backend/.env.production.example` as the production template.

Required production settings:

```env
NODE_ENV=production
PORT=8080
CORS_ORIGINS=https://your-admin.example.com,https://your-web.example.com
MYSQL_HOST=...
MYSQL_PORT=3306
MYSQL_USER=coscircle_app
MYSQL_PASSWORD=...
MYSQL_DATABASE=coscircle
EVENT_SCRAPER_ENABLED=true
EVENT_SCRAPER_TIME_ZONE=Asia/Taipei
```

Production behavior to verify:

- `NODE_ENV=production` prevents automatic development admin creation.
- `CORS_ORIGINS` is not empty and contains only trusted HTTPS origins.
- The hosting platform stores uploads persistently, or the `uploads/` directory
  is backed by a volume/object storage before users upload images.
- Logs are access-controlled because auth and operational errors may include
  account identifiers.
- MySQL backups are scheduled before the first public release.

Health check:

```sh
curl https://api.example.com/api/health
```

Expected response:

```json
{"ok":true,"name":"CosCircle API"}
```

## 4. Android release build

Release builds must use HTTPS and a real Google Maps key:

```sh
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.example.com/api \
  -PGOOGLE_MAPS_API_KEY=your_google_maps_key
```

Safety checks:

- Building release without `-PGOOGLE_MAPS_API_KEY` must fail.
- Building release with `http://` `API_BASE_URL` must fail.
- The generated APK is signed with the release keystore, not the debug key.
- The installed APK can register, log in, list events, open the current-event
  map, share location with an expiry, stop sharing, block a user, and use
  emergency stealth mode.
- Android push tokens can be registered through `POST /api/me/push-tokens`;
  real FCM delivery credentials and recognition notification dispatch must be
  verified before inviting closed beta testers.

## 5. Pre-release verification

Run these before tagging or distributing a build:

```sh
flutter analyze
flutter test
node --check backend/src/server.js
cd backend && npm run smoke:privacy
flutter build apk --debug
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.example.com/api \
  -PGOOGLE_MAPS_API_KEY=your_google_maps_key
```

When testing staging or production, point the smoke test at that API:

```sh
cd backend
API_BASE_URL=https://api.example.com/api npm run smoke:privacy
```

Real Android smoke test:

```sh
flutter test integration_test/full_app_ui_test.dart \
  -d <android-device-id> \
  --dart-define=API_BASE_URL=https://api.example.com/api
```

Manual smoke checklist:

- Register a new account and complete onboarding.
- Log out and log back in.
- Open event discovery and event detail.
- Open current-event map and confirm it does not expose location by default.
- Share location with `circle` visibility and a short expiry.
- Stop sharing and confirm the location disappears from the API.
- Send a recognition request and confirm pending requests expire after 5
  minutes and cannot be spammed past the cooldown limits.
- Block another user and confirm that user disappears from location results.
- Enable emergency stealth mode and confirm profile booking visibility is
  restricted to circles.
- Open settings connection status and confirm the production API is healthy.

## 6. Rollback plan

- Keep the previous signed APK or store release available.
- Back up MySQL before applying migrations.
- Deploy backend and database changes before distributing the Android build.
- If privacy/location behavior fails, disable public distribution, restore the
  database backup if needed, and redeploy the previous backend image.
