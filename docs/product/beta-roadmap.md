# CosCircle beta roadmap

CosCircle's public goal is a production product for cosplay, ACG, and doujin
event attendees. The current delivery phase is a closed beta, not a prototype.
This roadmap captures the decisions accepted during project grilling and should
be used to decide what ships before inviting real testers.

## Product position

- Target state: public production product.
- Current phase: closed beta.
- Beta posture: treat privacy, location, recognition, accounts, and operations
  as real product concerns.
- Prototype shortcuts are not acceptable for beta behavior that touches real
  users or real event-day location.

## Beta success standard

The first beta succeeds only if 10-30 real users can use CosCircle across 1-2
real events without privacy incidents.

Minimum user outcomes:

- Find a real event.
- Log in and declare attendance.
- Use small-circle finding during the event.
- Send and receive recognition notifications.
- Share location only with trusted or allowed users.
- Stop sharing location and verify it disappears.
- Block a user and verify that sensitive visibility is cut off.

## Release gates

### Internal functional build

This build is only for the developer or a very small internal check.

- May use `http://34.187.168.222/api`.
- May run from debug tooling.
- Must not be distributed to real beta testers.
- Useful for verifying API connectivity, admin flows, and Android device
  behavior before domain work is complete.

### Closed beta build

This build may be given to real users only when all gates pass.

- HTTPS domain is configured for Web and API.
- Android release build uses HTTPS `API_BASE_URL`.
- Core features require login.
- Debug fallback data is not allowed to silently replace API failures.
- Android FCM recognition push is working.
- Privacy smoke test passes against the target backend.
- Location sharing, stop sharing, blocking, and recognition visibility are
  verified.
- Web Admin can manage activities, submissions, users, and sync status.

## Scope principles

- Beta is not a feature buffet.
- Small-circle finding is the first main flow.
- Public recognition is the second main flow.
- Web Admin is an operations tool, separate from the attendee app.
- Manual activity management is the reliable source of truth; scraping is an
  auxiliary source.
- Location and recognition safety take priority over map polish.

## Core app gates

### Login required

Beta core functionality requires login:

- Event discovery.
- Attendance.
- Current-event map.
- Location sharing.
- Small circles.
- Recognition.
- Profile identity and QR flows.

Public browsing can be reconsidered later, after beta risk is lower.

### Debug fallback

Silent debug fallback must be removed or made explicit.

Current risk:

- API failures can fall back to in-memory seed data.
- Seed data can look real and hide connectivity failures.
- This already caused a false diagnosis where the app appeared to have no
  events after 2026-07-04.

Required beta behavior:

- API failure shows a clear connection error.
- Demo data is available only through an explicit developer/demo mode.
- Demo mode must be visually distinguishable from real data.

## Web Admin

Create an independent Web Admin entry, recommended route:

```text
/admin
```

Admin must be a desktop operations surface, not the phone-style app shell.

Minimum areas:

- Overview: API health, activity counts, pending submissions, user counts,
  crawler status.
- Submissions: review, edit, approve, reject.
- Events: list, search, filter, create, edit, unpublish/reject, delete only when
  necessary.
- Users: search, suspend, restore, grant admin, revoke admin.
- Sync: crawler status, last success, last failure, error details, manual sync.
- Audit: show who performed sensitive admin actions.

### Admin permissions

- Beta supports multiple admins with the same permission level.
- Use `is_admin`; do not introduce role-based access control yet.
- Admin grant/revoke must happen inside Web Admin.
- Admin grant/revoke must write audit logs.
- Do not rely on database edits as the normal admin provisioning path.
- Production must not rely on automatic development admin creation.

### Account management

Daily account management should prefer suspension over deletion.

Required states:

- `active`
- `suspended`

Suspended users:

- Cannot log in or use core functionality.
- Keep historical data for audit and beta debugging.

Deletion should be reserved for exceptional privacy, legal, or cleanup cases and
should not be the primary Admin action.

## Activity data strategy

Manual activity management is the primary path for beta.

The Doujin scraper is useful but cannot be the only source of truth because the
GCP VM has been blocked by Cloudflare challenge responses from the source site.

### Submission review

Submission approval must allow editing fields before publishing.

Flow:

1. User submits an activity.
2. Admin opens the submission in Web Admin.
3. Admin edits and standardizes fields.
4. Admin approves and publishes, or rejects with a clear state.

Do not make one-click approval the only path.

### Minimum publish standard

An event cannot be published unless these fields are acceptable:

- Activity name.
- Start date.
- End date, not earlier than start date.
- Venue name.
- Detailed address, required for beta events using map/current-event features.
- Source type.
- Source name.
- Source URL for submissions and scraped data.
- Status: `pending`, `approved`, or `rejected`.
- Cancelled or postponed events must be visibly marked, not silently mixed into
  normal approved events.

### Sync observability

Crawler sync must be observable, not just a button.

Track and display:

- `source_url`
- `last_success_at`
- `last_failure_at`
- `last_error_code`
- `last_error_message`
- `last_import_count`

Failure rules:

- Failed sync must not overwrite or delete existing activities.
- Admin must see whether the last failure was Cloudflare 403, timeout, parser
  failure, or database failure.

## Location sharing

Location sharing is the highest-risk beta feature.

Required defaults:

- Location is not shared by default.
- User must explicitly share location.
- Share flow shows visibility scope and expiry.
- Default visibility is trusted/small-circle oriented, not public.
- Stop sharing is prominent and fast.
- API failure cannot be presented as successful stop sharing.

### Visibility rules

To view another user's event location, the viewer must satisfy all rules:

- Viewer is logged in.
- Viewer attends the same event.
- Viewer attends the same event day.
- Target location is not expired.
- Target visibility allows the viewer.
- No blocking relation exists in either direction.

Visibility modes may still exist, but they sit on top of the same-event,
same-day, expiry, and block checks.

### Stop sharing

Stop sharing must be enforced by the backend.

Required guarantee:

- Once stopped, the location is deleted or immediately unavailable.
- Refreshing, changing devices, or using another viewer token must not reveal it.
- Stop sharing must be covered by backend smoke tests.

### Blocking

Blocking is a two-way safety boundary.

If user A blocks user B:

- B cannot see A's location.
- A should not be forced to see B in maps or participant surfaces.
- B cannot send recognition requests to A.
- B cannot regain sensitive visibility through follows or circle membership.

## Recognition and finding people

CosCircle's core event-day value is helping people find each other and recognize
friends safely.

Recognition is therefore core, not secondary.

### Modes

There are two different modes:

- Small-circle finding.
- Public event recognition.

They must be designed separately because they carry different social and safety
risks.

### Small-circle finding

This is the first beta main flow.

Expected flow:

- Users form or join small circles before or during an event.
- Users declare attendance for the same event/day.
- Users share location with allowed visibility.
- Circle members can find each other on the current-event map.
- Circle members can send recognition requests or meetup updates.
- Blocking and stop sharing still override circle relationships.

### Public event recognition

This is the second beta main flow.

Required rule:

- Joining an event does not mean a user is publicly recognizable.
- Public recognition requires an explicit opt-in: "available for recognition
  today".

Public opt-in can include:

- Character.
- Work.
- Available time.
- Notes or boundaries.

Public recognition requests can be sent only when:

- Both users attend the same event/day.
- Target opted in to public recognition.
- Target is visible to the requester.
- No blocking relation exists.
- Rate limits and cooldowns allow it.

## Recognition notifications

Android real-time push is a closed-beta gate.

Beta platform scope:

- Android FCM is required.
- iOS APNs is deferred.
- Web Admin does not need mobile push.

Minimum Android FCM loop:

- App registers a device push token after login.
- Backend stores user device tokens.
- Recognition request sends push to the target user.
- Tapping the notification opens the event/recognition context.
- Target can respond from the app.
- Response sends push back to the requester.
- Push failure is logged, while the recognition request remains visible in-app.

Current local notifications are not enough for this requirement.

## Recognition state machine

Replace response-word states with product states.

Required states:

- `pending`
- `accepted`
- `declined`
- `expired`
- `cancelled`

Do not use `come` and `busy` as persistent states. Those can become labels or
response copy for `accepted` and `declined`.

### Expiry

Recognition requests expire after 5 minutes by default.

Rules:

- `expires_at = created_at + 5 minutes`.
- Expired requests cannot be answered.
- Expired requests are not shown as actionable pending items.
- Push copy should include the short validity window.

### Cooldown and anti-harassment

For the same requester, target, event, and day:

- A pending request prevents sending another one.
- After `declined`, requester must wait 15 minutes.
- After `expired`, requester can retry, but at most 3 times per hour.
- After blocking, requester can never send.
- `accepted` should not encourage repeated requests; a follow-up action should
  be explicit and bounded.

## Backend validation gates

Backend checks are the source of truth.

Required smoke coverage before beta:

- Register and log in.
- Create or use an approved event.
- Declare same-event same-day attendance.
- Share location.
- Confirm an allowed viewer can see it.
- Confirm a non-attending viewer cannot see it.
- Confirm stop sharing removes visibility.
- Confirm expired location is hidden.
- Confirm block cuts location visibility.
- Confirm recognition cannot bypass blocks.
- Confirm recognition cannot target users outside allowed event/day visibility.
- Confirm recognition cooldowns and expiry.

## First beta test plan

The first beta should be structured, not a broad unstructured invite.

Recommended shape:

- One real event.
- 10-15 people.
- 2-3 small circles.
- Everyone creates a profile card before event day.
- Everyone joins the same event day.
- Event-day tasks:
  - Find small-circle members.
  - Send recognition requests.
  - Respond to recognition requests.
  - Create or update a meetup point.
  - Share location.
  - Stop sharing location.
  - Block a test account and verify disappearance.
- Post-event feedback:
  - Did they find people faster?
  - Did notifications arrive in time?
  - Did visibility rules feel understandable?
  - Did anyone feel exposed or bothered?
  - What caused confusion during the event?

## Not doing yet

These are intentionally out of beta scope unless revisited:

- Public launch.
- Anonymous public event browsing.
- iOS APNs push.
- Role-based admin permissions.
- Recommendation algorithms.
- Chat or full messaging.
- Broad stranger discovery without explicit public recognition opt-in.
- Highly available multi-instance infrastructure.
- Relying on scraper success as the only activity data path.

## Immediate implementation priorities

1. Add explicit demo mode and remove silent debug fallback.
2. Create independent Web Admin route and desktop admin layout.
3. Add user suspension/restoration and admin grant/revoke with audit logs.
4. Add activity submission edit-before-approve flow.
5. Add crawler sync observability.
6. Tighten location visibility to same-event same-day plus visibility, expiry,
   and block checks.
7. Expand privacy smoke tests for stop sharing, blocks, attendance, and expiry.
8. Add Android FCM token registration and backend push dispatch.
9. Convert recognition to the accepted state machine.
10. Add recognition expiry, cooldown, and public recognition opt-in.
11. Run a structured internal functional test using the GCP HTTP IP.
12. Add HTTPS domain before distributing the closed beta build.
