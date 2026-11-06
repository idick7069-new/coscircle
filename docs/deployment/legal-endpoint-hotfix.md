# 法律同意端點最小修補

本流程只處理新版 App 的 `/api/me/legal` 404，不等同完整帳號安全功能上線。刪除帳號、檢舉與社群寫入限制仍依 [帳號安全部署文件](/Users/frank/FlutterProjects/coscircle/docs/deployment/account-safety.md) 另行完成與驗證。

## 範圍

部署來源必須是正式主機當前 release 的精確副本，不可打包目前工作目錄的整份 `server.js`。

只新增法律模組 import、在既有驗證 middleware 後掛載 GET 與 POST，以及在服務監聽前檢查同意資料表。新增 `legal-consent.js` 與單一 `migrate_legal_consent.sql`。不變更 nginx、前端網站、既有 API、排程爬蟲、相依套件或環境設定。

目前新版 App 仍要求明確同意，GET 不會寫入同意紀錄。本修補不啟用新的社群寫入 middleware，既有客戶端與 API 寫入保持原先行為，不能宣稱已完成全體客戶端的服務端同意管制。

## 準備與檢查

1. 確認正式 VM、目前 release、原始 `server.js` SHA256，以及 users 主鍵、狀態與 session 欄位。
2. 下載當前非機密 server 原始碼，以 `deploy/gcp/patch-legal-server.mjs` 產生修補。來源已含法律程式、驗證邊界變動或重複時必須停止。
3. 封裝精確三檔，不包含目錄項目、連結、環境檔或其他檔案。
4. 執行 `patch-legal-server.test.mjs`、`legal-hotfix-overlay.test.py`、法律模組聚焦測試與 shell 語法檢查。
5. 獨立檢查最終三檔、部署腳本與差異，記錄封裝 SHA256。

三檔為 `src/server.js`、`src/legal-consent.js`、`db/migrate_legal_consent.sql`。

## 正式切換

`deploy/gcp/deploy-legal-on-vm.sh` 只在 VM 以 root 執行。必須提供修補包路徑、`EXPECTED_OVERLAY_SHA256`，及 `EXPECTED_API_RELEASE`、`EXPECTED_SOURCE_SHA256` 至少一項。實際修補建議同時提供 release 與原始碼雜湊。

腳本先鎖定部署，將修補包複製到 root 專屬備份目錄並核對雜湊。驗證檔案白名單、SQL 與精確來源轉換後，備份正式資料庫、共享照片與設定，並驗證壓縮檔。備份含個資與機密，不能放進 Git 或對話。

接著複製目前 release，保留共享 uploads 連結與原有相依套件，套用新增資料表，再以原子方式切換 API 連結及重啟服務。健康檢查或未登入路由檢查失敗時，回復原 API 連結與服務。回復不會刪除新增的同意資料表，不能為回復程式而抹除同意紀錄。

## 修復驗收

使用專用 QA 帳號驗證 HTTPS 查詢回傳正確版本與 `accepted:false`，錯誤同意內容回傳 400，舊版本回傳 409，且不會改變紀錄。

讓模擬器中的 QA 使用者明確勾選並送出同意。確認進入 OOBE 或主頁，之後查詢為 `accepted:true`，重開仍有效。回應須有 `Cache-Control: no-store`。不可預設勾選、自動同意或移除 gate 來通過驗收。

只測未登入 401 或健康檢查不夠。舊後端也可能回傳相同結果，必須驗證 authenticated GET 與實際明確同意。

## 本輪紀錄

基準 release 為 `20261028095204`。修補前正式主機沒有法律模組、路由或同意資料表，專用 QA 帳號呼叫得到 HTTP 404。修補後的 release、備份位置及實際驗證結果以 `.audit/legal-404-fix.tsv` 與本輪 QA 報告記錄為準，不以這份操作文件預先宣告成功。
