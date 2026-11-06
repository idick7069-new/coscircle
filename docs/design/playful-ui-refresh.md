# CosCircle Playful UI Refresh

## Direction

Approved direction: illustration-led social UI, rounded surfaces, coral / teal /
yellow contrast, and lightweight profile-readiness progress. Logo A is one open
coral C with a short teal inward hook and a narrow light seam. No gender-symbol
extensions, detached dots, orbit, invented points, rewards or messaging features.

The light theme is the default for new installations. Existing saved light/dark
preferences retain their storage keys and are not overwritten. Both themes use
the new design system. Theme labels are 活力亮色 and 夜間撞色.

## Scope

- Shared: color and typography tokens, cards, buttons, switches, inputs, chips,
  dialogs, sheets, section/page headings, loading and error states.
- Brand: a single Flutter painter drives the app mark, startup animation and
  exported Android/iOS/Web icons. The animation has a small scale pulse and
  opacity reveal, no orbit or vertical movement. Reduced motion is immediate.
- Profile: compact identity without a decorative header illustration, prominent solid role pills, a working
  QRCode button, yellow readiness progress, and existing editable safety/details.
  Signal items open their corresponding edit fields. Profile saving stays in a
  fixed bottom row; failed saves retain the draft and show an inline error. Booking
  follower details are collapsed until expanded.
- Public profile: matching avatar surround and prominent role pills; existing
  follow, block and friendship actions retain their behavior.
- Events: calendar/filter-first discovery, smaller spotlight, illustrated fallback
  only when a real event image is absent, independent day controls retained.
- Booking, personal bookings and sharing: matching shared form controls and flat
  ticket surfaces; export canvas retains user photos/labels and removes glow orbs.
- Current event: solid, readable map header and state panels. Real Google Maps,
  avatar markers, sharing visibility/expiry and recognition flows are unchanged.
- Social: compact count overview, illustrated circle view, responsive action row,
  unchanged invitations, introductions, exact event snapshots and ignore privacy.
  The 同坑 tab matches shared deep/shallow works with paginated results and links
  to public cards and the existing friend-introduction flow.
- Account: illustrated login/onboarding, themed email states, login-method and
  verification entries, scrollable invite page.
- Settings, theme selection, scanning, work selection, diagnostics and admin:
  common component styling; admin remains a restrained work surface rather than
  becoming an illustrated dashboard. Scanner camera/contrast mask is preserved.

No API, database, auth/relationship/privacy policy or production deployment change
is part of this refresh. Production builds point to https://coscircle.app/api.

## Assets

Generated using the built-in image generation tool, not third-party stock photos:

- `assets/illustrations/meet-your-circle.png`: flat editorial illustration of an
  adult cosplayer and photographer exchanging a blank card; white background,
  teal/coral/yellow palette, rounded simplified forms, no text or UI.
- `assets/illustrations/next-event.png`: exhibition entrance, ticket and blank
  calendar; matching palette and white backdrop, no text, branding or UI.

These are decorative brand illustrations, never user avatars, official event
photos, venue maps, or evidence of actual attendance. Real uploaded media wins.

Platform icons are generated from the actual painter, not cropped from concept
boards. Export is opt-in:

```sh
flutter test test/export_brand_icons_test.dart --dart-define=EXPORT_BRAND_ICONS=true
```

The exporter reads the existing iOS asset manifest, checks output dimensions and
opacity, and writes only the existing declared platform icon paths.

## Verification

`test/playful_ui_test.dart` checks brand/theme compatibility, illustration loading,
reduced motion, QR button wiring and rendered light/dark page layouts. Optional
`QA_SCREENSHOTS=true` writes actual Flutter screenshots to `build/ui-preview/`.
`QA_CJK_FONT` and `QA_LATIN_FONT` may point to locally licensed test fonts; these
fonts are not bundled or redistributed with the application.

The existing regression suite continues covering 320/360/390/430px widths,
1x/1.5x/2x text, dark/light themes, QR portrait/landscape, bookings, privacy,
account startup, LINE, notifications, friendships and tap targets.

Device-only camera, LINE authorization, notifications and native map gestures
still require hardware acceptance testing. No such actions are simulated against
production accounts merely to produce visual screenshots.
