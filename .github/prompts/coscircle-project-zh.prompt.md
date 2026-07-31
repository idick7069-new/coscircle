# CosCircle 專案 Skill

使用這份 prompt 時，請基於 CosCircle 目前已開發的功能、架構、產品語氣、API contract 與資料庫結構進行回答或修改。

## 產品上下文

CosCircle，也稱為 `Cos小圈圈`，是給 cosplay、ACG、同人活動參與者使用的 Flutter Android/iOS/Web App。

目前 App 協助使用者：

- 探索 cosplay/同人活動。
- 宣告活動出席與身份。
- 建立個人檔案與活動出席名片。
- 透過 QR/public code 分享個人身份。
- 追蹤、封鎖與管理社交可見性。
- 建立、加入、編輯與離開小圈圈。
- 在活動當天分享目前位置。
- 建立集合點與認親訊號。
- 使用後台工具管理統計、活動、使用者、活動投稿與同人活動同步。

## 架構

前端：

- Flutter/Dart。
- Material 3。
- Riverpod 狀態管理。
- GoRouter 路由。
- Dio REST API。
- SharedPreferences 儲存 auth token。
- Google Maps、geolocator、local notifications。
- `qr_flutter` 與 `mobile_scanner`。
- image picker、share utilities、WebView、URL launcher。

後端：

- `backend/src/server.js` 內的 Express REST API。
- `backend/db` 內的 MySQL schema 與 migrations。
- `backend/scripts` 內的活動資料爬蟲/清理腳本。

## 重要檔案

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

## 路由

目前 GoRouter routes：

- `/login`：登入/註冊/social-token 登入頁。
- `/onboarding`：第一次使用的個人檔案設定。
- `/`：`HomeShellPage`。
- `/events/:id`：活動詳情。
- `/current/:id`：目前活動地圖/位置流程。
- `/profiles/:code`：以 QR/public code 開啟公開個人檔案。
- `/scan-profile`：個人 QR 掃描。
- `/scan-circle`：小圈圈邀請 QR 掃描。

底部導覽：

- `名片`
- `活動`
- `現場`
- `同好`
- `設定`

## 功能區

### Auth

檔案：

- `lib/features/auth/presentation/login_page.dart`
- `lib/core/repositories/auth_repository.dart`
- `backend/src/server.js`

能力：

- 註冊、登入、登出。
- Facebook/LINE social-token 登入 placeholder。
- 從 SharedPreferences 還原 token。
- 透過 `ApiClient` 附加 Bearer auth header。

Endpoints：

- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/logout`
- `POST /api/auth/social`
- `GET /api/me`
- `PUT /api/me`

### 個人檔案與 QR 身分

檔案：

- `lib/features/profile/presentation/profile_page.dart`
- `lib/features/profile/presentation/public_profile_page.dart`
- `lib/features/profile/presentation/profile_qr_scanner_page.dart`
- `lib/features/profile/presentation/onboarding_profile_page.dart`
- `lib/core/models/profile.dart`
- `lib/core/repositories/profile_repository.dart`

能力：

- 個人檔案編輯。
- 以 `publicCode` 查看公開個人檔案。
- 個人 QR 掃描。
- 圖片上傳。
- 作品標籤與坑單。
- 年齡、常跑地區、遠征偏好、雷點、性別、其他照片。
- 出席可見性/隱私 dashboard。
- 粉絲管理與封鎖。

### 活動與出席

檔案：

- `lib/features/events/presentation/event_list_page.dart`
- `lib/features/events/presentation/event_detail_page.dart`
- `lib/features/events/presentation/my_events_page.dart`
- `lib/features/events/presentation/event_booking_share_page.dart`
- `lib/features/events/presentation/widgets/event_card.dart`
- `lib/core/repositories/event_repository.dart`
- `lib/core/repositories/submission_repository.dart`

能力：

- 活動探索、月曆與篩選 UI。
- 活動詳情與官方來源 WebView。
- 加入/修改/取消活動出席。
- 以 `dayIndex` 支援多日活動。
- 出席身份：photographer、coser、manager、self。
- 出席資料：作品、角色、可互動時間、互動方式、狀態、備註、出角照片。
- 參與者列表、追蹤/封鎖互動。
- 我的活動票夾/名片。
- 出席分享卡產圖。
- 活動投稿。

### 現場活動、位置、集合點、認親

檔案：

- `lib/features/current_event/presentation/current_event_page.dart`
- `lib/features/current_event/presentation/widgets/current_event_overlays.dart`
- `lib/core/repositories/location_repository.dart`
- `lib/core/models/shared_location.dart`
- `lib/core/models/meetup_point.dart`
- `lib/core/models/recognition_request.dart`

能力：

- 目前活動地圖/雷達體驗。
- 取得、分享、停止分享位置。
- 建立/更新/刪除集合點。
- 認親 request/response。
- local notification 初始化。
- 位置可見性與到期概念。

### 小圈圈社交

檔案：

- `lib/features/social/presentation/social_page.dart`
- `lib/features/social/presentation/circle_qr_scanner_page.dart`
- `lib/core/models/circle.dart`
- `lib/core/repositories/social_repository.dart`

能力：

- 建立/編輯/加入/離開小圈圈。
- 透過邀請碼或 QR 加入。
- 擁有者移除成員。
- 查看已追蹤使用者。
- 取消追蹤。
- 小圈圈邀請碼與 QR 流程。

### 後台與設定

檔案：

- `lib/features/settings/presentation/settings_page.dart`
- `lib/features/settings/presentation/theme_settings_page.dart`
- `lib/features/admin/presentation/admin_dashboard_page.dart`
- `lib/core/repositories/admin_repository.dart`

能力：

- 主題設定：neon dark 與 Morandi light。
- 連線狀態/API health 診斷。
- 重看 onboarding。
- Bug report page。
- 活動投稿。
- 後台統計、活動 CRUD、使用者管理、同人活動同步、投稿審核/拒絕。

## 開發規則

- 產品文案使用繁體中文。
- 沿用既有 feature folders 與 shared widgets。
- 優先復用 `CosCard`、`CosBadge`、`CosChoicePill`、`CosSectionHeader`、`CosGradientPanel`、`CosSafetyConfirmDialog`、`AppPage`。
- mobile 是主要設計基準；web 使用 phone-like constrained frame。
- 保留 loading、empty、error、failure、destructive confirmation 狀態。
- 新增 API-backed 功能時，同步更新 Flutter model/repository/provider/UI、backend endpoint、schema/migration。
- 修改 privacy/social/location 時，檢查 current user、blocked users、follows、circle membership、visibility、expiry。
- Release build 必須指定 `API_BASE_URL`，且必須使用 HTTPS。
- 不要提交 `.env`、`local.properties`、簽章檔或真實 API key。

## 驗證

優先執行：

- `flutter analyze`
- 相關 `flutter test`
- `integration_test` 內相關測試
- 修改 Express/API/privacy 行為時執行 backend smoke/manual tests

如果無法驗證，請明確說明沒跑哪個命令與原因。
