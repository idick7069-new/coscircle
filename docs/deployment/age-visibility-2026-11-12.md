# 年齡隱私與預訂體驗發布

2026-11-12 已更新正式 GCP API 與 Web App。

- API：`/opt/coscircle/api/releases/age-visibility-QvN1SyNi`。只在原正式 API 上套用年齡公開欄位及公開資料遮蔽，保留原服務差異；必要 patch 為 `deploy/gcp/age-visibility-production.patch`。
- 原 API：`/opt/coscircle/api/releases/partner-XnNVruDQ`，保留作回復。新增 `age_public` 為相容欄位，回復 API 時不刪除欄位或使用者資料。
- 正式 DB 備份：`/var/backups/coscircle/age-visibility-1CihzB6M`，僅 root 可讀。先驗證完整備份再執行可重複的 `migrate_age_visibility.sql`。
- Web：`/var/www/coscircle/releases/user-web-jDoFyMKH`；上一版 `/var/www/coscircle/releases/official-ZOv4mIPw` 保留。官網內容沿用既有版本。

Flutter 完整 440 項測試、後端完整 195 項測試通過，Flutter 分析無問題。另以兩個本輪專用 QA 帳號呼叫正式 API，確認私密年齡遮蔽、擁有者保留原值、舊版儲存不重設偏好、無效值回 400，以及重新公開；QA 帳號已清理，不使用真實使用者做修改驗證。

同作品 Coser 計數使用既有參加者 API，只計算可見、同場、同日、同作品的其他 Coser，依使用者去重；自由輸入時間不作精確重疊判斷。活動分頁新進入時預設今天，手動選日後本次瀏覽維持選擇。同坑雷達的共同作品改為實心亮色。預訂操作統一使用「發佈預訂／修改預訂／儲存預訂」。

Android APK 已建置，並於 2026-11-12 覆蓋安裝至 Pixel 9a；保留既有 App 資料，確認新版啟動並顯示於前景。
