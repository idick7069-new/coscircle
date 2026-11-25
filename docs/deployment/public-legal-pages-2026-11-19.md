# 公開隱私／條款／刪除帳號頁修復（2026-11-19）

已部署並驗證：

- https://coscircle.app/privacy.html
- https://coscircle.app/terms.html
- https://coscircle.app/delete-account.html

## 根因與修正

`deploy-official-site.sh` 先前只把首頁與 Android 測試指南複製到網站根目錄，法律頁與 CSS／JS 只有 `official/` 下的副本。Nginx 的一般路由遇到根目錄缺檔就回傳首頁，導致 HTTP 200 不能代表法律頁存在。

官網打包工具與安裝器現已要求根目錄包含 privacy.html、terms.html、delete-account.html、delete-account.js、legal.css；安裝後逐一比對實際服務內容。`official-site-packaging.test.py` 透過隔離 gcloud transport 執行真正打包流程，驗證根目錄及 official 副本內容一致，避免再漏檔。

新增五個精確 Nginx 路由，缺檔回傳 404，不採用首頁 fallback；隱私／條款／CSS 使用 no-cache，刪除頁及其 JS 使用 no-store。保留現有網站首頁、App、後台、API、LINE callback 設定與資料庫結構。文件仍沿用既有 2026-10-28 版本內容，本輪不新增法律政策承諾或改動 App 同意版本。

## 正式部署

- GCP project：`cos-circle`；account：`idick7069@gmail.com`。
- VM：`coscircle-free-vm`，zone `us-west1-b`，IP `34.187.168.222`。
- Web release：`/var/www/coscircle/releases/public-legal-Oc7a7CJd`。
- 上一版保留：`/var/www/coscircle/releases/user-web-QlxYPYOg`。
- Nginx／舊 release 路徑備份：`/var/backups/coscircle/public-legal-mXGp7T6R`。
- 安裝器：`deploy/gcp/install-public-legal-pages-on-vm.sh`；路由片段：`deploy/gcp/legal-public-pages.nginx`。
- `nginx -t` 通過；實際服務內容與來源逐檔比對通過；首頁、App main 與 admin main 的位元組比較一致，API release 未切換，health 正常。

## 公開 HTTP 驗證

- `/privacy.html`：200，`text/html`，SHA-256 `1a54435390472ab5bbca79436fbabcf8ef3f127120b4192c7747a36340ccb802`。
- `/terms.html`：200，`text/html`，SHA-256 `3bf72df7ae448a1ef5a672d41b95d061db095942e942350d5c547fb34c24c876`。
- `/delete-account.html`：200，`text/html`，SHA-256 `0511b7217e6be677909aaaea346f3814414fa87fd504f2ad3f1c79bf12587e7a`。
- `/delete-account.js`：200，`application/javascript`，SHA-256 `b3b67c51f58965e0d3c35586a33284b6848f46f5f5e2f441ad5927eeaf6910cf`。
- `/legal.css`：200，`text/css`，SHA-256 `91f270ae12162a130bca2450385a979e6e3ed90762cdbb469078981a8ecbc664`。

HTTP 詳細紀錄：`build/legal-pages-20261119/http-verification.json`。驗證包含公開網域與 Nginx origin，並核對完整頁面內容，不只檢查 200 狀態。

## 真實瀏覽器與刪除功能驗證

使用獨立 Chrome／Playwright context，以 390×844 與 1280×900 分別檢查三頁：標題及 H1 正確、完整 HTML 雜湊一致、CSS 載入、圖片正常、無水平 overflow，沒有 pageerror。已逐頁截圖並目視確認手機隱私頁與桌面刪除頁。

另建立一次性、非管理員、未完成條款同意的 QA 帳號，只用於真實公開刪除流程，沒有使用或刪除 Google Play 主／備用審查帳號。瀏覽器驗證：

1. Email／密碼登入後只顯示確認步驟，不自動刪除。
2. 取消後回到登入表單。
3. 非大寫 DELETE 或未完成確認時不能送出。
4. 錯誤密碼回傳 403 並保留確認頁面。
5. 正確密碼及確認後回傳 204，顯示帳號已刪除。
6. 刪除後再用同一帳密登入回傳 401。
7. localStorage／sessionStorage 不保存登入權杖。

QA 清理確認測試帳號已由正常刪除 API 移除，並刪除 VM 與本機暫存憑證；未留下測試登入帳密。

- 瀏覽器工具：`tools/review/verify-public-legal-pages.mjs`。
- 一次性帳號工具：`tools/review/public-legal-qa-account.mjs`（VM root、API env、明確 create／cleanup）。
- 截圖與驗證紀錄：`build/legal-pages-20261119/`。
- 測試用 Playwright 安裝於 `/private/tmp/coscircle-legal-browser`，使用既有 Chrome，沒有更改專案 npm 相依套件或使用者 Chrome profile。
