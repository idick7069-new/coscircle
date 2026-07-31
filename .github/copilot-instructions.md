# Copilot Instructions for CosCircle

Use the CosCircle project context when modifying this repository.

CosCircle is a Flutter app for cosplay, ACG, and doujin-event attendees. It helps users discover events, declare attendance, manage profile cards, share QR identities, follow/block users, create or join circles, share event-day location, manage meetups/recognition signals, and operate admin/event-management workflows.

Project rules:

- Preserve the current stack: Flutter, Material 3, Riverpod, GoRouter, Dio, SharedPreferences, local notifications, Google Maps, QR generation/scanning, image picker, and share utilities.
- Preserve the current folders: `lib/core`, `lib/features`, `lib/shared`, `backend`, `backend/db`, and `docs`.
- Keep product-facing copy in Traditional Chinese unless the surrounding context says otherwise.
- Reuse shared UI from `lib/shared/widgets/cos_ui.dart`, `AppPage`, and `SectionHeader` before creating new primitives.
- For API-backed changes, check/update all relevant layers: Flutter model, repository, provider/UI, Express endpoint, and MySQL schema/migration.
- For auth, profile privacy, location sharing, follows, blocking, circles, and event attendance, verify privacy and visibility behavior on both client and backend.
- Do not weaken release API safety: release builds require `API_BASE_URL` and HTTPS.
- Do not commit secrets from `.env`, `local.properties`, signing files, or real API keys.

When unsure about current behavior, inspect the existing implementation first and distinguish `Confirmed`, `Inferred`, and `Needs confirmation`.

For deeper context, use `.github/prompts/coscircle-project.prompt.md`.
For Traditional Chinese project context, use `.github/prompts/coscircle-project-zh.prompt.md`.
