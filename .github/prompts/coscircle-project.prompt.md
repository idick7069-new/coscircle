# CosCircle Project Skill

Use this prompt when working on the CosCircle Flutter project. Base suggestions and changes on the existing codebase, product behavior, architecture, and backend contract.

## Product Context

CosCircle, also named `Cos小圈圈`, is a Flutter Android/iOS/Web app for cosplay, ACG, and doujin-event attendees.

The app helps users:

- Discover cosplay/doujin events.
- Declare event attendance and role.
- Build profile and attendance cards.
- Share profile identity by QR/public code.
- Follow, block, and manage social visibility.
- Create, join, edit, and leave circles.
- Share current event location.
- Create meetups and recognition signals.
- Use admin tools for stats, event management, users, event submissions, and doujin event sync.

## Architecture

Frontend:

- Flutter/Dart.
- Material 3.
- Riverpod for state management.
- GoRouter for routing.
- Dio for REST API.
- SharedPreferences for auth token persistence.
- Google Maps, geolocator, local notifications.
- QR generation/scanning through `qr_flutter` and `mobile_scanner`.
- Image picker, share utilities, WebView, URL launcher.

Backend:

- Express REST API in `backend/src/server.js`.
- MySQL schema and migrations in `backend/db`.
- Event scraping scripts in `backend/scripts`.

## Key Files

- `README.md`
- `pubspec.yaml`
- `lib/main.dart`
- `lib/app/cos_circle_app.dart`
- `lib/core/router/app_router.dart`
- `lib/core/api/api_client.dart`
- `lib/core/providers/*.dart`
- `lib/core/models/*.dart`
- `lib/core/repositories/*.dart`
- `lib/features/**/presentation/*.dart`
- `lib/shared/widgets/cos_ui.dart`
- `backend/src/server.js`
- `backend/db/schema.sql`
- `backend/db/migrate_*.sql`
- `docs/design/figma_project_brief.md`
- `docs/deployment/*.md`

## Routes

Current GoRouter routes:

- `/login`: login/register/social-token page.
- `/onboarding`: first-use profile setup.
- `/`: `HomeShellPage`.
- `/events/:id`: event detail.
- `/current/:id`: current event map/location workflow.
- `/profiles/:code`: public profile by QR/public code.
- `/scan-profile`: profile QR scanner.
- `/scan-circle`: circle invite QR scanner.

Bottom navigation destinations:

- `名片`
- `活動`
- `現場`
- `同好`
- `設定`

## Feature Areas

### Auth

Files:

- `lib/features/auth/presentation/login_page.dart`
- `lib/core/repositories/auth_repository.dart`
- `backend/src/server.js`

Capabilities:

- Register, login, logout.
- Social-token login placeholder for Facebook and LINE.
- Token restore from SharedPreferences.
- Bearer auth header through `ApiClient`.

Relevant endpoints:

- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/logout`
- `POST /api/auth/social`
- `GET /api/me`
- `PUT /api/me`

### Profile and QR Identity

Files:

- `lib/features/profile/presentation/profile_page.dart`
- `lib/features/profile/presentation/public_profile_page.dart`
- `lib/features/profile/presentation/profile_qr_scanner_page.dart`
- `lib/features/profile/presentation/onboarding_profile_page.dart`
- `lib/core/models/profile.dart`
- `lib/core/repositories/profile_repository.dart`

Capabilities:

- Profile editing.
- Public profile by `publicCode`.
- Profile QR scanning.
- Image upload.
- Work tags and pit works.
- Age, regions, travel preference, landmine, gender, other photos.
- Booking visibility/privacy dashboard.
- Follower management and blocking.

### Events and Attendance

Files:

- `lib/features/events/presentation/event_list_page.dart`
- `lib/features/events/presentation/event_detail_page.dart`
- `lib/features/events/presentation/my_events_page.dart`
- `lib/features/events/presentation/event_booking_share_page.dart`
- `lib/features/events/presentation/widgets/event_card.dart`
- `lib/core/repositories/event_repository.dart`
- `lib/core/repositories/submission_repository.dart`

Capabilities:

- Event discovery, calendar/filter UI.
- Event detail and official source WebView.
- Join/modify/cancel event attendance.
- Per-day attendance through `dayIndex`.
- Role declaration: photographer, coser, manager, self.
- Work/character/time/interaction/status/note/outfit photo for attendance.
- Participant browsing, follow/block actions.
- My events ticket/card view.
- Attendance share image/card.
- Event submissions for review.

### Current Event, Location, Meetups, Recognition

Files:

- `lib/features/current_event/presentation/current_event_page.dart`
- `lib/features/current_event/presentation/widgets/current_event_overlays.dart`
- `lib/core/repositories/location_repository.dart`
- `lib/core/models/shared_location.dart`
- `lib/core/models/meetup_point.dart`
- `lib/core/models/recognition_request.dart`

Capabilities:

- Current-event map/radar experience.
- Shared location fetch/share/stop sharing.
- Meetup create/update/delete.
- Recognition request and response.
- Local notification initialization.
- Location visibility and expiry concepts.

### Social Circles

Files:

- `lib/features/social/presentation/social_page.dart`
- `lib/features/social/presentation/circle_qr_scanner_page.dart`
- `lib/core/models/circle.dart`
- `lib/core/repositories/social_repository.dart`

Capabilities:

- Create/edit/join/leave circles.
- Join by invite code or QR.
- Remove members from owned circles.
- View followed users.
- Unfollow users.
- Circle invite display and QR-oriented flow.

### Admin and Settings

Files:

- `lib/features/settings/presentation/settings_page.dart`
- `lib/features/settings/presentation/theme_settings_page.dart`
- `lib/features/admin/presentation/admin_dashboard_page.dart`
- `lib/core/repositories/admin_repository.dart`

Capabilities:

- Theme settings: neon dark and Morandi light.
- Connection status/API health diagnostics.
- Rewatch onboarding.
- Bug report page.
- Event submission flow.
- Admin stats, event CRUD, user management, doujin sync, submission approval/rejection.

## Data and Backend

Important Flutter models:

- `CosEvent`, `EventStatus`
- `EventBooking`, `ParticipantRole`
- `EventParticipant`
- `UserProfile`
- `WorkTag`
- `CircleGroup`, `CircleMember`, `FollowedUser`
- `SharedLocation`
- `MeetupPoint`
- `RecognitionRequest`, `RecognitionStatus`
- `BookingFollower`, `BookingFollowerGroup`, `BlockedUser`
- `AdminStats`, `AdminUser`
- `EventSubmission`

Important MySQL tables:

- `users`
- `works`
- `user_pit_works`
- `events`
- `event_bookings`
- `follows`
- `user_blocks`
- `circles`
- `circle_members`
- `shared_locations`
- `event_meeting_points`
- `event_recognition_requests`
- `event_submissions`

## Development Rules

- Keep copy in Traditional Chinese.
- Use existing feature folders and shared widgets.
- Reuse `CosCard`, `CosBadge`, `CosChoicePill`, `CosSectionHeader`, `CosGradientPanel`, `CosSafetyConfirmDialog`, `AppPage`, and related components.
- Keep mobile as the source of truth; web uses a phone-like constrained frame.
- Preserve loading, empty, error, offline/failure, and destructive-confirmation states.
- For new API-backed features, update Flutter model/repository/provider/UI and backend endpoint/schema/migration together.
- For privacy/social/location changes, check current user identity, blocked users, follows, circle membership, visibility, and expiry behavior.
- Preserve release API safety: release builds require `API_BASE_URL` and HTTPS.
- Do not commit real secrets from `.env`, `local.properties`, signing files, or API keys.

## Verification

Prefer focused verification:

- `flutter analyze`
- Relevant `flutter test`
- Relevant integration tests under `integration_test`
- Backend smoke/manual tests when changing Express/API/privacy behavior

When you cannot verify, say exactly what was not run and why.
