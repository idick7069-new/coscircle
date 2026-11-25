# 1.0.1 (6) 正式安全更新

日期：2026-11-24（台北時間）。僅使用正式 GCP `cos-circle`／`coscircle-free-vm`，不使用測試後端。

## 已部署與驗證

- API：`/opt/coscircle/api/releases/release-security-RgMe3xgy`。
- Web 與管理頁：`/var/www/coscircle/releases/release-security-qHHbbgJ3`。
- 受限備份：`/var/backups/coscircle/release-security-mpCn1E6A`，包含部署前完整 SQL、設定及工作階段快照，不可下載到公開目錄或納入 Git。
- 232 項後端測試通過；Flutter 214 項測試通過，靜態分析通過。兩套正式 Web 建置成功。
- GCP 候選與切換後皆以實際 MySQL／HTTP 驗證：一般帳號無法讀取測試活動、圈圈或測試名片，審查帳號仍可讀取。原審查密碼雜湊核對一致，沒有登入或重設原審查帳號。
- 17 個既有測試帳號隔離，僅 28、29 有審查資料存取資格；管理員亦可查看。其餘測試帳號不得登入。審查內容與社群關係保留。
- 原有可用登入憑證經雜湊轉換後仍有效，13 個非審查測試登入受到阻擋。DB 不再保存可直接登入的原始憑證。最長 30 天到期。
- 新版 Android／iOS 使用安全儲存區並遷移舊偏好憑證；Web 使用 Secure、HttpOnly、SameSite Cookie，登出撤銷工作階段。
- 三個 nginx uploads 路由均改為後端授權，原始無簽章網址回傳 404／no-store。小圈圈圖片需授權，短連結最長 5 分鐘，下載時再次檢查封鎖與工作階段。舊版本產生的瀏覽器快取、截圖及下載副本無法遠端收回。
- Facebook 登入停用；內容修改同意規則與停權篩選已部署。
- 臨時 QA 帳號、活動、圈圈與合成圖片已清理；原審查資料未刪除。

## 建置產物

- Android：`build/app/outputs/bundle/release/app-release.aab`，1.0.1／6，套件 `com.hikakineame.coscircle`。
- AAB SHA-256：`3c670225e8ca674a6b29927abd1c1a7efdd7b78a17332da125c1f50659677d3c`。
- 正式 upload certificate 一致、bundletool validate 通過、targetSdk 36／minSdk 24、非除錯、64 位原生程式庫 16KB 對齊通過。
- 同一 AAB 產出的裝置驗證 APK：`build/private/release-security/CosCircle-1.0.1-6.apk`。已更新到 Pixel 9a，確認 versionCode 6／versionName 1.0.1，Activity 啟動成功、程序持續存活，未發現 FATAL EXCEPTION／MissingPluginException／缺類別等啟動錯誤。此為啟動 smoke，並非所有頁面操作或 Play 簽署後配送包的完整驗證。

## 商店進度（必須依實際結果更新）

- iOS 1.0.1 (6)：IPA 已建立，正式簽章、production APNs、Apple 登入 entitlement、Firebase 配置、無後端私鑰、無 Always Location API 均驗證通過。`build/ios/ipa/CosCircle.ipa`。上傳遭 Apple 拒絕：`exportArchive Failed to Use Accounts`，必須在 Xcode 重新驗證 UF6P9B6PBV 帳號；尚未上傳成功。
- Google Play：內部測試草稿 `releases/2/prepare` 已儲存「1.0.1 (6)－登入與隱私安全更新」及繁中版本資訊；檔案上傳工具兩次逾時，尚未上傳成功，未發布。原內部與 alpha 版本皆為 3 (1.0.0)，測試人員未變更。
- Chrome 檔案上傳工具無法完成檔案選擇，不能將草稿視為發布成功。
- App Store Connect 網頁登入亦已過期。不能以既有 1.0.0 (5) 上傳成功推斷本次成功。
- Apple／LINE 真實授權與正式 APNs 推播抵達實體 iOS 裝置，未在本輪宣稱通過。

## 後續部署約束

`MEDIA_SIGNING_KEY` 必須是獨立的 32-byte Base64 隨機密鑰並持續保留，不可每次部署重產。先執行可重入 migration prepare，候選驗證後才 activate；不可在舊服務仍對外時先雜湊全部工作階段。rollback-sessions 僅恢復仍匹配部署前雜湊的工作階段，不覆寫並行登入／登出。
