# 官網 Google Play 測試連結

2026-11-19 使用者提供正式連結，並回報版本已送審；未透過本輪操作變更 Play Console 的測試資格或發布狀態。

- Android 商店：https://play.google.com/store/apps/details?id=com.hikakineame.coscircle
- 網頁加入測試：https://play.google.com/apps/testing/com.hikakineame.coscircle
- 官網：https://coscircle.app/
- 加入指南：https://coscircle.app/android-testing.html

首頁加入兩個直接入口；指南中的加入測試、商店安裝按鈕直接包含 href，不需 JavaScript 也可使用。保留三步驟：確認同一 Google 帳號 → 加入測試 → 安裝。未提供群組／申請連結，不捏造群組入口，也不把有網址寫成保證所有人都能加入或已通過審查。沒有資格的使用者可透過既有意見回饋聯絡開發者確認名單。

保留 `android-testing.json` 的 enroll=null，提供真實 optIn 與 store。JavaScript 準備狀態改為這兩個連結皆有效，不再因缺少群組連結而停在「準備中」。首頁與指南資產版本使用 20261119-2。頁尾也加入已部署的兒童安全政策連結。

正式 GCP project cos-circle、account idick7069@gmail.com、VM coscircle-free-vm、zone us-west1-b。使用官網專用部署，保留原有 App、後台與 API：

- 新 web release：`/var/www/coscircle/releases/official-a6qWXFjb`
- 前 web release：`/var/www/coscircle/releases/public-legal-wA6NIi2H`

部署安裝器核對各法律頁來源內容。打包測試、JavaScript／shell 語法及變更空白檢查通過。

公開真實 Chrome 驗證工具：`tools/review/verify-android-testing-links.mjs`；驗證及畫面輸出：`build/android-testing-links-20261119/`。測試包含首頁／指南的手機、桌面、停用 JavaScript 版本，正確來源 HTML、兩個連結、無水平溢出、動態設定及實際 Google 頁面分頁。Google 帳號是否取得測試資格不屬於本次驗證。
