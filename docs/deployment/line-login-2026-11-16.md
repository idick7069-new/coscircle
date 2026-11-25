# LINE Web／Android 重接部署紀錄

狀態：程式與新 Channel `2012627208` 已在正式環境啟用，**尚未完成真實 LINE 授權**。

- API release：`/opt/coscircle/api/releases/line-web-VOXmjwIw`
- API 前版保留：`/opt/coscircle/api/releases/account-safety-VLlwcPrk`
- DB 備份：`/var/backups/coscircle/line-web-PnllDgIF/coscircle.sql.gz`（root-only）
- API server SHA-256：`71d7281988d55a9367a11177f3e9a3fa396ef3bcfb608cb4325e6c159f7a40be`
- Web release：`/var/www/coscircle/releases/user-web-0ttT8r6l`
- Web main SHA-256：`32b80a605a67ac10732a199a03f2bd6d437913a05f210bcc639a74361807bcbe`
- Android：`1.0.0+2`，套件 `com.hikakineame.coscircle`；新 AAB 維持原 upload key 簽章。

部署僅更新 LINE 所需 API 差異、暫存表及 User Web。官網、管理後台與既有 Email 登入保留。Callback 的 access log 關閉，Nginx 設定有備份並通過 `nginx -t`。

設定前正式 HTTPS 檢查：`/api/auth/line/config` 回傳 enabled=false／webEnabled=false／channelId=null；同源啟動在未設定時回傳 503，外站 Origin 回傳 403。這些結果只證明路由與未啟用時保護正常，不代表 LINE 真實授權成功。

測試：完整 Node 201 項；Flutter 登入／綁定／狀態回歸 28 項；Flutter analyze 無問題。AAB 經 jarsigner、bundletool validate、64-bit ELF 16KB 對齊驗證。新 Web 編譯成功；本輪瀏覽器自動化連線不可用，尚未完成真人 Web／Android LINE 登入。

後續按 [Channel 建立與設定說明](line-login.md)，ID／secret 已安全設定，接下來須由本人完成 Web 與 Android 真實授權。不要把 secret 放入聊天、Git 或客戶端。

使用者已執行安全設定工具並成功更新 Channel `2012627208`；先前設定備份：`/var/backups/coscircle/line-config-20261116021314.env`（root-only）。本機 gcloud 日誌曾因磁碟空間不足出現警告，沒有影響遠端設定完成。

設定後 HTTPS 驗證：config 200，`enabled=true`、`webEnabled=true`、`channelId=2012627208`；同源 start 200，指向 `access.line.me`、新 client_id、固定 callback、`profile openid`、PKCE S256，並設定 Secure／HttpOnly cookie。此檢查未進行使用者授權，不代表真實登入成功。

Android arm64 正式簽章 APK 已建置：`build/app/outputs/flutter-apk/app-release.apk`。目前 ADB 無連線裝置，尚未安裝或完成實機授權。


## Web 綁定既有信箱帳號：第二次發布

正式部署完成。使用者入口：先用信箱登入 Web → 設定 → 登入方式 → 綁定 LINE → LINE 授權 → 回到登入方式輸入原信箱密碼。

- API release：`/opt/coscircle/api/releases/line-link-jwd6kLbu`；上一版 `line-web-VOXmjwIw` 保留。
- DB 備份：`/var/backups/coscircle/line-link-Wo1jUCx3/coscircle.sql.gz`（root-only）。
- API server SHA-256：`71987b18e23617e1de41d9d426d0e2f3181aa345e359e042b5beb371c3d1aadf`。
- Web release：`/var/www/coscircle/releases/user-web-o6qq5z9b`；上一版 `user-web-0ttT8r6l` 保留。
- Web main SHA-256：`aacc5414f5bf66115f4924c5b08d952a1fda4ea44d2c5b5887ad97dcc76a3c30`。
- 新增 migration：`backend/db/migrate_line_web_link.sql`；部署前檢查欄位，僅新增 purpose、原 user ID、原 session hash，不修改既有帳號關係。
- 部署腳本：`deploy/gcp/install-line-web-link-on-vm.sh`；最小正式 server patch：`deploy/gcp/line-web-link-production.patch`。

驗證：Node 207 項、Flutter 登入相關 33 項通過；Flutter analyze 無問題；Web release 建置完成。正式專用 QA 建立單一暫時帳號，驗證已登入 start、原帳號／session 紀錄、取消授權回到登入方式、匿名／外站拒絕，以及綁定逾時回傳 410 而原 session 仍可取得同一 user ID。QA 沒有新增 LINE identity，所有暫時帳號與綁定紀錄已清除。腳本為 `deploy/gcp/line-web-link-production-qa.mjs`。

仍須由使用者本人完成真實 LINE 授權與正確密碼的最後一步；上述測試不能代替 LINE Console 狀態、本人 QR／LINE App 授權的實測。已有 Email 帳號不可先以未綁定的 LINE 建立另一帳號，再期待自動合併。
