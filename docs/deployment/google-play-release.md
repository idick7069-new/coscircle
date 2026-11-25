# Google Play 簽章與 AAB

2026-11-18 內部測試操作步驟見 [Google Play 內部測試上傳](google-play-internal-testing.md)。以下保留既有簽章與產物歷史紀錄。

## Upload key

- 私鑰：`android/signing/coscircle-upload.jks`（RSA 3072，alias `coscircle-upload`）
- 密碼與路徑：`android/key.properties`
- 公開憑證：`android/signing/coscircle-upload-certificate.pem`
- 私鑰與設定為 600 權限，目錄為 700，已排除 Git。請把私鑰與密碼設定另外備份至你控制的安全儲存位置；不要放入聊天、Git 或官網。
- 這是 Play **上傳金鑰**；Play App Signing 的 App 簽章金鑰由 Google 管理。首次上傳後須從 Play Console 取得實際 App signing certificate 指紋，加入 Google Maps／Firebase／LINE 所需的 Android 憑證設定。只加入 upload certificate 不代表 Play 下載版本已可正常使用第三方 SDK。

公開憑證指紋：

```
SHA-1: 8B:DC:14:F3:DF:B0:52:88:36:1B:16:77:7A:8E:1A:34:88:C2:40:64
SHA-256: DC:7A:45:36:3D:F2:3B:A2:1D:05:84:5F:86:F0:8C:57:09:55:BE:DC:25:B8:6E:B8:50:07:D8:0F:39:58:B7:A1
LINE Android signature (SHA-1 Base64): i9wU89+wUog2GxZ3eo4aNIjCQGQ=
```

## 建置

```sh
python3 tools/android/build_play_bundle.py
```

預設 Flutter 位置為專案同層的 `flutter/bin/flutter`，可用 `FLUTTER_BIN` 覆寫。Maps key 由 `ORG_GRADLE_PROJECT_GOOGLE_MAPS_API_KEY` 或既有專案設定取得，不將值放入命令參數或文件。

- 套件名稱 `com.hikakineame.coscircle`
- 版本 `1.0.0+1`；如果 Play Console 已使用 versionCode 1，需遞增後重建。
- minSdk 24、targetSdk 36
- 正式 GCP API `https://coscircle.app/api`
- LINE 登入與 account safety 入口均啟用
- 輸出 `build/app/outputs/bundle/release/app-release.aab`

## 發給測試者之前

1. 正式 GCP 的刪除帳號、檢舉及管理員審核路由已於 2026-11-15 補齊，資料表與專用 QA 流程驗證通過。見 [部署紀錄](account-safety-2026-11-15.md)。AAB 位元組未變，不需要為這次後端部署重建；仍需完成下列 Play 憑證與實機驗證。
2. 在 Play Console 建立 App、啟用 Play App Signing，完成必要資料及內部測試名單。
3. 將 **App signing certificate** 加入第三方服務的憑證限制；上傳金鑰與 Google 實際發送給使用者的 App 簽章不同。
4. 安裝 Play 產生的版本，實測登入、LINE、地圖、通知、圖片上傳、檢舉與刪除測試帳號。
5. 本輪未連接 Android 裝置，未做 release 實機測試。正式簽章與既有 debug App 不同，不能直接覆蓋安裝；不要為測試自動解除安裝而丟失現有本機資料。

參考：[Flutter Android release](https://docs.flutter.dev/deployment/android)、[Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756)。

## 舊套件產物驗證結果（移轉前）

- AAB 63,532,957 bytes；SHA-256 `1ced7d58294a72b9fa07b0bc267df2ff0bd59d724d40e5a3f37ab993d113b005`。
- `jarsigner` 驗證通過，實際 signer certificate 與本輪 upload certificate 相符。
- Google bundletool 1.18.3 `validate` 通過；Manifest 確認非 debuggable、版本 1.0.0／1、minSdk 24、targetSdk 36。
- 所有 64 位元原生函式庫 PT_LOAD 對齊至少 16KB，BundleConfig 使用 `PAGE_ALIGNMENT_16K`。
- 帳號安全／使用規則 Flutter 測試 14 項通過；相關後端測試 81 項通過。
- 機器可讀結果：`build/app/outputs/bundle/release/verification.json`。
- 驗證重跑：設定 `JAVA_HOME` 與 `BUNDLETOOL_JAR` 後執行 `python3 tools/android/verify_play_bundle.py`。

## Android 套件名稱更新

Android Application ID、namespace 與 MainActivity 已改為 `com.hikakineame.coscircle`。Firebase 同一正式專案 `coscircle` 已登記新 Android App，取得真實 google-services.json 並同步 Dart options／FlutterFire metadata；已登記既有 upload key 的 SHA-1／SHA-256。既有 Firebase App 保留。

- Android 新舊套件在裝置上是不同 App，不會原地更新或自動搬移本機登入狀態；原帳號可重新登入。
- 前一份舊套件 AAB 保存在 `build/app/outputs/bundle/legacy-com.coscircle.coscircle/`，避免誤傳成新套件版本。
- LINE Developers Channel `2011925571` 的 Android package name 須同步為新值，並核對簽章設定。Google Play App signing certificate 仍須在取得後登記。
- 若 Play Console 已上傳舊套件版本，不能直接改成新 package name，需為新套件建立對應 App。

## 新套件 AAB 驗證結果

- package `com.hikakineame.coscircle`，版本 `1.0.0+1`，63532936 bytes。
- SHA-256 `f94c5a30e4a8656ecab575aaf4c448f45a106010dc15387deed017ba1ddbf2b3`。
- 正式 upload 簽章相符、bundletool validate、64 位元 ELF 16KB 對齊與 Flutter analyze 皆通過。

Maps key 只讀檢查：目前僅設 API service 限制，沒有 Android package allowlist，因此本次套件改名不需要修改該金鑰。曾嘗試準備條件式追加白名單的操作被自動審核拒絕，實際未執行；後續只讀確認無需變更。為查詢而啟用 Firebase 專案的 API Keys 管理 API，沒有新增金鑰或放寬限制。

## LINE 重接版本（2026-11-16）

AAB 已更新為 `1.0.0+2`，SHA-256 `0f7577a5fa79d564ab91cee2c6c2b6a1f4683a5b62bf0d4ed4d87b615ce12074`。原生 LINE 改從正式 API 取得 Channel ID，等待新的 Channel 設定與真實授權驗證，詳見 [LINE 部署紀錄](line-login-2026-11-16.md)。


## 最新內部測試 AAB（2026-11-18）

- 已重建並驗證 `1.0.0+3`，套件 `com.hikakineame.coscircle`，minSdk 24／targetSdk 36。
- 交付檔：`build/releases/android/coscircle-1.0.0+3.aab`；標準建置輸出亦已更新。
- 63,540,799 bytes，SHA-256 `60a20fb5b907b2eea0165ecf8f3e148a49f722b9177442dc71a3b8b9ef9b5f4f`。
- jarsigner 驗證與既有 upload certificate 相符；bundletool validate 通過；非 debuggable；所有 64 位元 ELF PT_LOAD 對齊至少 16KB。
- 驗證報告：`build/releases/android/coscircle-1.0.0+3-verification.json`。
- 可貼入 Console 的版本說明：`build/releases/android/coscircle-1.0.0+3-release-notes.txt`。
- 舊 +2 bundle 保留於 `build/app/outputs/bundle/previous-1.0.0+2/`。
- 使用現有正式金鑰及正式 HTTPS GCP 設定，未更動 API／DB 或 Play Console。
- 尚未上傳、發布或從 Play 安裝此 bundle；Play App signing certificate 與第三方服務配置仍待 Console 提供，不能把 upload 簽章驗證當作 Play 下載版本實測。

上傳步驟見 [Google Play 內部測試上傳](google-play-internal-testing.md)。若 versionCode 3 已在 Console 用過，必須遞增後重建，不能只更名檔案。
