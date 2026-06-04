# CosCircle Figma Design Project

This package maps the current Flutter codebase into a Figma-ready design
project. It is written so the Figma file can be built page by page, with
component names, variants, states, and prototype flows matching the app code.

Companion file:

- `docs/design/figma_tokens.json`

## Project Structure

Create one Figma project named `CosCircle / Cos小圈圈`.

Recommended pages:

1. `00 Cover`
2. `01 Design Tokens`
3. `02 Components`
4. `03 Auth`
5. `04 Home Shell`
6. `05 Events`
7. `06 Current Event Map`
8. `07 Profile`
9. `08 Social`
10. `09 Admin`
11. `10 Prototype Flows`

Primary frame sizes:

- `Android / 393 x 852`
- `iPhone / 390 x 844`
- `Small Android / 360 x 800`

Use `Android / 393 x 852` as the source of truth unless a screen has a
small-width edge case.

## Product Positioning

CosCircle is an event-day companion for Coser, photographers, and ACG event attendees.

Core promise:

- Find who is attending an event.
- Publish an attendance declaration.
- Search people by work, role, interaction intent, and status.
- Share approximate/current location during active events.
- Share profile by QR code without exposing user id.

## Design Tokens

Source: `lib/core/theme/app_theme.dart`

### Colors

| Token | Value | Usage |
| --- | --- | --- |
| `color.primary` | `#4F9DC9` | Primary actions, selected states |
| `color.secondary` | `#FFB86B` | Social/follow highlights, warm accent |
| `color.tertiary` | `#8CC9A8` | Today/current activity accent |
| `color.surface` | `#FFFBF5` | App background |
| `color.card` | `#FFFFFF` | Cards, sheets, panels |
| `color.seed` | `#5FA8D3` | Material color seed |

Suggested semantic additions for Figma:

| Token | Value | Usage |
| --- | --- | --- |
| `color.success` | `#4F9D69` | Approved, active, online |
| `color.warning` | `#D9822B` | Pending, limited interaction |
| `color.danger` | `#C94F4F` | Delete, reject, destructive |
| `color.disabledBg` | `#E9E5DD` | Ended/disabled cards |
| `color.disabledText` | `#77736C` | Ended/disabled text |

### Shape

| Token | Value |
| --- | --- |
| `radius.card` | `8` |
| `radius.input` | `8` |
| `radius.button` | `8` |
| `radius.pill` | `999` |

### Spacing

| Token | Value |
| --- | --- |
| `space.page` | `16` |
| `space.card` | `10-14` |
| `space.section` | `20` |
| `space.inline` | `8` |
| `space.compact` | `4-6` |

### Typography

Use Material 3 default text scale as the base.

Suggested Figma text styles:

- `Display / App Name`: displaySmall, weight 800
- `Heading / Page`: headlineSmall, weight 800
- `Heading / Section`: titleLarge, weight 800
- `Title / Card`: titleMedium, weight 700
- `Body / Default`: bodyMedium
- `Body / Secondary`: bodySmall
- `Label / Pill`: labelSmall, weight 600

## Component Inventory

Build components on the `02 Components` page first, then compose screen frames
from instances. Name components with slash hierarchy, for example
`Event/Card`, `Event/Tag`, `Profile/Summary`.

### App Shell

Source:

- `lib/features/home/presentation/home_shell_page.dart`
- `lib/shared/widgets/app_page.dart`

Components:

- `BottomNavigation / Main`
  - Destinations: 個人, 活動, 當前, 社交, 其他
  - Active state: filled Material icon
  - Inactive state: outlined Material icon

- `AppPage`
  - Safe area
  - Default padding: `16`
  - Optional app bar and FAB

### Event Card

Source: `lib/features/events/presentation/widgets/event_card.dart`

Component: `EventCard`

Variants:

- `upcoming`
- `active`
- `ended / disabled`
- `joined`

Layout:

- Horizontal card
- Left image: `92 x 112`
- Right content:
  - tags row: category, status, source
  - title
  - date
  - venue
  - participant avatar strip
  - actions: 詳細, 加入/修改

Ended state:

- Card background uses disabled surface.
- Text uses surface variant.
- Join action disabled.

Figma properties:

- `state`: `upcoming | active | ended`
- `joined`: `true | false`
- `image`: `present | placeholder`
- `density`: `regular | narrow`

Auto layout:

- Direction: horizontal
- Gap: `10`
- Padding: `10`
- Min height: `132`
- Image fixed: `92 x 112`
- Content: fill container

### Event Tags

Source: `_EventTag`

Component: `Tag / Event`

Properties:

- label
- optional leading icon

Style:

- Height: `22`
- Radius: pill
- Border: outline variant
- Text: labelSmall

### Participant Avatar Strip

Source: `_ParticipantStrip`

Component: `AvatarStrip`

Behavior:

- Show up to 10 participant avatars.
- Supports loading/empty states.

### Attendance Sheet

Source: `lib/features/events/presentation/event_list_page.dart`

Component: `Attendance/Sheet`

Fields:

- Role segmented control: 攝影 / Coser / 本體
- Work selector
- Character name
- Available time
- Interaction tags
- Presence status dropdown
- Outfit image upload
- Note
- Actions: 取消出席, 我會去/儲存出席

States:

- create
- edit
- submitting
- error snackbar

Tone:

- Use the wording `發布出席宣告`, not booking/reservation language.
- This feature means "I will attend and people can find/interact with me",
  not a one-on-one appointment.

### Event Detail

Source: `lib/features/events/presentation/event_detail_page.dart`

Frame: `Event Detail`

Sections:

- Hero image
- Event title
- Info grid
- Source webview button
- Description
- `今天誰會去`
- Participant search and filters
- Participant card list

Info grid should display user-facing source names only:

- `同人誌中心`
- `投稿活動`
- `官方建立`

Do not show event id or raw source type in UI frames.

Participant filters:

- Search nickname/work/character
- Role chips: 全部, Coser, 攝影, 本體
- Toggle chips: 只看可互動, 只看關注
- Interaction tag chips

### Participant Card

Source: `_ParticipantCard`

Component: `ParticipantCard`

Content:

- Avatar
- Nickname
- Role/work/character
- Presence status pill
- Available time
- Up to 4 interaction tags

### Current Event Map

Source: `lib/features/current_event/presentation/current_event_page.dart`

Frame: `Current Event Map`

Elements:

- Google map background
- Floating event header card
- Filter chips: all/followed/circle
- Avatar map markers
- Share location FAB
- Empty state: 目前無當前活動
- Location detail bottom sheet

Marker spec:

- Pin body uses avatar as the primary visual.
- `isMe` marker uses primary color border/body.
- Other users use secondary color border/body.
- Marker tap opens the location detail sheet.
- Location age: show minutes under 60 minutes, then hours.

Important states:

- no active joined event
- loading event
- map with locations
- location sharing in progress

### Profile

Source:

- `lib/features/profile/presentation/profile_page.dart`
- `lib/features/profile/presentation/public_profile_page.dart`

Frames:

- `My Profile / View`
- `My Profile / Edit`
- `Profile Share QR`
- `Public Profile`

View mode:

- Avatar
- Nickname
- Bio
- Facebook URL
- Pit works chips
- Actions: edit, share QR

Edit mode:

- Avatar upload
- Nickname
- Facebook URL
- Bio
- Pit works selector
- Save

QR sheet:

- QR code data: `coscircle://profiles/<publicCode>`
- Nickname
- Selectable URL

Privacy rule:

- Never expose `userId` in QR, public profile URLs, or mock content.
- Use `publicCode` examples such as `P7K4Q9MA`.

### Auth

Source: `lib/features/auth/presentation/login_page.dart`

Frames:

- `Login`
- `Register`
- `Loading`
- `Error`

Elements:

- App name: CosCircle
- Subtitle: Cos小圈圈
- Segmented control: 登入 / 註冊
- Register-only nickname field
- Email
- Password
- Primary CTA
- Error text

### Social

Source: `lib/features/social/presentation/social_page.dart`

Frames:

- `Social / Circles`
- `Create Circle Sheet`
- `Join Circle Sheet`
- `Circle Card`

Known improvement target:

- Add copy/share affordance for invite code and URL.
- Add QR for circle invite.

### Works

Source:

- `lib/features/works/presentation/work_selector.dart`

Components:

- `Work/MultiSelector`
- `Work/SingleSelector`
- `Work/Chip`
- `Work/SearchResult`
- `Work/CreateInline`

Usage:

- Profile pit works: multi-select tags.
- Attendance declaration: single work for Coser role.
- Typing a missing work name creates it after Enter/submit.

Example data:

- `葬送的芙莉蓮`
- `Fate/Grand Order`
- `原神`
- `咒術迴戰`

### Admin

Source: `lib/features/admin/presentation/admin_dashboard_page.dart`

Frames:

- `Admin Dashboard`
- `Admin / Stats`
- `Admin / Users`
- `Admin / Submissions`
- `Admin / Events`
- `Create Event Sheet`
- `Edit Event Dates Sheet`

Components:

- Stats grid card
- User management tile
- Submission review tile
- Admin event tile
- Loading panel
- Error panel

Admin destructive actions:

- Delete user confirmation dialog.
- Delete event confirmation dialog.
- Reject submission confirmation or clear reject affordance.

Event date editing:

- Date fields show `yyyy/MM/dd`.
- End date cannot visually precede start date.

## Screen Frames

Create these concrete frames.

### `03 Auth / Login`

- App name: `CosCircle`
- Subtitle: `Cos小圈圈`
- Segmented control default: `登入`
- Email input
- Password input
- Primary CTA: `登入`
- Secondary text action: switch to register

### `03 Auth / Register`

- Segmented control default: `註冊`
- Nickname input
- Email input
- Password input
- Primary CTA: `建立帳號`
- After successful register, app should not ask nickname again.

### `04 Home Shell / Main`

- Bottom navigation with 5 destinations.
- Default selected destination in code is `當前`.
- Use real page content in the selected tab, not a marketing splash.

### `05 Events / Event List`

- Header: `活動清單`
- Filled tonal icon button: only joined events.
- Month calendar with joined event markers.
- Filter chips: `全部`, `我有加入`, `關注者`, `小圈圈`.
- Checkbox filter: `隱藏已結束`.
- Event card list, horizontal card layout.
- Pull-to-refresh state.

### `05 Events / Event Detail`

- Hero image.
- Title and status.
- Info grid: date, venue, category, source name.
- Source URL button opens webview.
- Participant area title: `今天誰會去`.
- Search input and chips.
- Participant cards.

### `05 Events / Attendance Sheet`

- Bottom sheet height target: up to `86%` viewport.
- Scrollable content to avoid bottom overflow.
- Role segmented button.
- Coser-only work and character fields.
- Interaction tags.
- Presence status dropdown.
- Outfit photo button.
- Note field.
- Submit row.

### `06 Current Event Map / Active`

- Full-screen map.
- Floating event header with event name and visible/total count.
- Filter chips.
- Avatar markers.
- Extended FAB: `分享位置`.

### `06 Current Event Map / Empty`

- Same map shell.
- Header and centered panel text: `目前無當前活動`.
- Share location FAB disabled.

### `07 Profile / View`

- Header: `個人資訊`
- QR share icon button.
- Edit icon button.
- Avatar, nickname, bio, Facebook, pit works.

### `07 Profile / Edit`

- Same header.
- Close icon button exits edit mode.
- Avatar upload.
- Nickname, Facebook, bio.
- Pit works multi-selector.
- Save button.

### `07 Profile / QR Share`

- Bottom sheet.
- Title: `分享個人資訊`.
- QR code.
- Nickname.
- Deep link with `publicCode`.

### `09 Admin / Dashboard`

- App bar title: `後台管理`.
- Actions: API URL, sync Doujin events, refresh.
- Stats grid.
- User management list with delete action.
- Submission review list.
- Event list with edit dates and delete actions.
- FAB: `新增活動`.

## Prototype Flows

### Flow 1: Register and Publish Attendance

1. Register
2. Home shell opens
3. Events tab
4. Tap event join
5. Fill attendance sheet
6. Submit
7. Event card updates joined state
8. Event detail shows participant card

Acceptance:

- No extra nickname step after account creation.
- Event list refreshes automatically after attendance changes.

### Flow 2: Find People at Event

1. Event detail
2. Search by work/character
3. Filter Coser + 可互動
4. Open participant sheet
5. Follow participant

### Flow 3: Share Profile

1. Profile tab
2. Tap QR share
3. Show QR
4. Open public profile by `profiles/:code`

### Flow 4: Current Event Map

1. Current tab
2. Active joined event is resolved
3. Share location
4. Tap avatar marker
5. View outfit, interaction tags, status

Acceptance:

- Ended activities are not selected as current.
- Header shows activity name, not event id.

### Flow 5: Admin Management

1. Settings
2. Admin dashboard
3. View stats
4. Delete user
5. Edit event dates

## Design Notes

- This product is operational, not marketing-first. Keep information dense but readable.
- Cards should remain restrained with 8px radius.
- Avoid large decorative gradients or hero marketing sections.
- The first screen should always be the actual workflow.
- Mobile-first target: Android physical device.
- Test long Chinese titles and venue names.
- Test small widths and large text scale.

## Figma Build Checklist

1. Create `01 Design Tokens` using `figma_tokens.json`.
2. Create text styles from the typography section.
3. Create color, radius, and spacing variables.
4. Build the `02 Components` page first.
5. Use variants for component states instead of duplicating detached copies.
6. Build all screen frames from instances.
7. Connect prototype flows.
8. Review at `360 x 800` for long Chinese strings and bottom sheets.

## Open Design Debt

These are visible product gaps worth representing as future-state frames:

- Auth guard and expired session state.
- Media upload progress and cross-device image display.
- Stop sharing location and location expiry.
- Copy/share buttons for profile and circle QR.
- Existing attendance edit prefill.
- Empty states for filtered event participants.
- Admin destructive action confirmations.
