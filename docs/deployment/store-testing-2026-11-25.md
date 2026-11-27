# 商店測試版 1.0.1（10）準備與上傳狀態

日期：2026-11-25，台北時間。來源 commit `075d3b8`。本文記錄當日測試版操作；正式 App Review 已於 2026-11-26 提交，詳見 [正式送審紀錄](app-store-release-readiness-2026-11-25.md)。

## 已完成

- Android AAB：`build/releases/android/CosCircle-1.0.1-10.aab`，套件 `com.hikakineame.coscircle`，正式 upload 簽章、bundletool validate、非 debuggable、targetSdk 36 與 64-bit ELF 16KB 對齊檢查通過。
- Android SHA-256：`66c6dd0b94c82e230e78f9162c8311c57f8741793d67b4fd6e7f7826b9e88239`。
- iOS：`build/releases/ios/CosCircle-1.0.1-10.ipa`，Bundle ID 同上，團隊 `UF6P9B6PBV`，最低 iOS 15。
- iOS SHA-256：`09128fcb51588d2e23224ce8bfcecd674f806f92f4814ce15ff9b3c1bab84ba1`。
- archive 及實際匯出 IPA 均核對為 1.0.1（10），codesign 嚴格／深度檢查通過，含 Apple 登入與 production APNs，get-task-allow 未啟用；Firebase 設定正確，未包含後端簽章私鑰。archive 檢查確認沒有未使用的 Always Location API。
- 版本說明：`build/releases/CosCircle-1.0.1-10-release-notes.txt`；TestFlight 測試重點：`build/releases/CosCircle-1.0.1-10-testflight-notes.txt`。
- 已清除可重建的 Flutter、Xcode 與舊 Gradle 轉換快取；保留簽章、profile、受限設定與已驗證產物。

## 已完成上傳與 Google Play 發布

- 2026-11-25 12:45（台北時間），Xcode 回報 `Upload succeeded`、`EXPORT SUCCEEDED`，Apple 已接收 1.0.1（10）。上傳工具當時回報套件開始處理；不代表目前已可供 TestFlight 測試者下載。
- Google Play 使用系統檔案選擇器上傳已驗證 AAB，沒有開啟擴充功能的全域本機檔案存取權限。
- 內部測試 track `4700802202821027903`、release `2`：已儲存並發布，後台顯示有效、最新版本 1.0.1（10）、提供給內部測試人員。
- 同一套件已升級到既有 Alpha 封閉測試 track `4700272541770339756`，release `2`，沿用原測試人員，推出比例 100%。發布總覽只提交這一項 Alpha 變更，已顯示「審查中的變更」，包含快速檢查與審查等待；不能宣稱 Alpha 測試者已可下載。
- 繁體中文版本資訊已填入 Google Play；未發布正式版、未新增或邀請測試者。

## TestFlight 處理及群組

- Apple 網站驗證已完成，build `c73f1ad4-216c-4c85-821b-e7cf50c2580b` 已處理完成；內部顯示「準備測試」，外部顯示「準備提交」。
- 「CosCircle 內部測試」（`e8343cbc-84f9-4abb-b3f6-47aad6886bda`）已加入 build 10；既有開發者帳號 1 位顯示「已邀請」。沒有開啟自動散佈其他版本。
- 已儲存繁體中文測試重點。
- 依使用者選擇建立「CosCircle 公開測試」（`14845394-c257-4edf-9875-e80fe84410ed`）。build 10 已加入並成功送出首次 Beta 審查，Apple 顯示「等待審查」。
- Beta 描述、聯絡資料與專用審查登入資料已提交。電話國碼前補上 `+` 後通過 Apple 格式檢查。
- 已建立公開連結：https://testflight.apple.com/join/j6tyGKHr ，選擇「開放給所有人加入」，未額外設定加入條件或人數限制。Apple 顯示「此群組具有核准的建置版本後，測試人員才能加入公開連結」；2026-11-25 確認時等待審查；未重新確認前，不能宣稱已能加入或下載。

## Apple 專用審查資料

- 使用者授權後，正式 MySQL 完整備份至 VM 的受限目錄 `/var/backups/coscircle/apple-review-Y9kJ1fxc`，壓縮檔完整性檢查通過。
- 新建 2 組 Apple 審查帳號、2 組示範帳號，均無管理員權限；示範帳號不允許登入。審查憑證僅保存在 VM root-only 設定檔，不寫入 Git 或本文件。
- 建立隔離示範活動 `641`、小圈圈 `13` 及其預定、關係與動態資料。建立前後核對原 Google 審查帳號的密碼、session 與資料存取權保持不變。
- 建立工具：`tools/review/prepare-apple-review.mjs`，僅允許在正式 VM 以 root 指定 `--prepare` 使用既有受限環境設定執行。可重跑並驗證資料歸屬；不改動一般使用者。密碼與邀請碼隨機產生，錯誤不印出資料庫或憑證內容。
- 兩組審查帳號皆已透過正式 HTTPS API 驗證：登入、個人資料、動態與小圈圈回傳 200，能看到隔離示範動態，管理員端點回傳 403。VM 本機回連檢查曾逾時，外部 HTTPS 驗證已成功。
- 本人可在互動式終端機執行 `python3 tools/ios/show_apple_review_access.py`，只顯示 Apple 主審查帳密；拒絕非互動輸出，不保存本機憑證檔案。

現有安裝包、封存與簽章保留，不必重建。
本機機器可讀狀態：`build/private/ios/store-build10-status.json`。
