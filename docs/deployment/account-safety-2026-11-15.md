# 正式 GCP 帳號刪除與檢舉路由

## 發布結果

2026-11-15 已發布正式 GCP `cos-circle`／`coscircle-free-vm`／`us-west1-b`。

- API：`/opt/coscircle/api/releases/account-safety-VLlwcPrk`
- 前版：`/opt/coscircle/api/releases/age-visibility-QvN1SyNi`
- 僅 root 可讀 DB 備份：`/var/backups/coscircle/account-safety-DKAk9gWu/coscircle.sql.gz`
- 正式 server SHA-256：`349f76c9b666e2565673acb64c8d41ca597d7c9726e740d63a39597822e351c3`
- 原版 SHA-256：`ff683e7c1e9e514970f3e81f8497e72001b36e2788d771b5abadfa2dc90fe334`

只部署帳號安全所需的最小差異，保留原正式 API 的其他功能；審閱用 patch 為 `deploy/gcp/account-safety-production.patch`。部署腳本檢查原始碼 SHA、共用 transaction helper、部署鎖並備份 DB，重啟後若健康檢查或 QA 失敗會回復前版 API。新增表不自動刪除。

## 路由

- `POST /api/me/delete-account`：需登入、`confirmation: "DELETE"`，再以 Email 密碼或已綁定 LINE 的有效 access token 重新驗證。保護最後一位啟用中的管理員；成功回傳 204。
- `POST /api/reports`：支援 `user`、`booking`、`circle`，檢查目標可見性、封鎖、同日預定與圈內資格，阻擋自我及重複檢舉。
- `GET /api/admin/reports`：管理員檢舉清單及審核紀錄。
- `POST /api/admin/reports/:id/review`：管理員審核，版本比對避免覆蓋其他審核結果；支持無處分、停權、移除預定或小圈圈。

既有條款路由保持不變。一般路由均需登入，管理路由另需管理員權限；刪除與檢舉設有限流。不把本機新版 server 整份覆蓋到正式環境。

## 資料與檔案

備份後套用兩份可重跑的 migration：`migrate_account_deletion.sql`、`migrate_content_reports.sql`，共新增五張表。既有 `user_legal_consents` 與外鍵已檢查。

刪除帳號會移除身份、驗證連結、預定、社交、位置、自己擁有的圈圈與活動投稿，清除相關檢舉證據中的個人文字／快照；保留匿名案件狀態。管理員刪除帳號也使用相同服務與最後管理員保護鎖。

圖片上傳改為先記錄擁有者，再寫入檔案。刪除後由 durable queue 清理本人擁有的檔案；每十分鐘重試並清除已超過 90 天的檢舉證據。舊版圖片若缺乏可信擁有者記錄，不僅憑公開 URL 推定權屬或刪除他人檔案；可辨認的舊引用記錄到 `account_legacy_upload_review`，後續仍需人工確認擁有權。不能把這些舊檔案宣稱為已全部刪除。

## 驗證

- 完整後端測試 195 項通過（包括帳號刪除／檢舉／條款相關 81 項）。
- 正式 MySQL 與 API 專用 QA：匿名存取被拒、上傳擁有者追蹤、三種目標檢舉、自我與重複檢舉、封鎖與圈內可見性、活動日隔離、管理員權限、審核歷程與版本衝突。
- 專用 QA 帳號刪除：錯誤確認文字／密碼被拒，正確密碼成功；原 session 隨即失效；關聯資料、已追蹤本人圖片與檢舉個人證據確實清除，另一個 QA 帳號圖片保留。
- QA 建立的三個帳號、未公開場次、檢舉與上傳檔案全部清理。沒有刪除或修改真實使用者帳號。
- QA 執行紀錄：上述 root-only 備份目錄的 `qa.log`。
- 專用驗證腳本 `deploy/gcp/safety-production-qa.mjs` 隨部署安裝至 API `scripts/`，須明確傳入 `--run-production-qa`；不應在其他路徑直接執行。
- 真實 LINE 帳號重新授權刪除尚未操作；LINE 權屬與錯誤處理目前由自動測試覆蓋。

## Android 候選版

先前 AAB 已設定 `ENABLE_ACCOUNT_SAFETY=true`，本次只更新後端，無需因路由補齊重建。送測前仍須設定 Google Play App signing certificate 到第三方服務，並以 Play 簽章版本進行實機驗證。
