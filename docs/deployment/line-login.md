# LINE 登入：Web 與 Android（2026-11-16）

## 目前狀態

程式已新增 Web OAuth 與 Android 動態 Channel ID。新 Channel `2012627208` 與 secret 已透過安全工具設定至正式 GCP；2026-11-16 已確認 Web／Android 登入開關啟用、Web 授權導向正確。尚未完成真實 LINE 授權驗證。

原設定 `2011925571` 只代表歷史設定值，未確認可管理或有效。2026-11-15 正式 DB 的 LINE identity 數為 0。切換設定工具會重新檢查此數量，若已有 LINE 身份且要換 Channel，會停止，避免造成帳號無法登入。

## 1. 建立 Channel

在 [LINE Developers Console](https://developers.line.biz/console/) 登入後：

1. 選擇長期使用的 Provider（例如自己的專案／品牌）；LINE 使用者 ID 與 Provider 有關，後續不要任意更換 Provider。
2. 點 Create a new channel，選 **LINE Login**，不是 Messaging API。
3. 名稱填 `CosCircle`，說明可填「Cosplay 活動預定、同坑交流與現場認親工具」。開發者類型、地區與聯絡信箱按實際資料填寫。
4. App types 同時勾選 **Web app** 與 **Mobile app**，由帳號持有人自行確認條款並建立。
5. 在 Basic settings 記下新的 **Channel ID**。這是公開識別碼，可回覆給開發者；Channel secret 不要貼到聊天或放進 App。

設定值：

| 項目 | 值 |
|---|---|
| Web Callback URL | `https://coscircle.app/api/auth/line/web/callback` |
| Android Package names | `com.hikakineame.coscircle` |
| 隱私政策 | `https://coscircle.app/privacy.html` |
| 服務條款 | `https://coscircle.app/terms.html` |
| OAuth scopes | `profile openid`（不申請 Email） |

先保留 Developing，用 Channel 管理員帳號測試。其他人若要測試，需依 LINE Console 角色設定加入可測試帳號，或確認後發布 Channel。LINE Channel 是否發布與 Google Play 測試軌道是不同設定。

若 Android Package signatures 欄位有設定限制，須加入實際簽章的 SHA-1 Base64。上傳金鑰的值見 [Google Play 簽章文件](google-play-release.md)；Play 安裝版本使用 Google 的 App signing certificate，需再加入其對應 signature。不要把 SHA-256 或冒號格式 SHA-1 誤填為 LINE 的 Base64 signature。

## 2. 安全設定正式 GCP

在本人終端機執行：

```sh
cd /Users/frank/FlutterProjects/coscircle
python3 deploy/gcp/setup-line-login-on-gcp.py
```

依序輸入新 Channel ID 及 Channel secret。secret 輸入隱藏，經 SSH stdin 傳輸，不放在命令參數或聊天中。程式只更新正式 `/etc/coscircle/api.env` 的三個 LINE 設定，先保留 root-only 舊設定並重啟 API：

- `LINE_LOGIN_ENABLED=true`
- `LINE_LOGIN_CHANNEL_ID`：新 Channel ID
- `LINE_LOGIN_CHANNEL_SECRET`：新 Channel secret

GCP project 為 `cos-circle`、account `idick7069@gmail.com`、VM `coscircle-free-vm`、zone `us-west1-b`。Firebase project `coscircle` 另外管理 Android 通知，與 LINE Provider／Channel 無關。

## 3. 程式流程

### Web

1. 登入頁讀取公開 `/api/auth/line/config`；Web 設定未齊時隱藏 LINE 按鈕，Email 登入仍可用。
2. 點擊 LINE 登入，POST `/api/auth/line/web/start`。後端檢查 HTTPS／Origin，建立 10 分鐘有效的 state、PKCE verifier 與 nonce，並設定 Secure／HttpOnly／SameSite=Lax 的 browser-binding cookie。
3. 瀏覽器前往 LINE 授權。Callback 在後端檢查 state 與 browser binding，授權碼只能領取一次；以 Channel secret／PKCE 交換 LINE token，再核對 channel、有效期、profile scope、ID token nonce／issuer／audience／subject。
4. 驗證結果短暫存 DB；redirect 回 App 的 URL 只帶結果標記與內部返回路徑，不帶 LINE token 或 CosCircle session。
5. App POST `/api/auth/line/web/complete`，領取一次性結果，沿用既有社群登入交易建立／恢復帳號、保存 CosCircle session，並依 onboarding 狀態進入對應頁面。

暫存表 `line_web_logins` 需套用 `backend/db/migrate_line_web_login.sql`；未領取或過期內容由定期維護清理。Callback 在 Nginx 設為不記錄 access log，避免授權碼出現在一般存取記錄。

### Web 綁定既有信箱帳號

1. 使用 Email／密碼登入原帳號，開啟「設定 → 登入方式 → 綁定 LINE」。
2. 已登入的瀏覽器 POST `/api/me/auth-identities/line/web/start`，暫存紀錄標為 `link`，綁定原 user ID、目前 session 的 SHA-256 與安全 cookie。
3. 完成 LINE 授權後共用既有 callback 驗證，回到 `/app/#/login-methods`，不建立帳號或發行新的登入 session。
4. 顯示密碼確認對話框；輸入原帳號的 Email 登入密碼，再 POST `/api/me/auth-identities/line/web/complete`。
5. 一次性領取授權結果，核對目前 user／session，沿用 `linkLineIdentity` 交易驗證密碼並新增 LINE identity。原帳號資料與 session 保留，日後兩種方式都解析到原 user ID。

LINE 已綁定其他帳號、原帳號已綁另一 LINE、密碼錯誤或帳號停權時拒絕操作，不自動搬移或合併帳號。取消授權會回到登入方式；切換帳號／session 後舊流程不能完成。密碼錯誤消耗本次一次性結果，須重新綁定。授權完成後的綁定結果保留 5 分鐘；一般登入結果仍為 1 分鐘。綁定逾時回傳 410，不清除目前信箱登入。

既有 DB 需另套用 `backend/db/migrate_line_web_link.sql`；全新 schema／login migration 已包含欄位。部署程式檢查欄位，避免重複 ALTER。

### Android

原生 SDK 先從正式 API 取得已開放的 Channel ID，不再預設使用舊號碼。SDK 取得的 LINE access token 送至既有 `/api/auth/social`；伺服器驗證後，和 Web 使用同一段帳號查找／建立流程。

新 AAB 為 `1.0.0+2`，套件 `com.hikakineame.coscircle`，需安裝此版才能使用動態 Channel 設定。既有已編譯 App 不會因後端設定改變而自動換掉其內嵌 SDK 初始化方式。

### 帳號規則

相同 Provider、同一 LINE 使用者經 Web／Android 登入，會查找同一個 LINE identity。已有 Email 帳號的使用者若要共用原帳號，先用 Email 登入 Web 或 Android，從「設定 → 登入方式」綁定 LINE 並驗證原帳號密碼；不因顯示名稱或 Email 相似而自動合併帳號。Web 與 Android 都可綁定；刪除帳號再驗證流程保留。

### Web／App 解綁 LINE

從「設定 → 登入方式 → 解綁 LINE」輸入原帳號 Email 登入密碼並確認。共用 `DELETE /api/me/auth-identities/line`，使用目前登入 session 與 HTTPS，沿用身份管理的速率限制。解綁不需要重新取得 LINE token，也不依賴 LINE 服務可用狀態。

後端交易先鎖定目前帳號，確認帳號有效且有可用的 Email identity／password hash，再驗證密碼。只有 LINE 的帳號不能解綁；目前沒有從 LINE-only 帳號新增 Email／密碼的介面，頁面會顯示限制，不能將其視為已有設定入口。

解綁僅移除目前帳號的 LINE identity 與未完成的 Web 綁定紀錄；保留 user ID、Email 登入、目前 session、個人資料、好友、小圈圈及預定。對原始 provider 為 LINE、但另有 Email identity 的舊資料，將 legacy provider 欄位改指向同帳號的 Email identity，避免服務重啟回補 LINE。無 DB schema 變更。

- 密碼錯誤：403 `reauthentication_required`，保留綁定。
- 無可用 Email／密碼：409 `email_login_required`，保留 LINE 登入。
- 已解綁後重複操作：仍須驗證 Email 密碼，成功回傳 `unlinked=true`。
- 此操作解除 CosCircle 的登入身份關聯；不等於取消 LINE 帳號端對 Channel 的授權。之後若直接用未綁定的 LINE 登入，會依一般首次登入規則建立新帳號；要共用原帳號請先用 Email 登入再綁定。

## 4. 驗證進度

- 後端 213 項測試、登入相關 Flutter 39 項測試通過，Flutter analyze 無問題。
- 覆蓋 Web state／browser binding／PKCE／nonce／重複 callback／一次性領取／逾時／取消／Origin／HTTPS 與未設定時關閉。
- 新 Channel 已設定，仍需本人完成 Web 掃碼登入與 Android LINE App 授權、拒絕／取消及回到 CosCircle 的實測；不能用 mock 測試代替這些成功證據。

參考：[建立 LINE Login](https://developers.line.biz/en/docs/line-login/getting-started/)、[Web OAuth 流程](https://developers.line.biz/en/docs/line-login/integrate-line-login/)、[PKCE](https://developers.line.biz/en/docs/line-login/integrate-pkce/)。

新 Channel `2012627208` 已設定完成。正式 `/api/auth/line/config` 回傳 `enabled=true`、`webEnabled=true`；同源 Web start 回傳 200，授權網址的 client_id、callback、scope 與 PKCE S256 均正確。secret 未輸出。仍需本人完成真實登入驗證。

解綁功能與 Android `1.0.0+3` 的發布紀錄：[LINE 解綁正式部署](line-unlink-2026-11-16.md)。
