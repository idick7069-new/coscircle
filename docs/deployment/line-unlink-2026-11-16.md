# LINE 解綁正式部署（2026-11-16）

Web 與 Android 共用「設定 → 登入方式 → 解綁 LINE」，需確認 Email 密碼。原帳號、session、個人資料、預定、好友／關注與小圈圈保留；沒有可用 Email／密碼時拒絕解綁。詳見 [LINE 登入文件](line-login.md)。

## 正式發布

- GCP project `cos-circle`／VM `coscircle-free-vm`／zone `us-west1-b`，帳號 `idick7069@gmail.com`。
- API release：`/opt/coscircle/api/releases/line-unlink-lIgtCUz3`；上一版 `line-link-jwd6kLbu` 保留。
- Root-only DB 備份：`/var/backups/coscircle/line-unlink-QuwwVUKL/coscircle.sql.gz`。
- Server SHA-256：`4a123c9a653aacf8c41ebaa21a3c59b11de69e0622440df9dbf5c1c759ec0779`。
- Auth identities module SHA-256：`2bb544bcf9152b09c970659368c0e120bf6b2f3af32a30c732d14bb29c4ef770`。
- Web release：`/var/www/coscircle/releases/user-web-QlxYPYOg`；上一版 `user-web-o6qq5z9b` 保留。
- Web main SHA-256：`205ccc25202f96db1a768efb77793d006311ac3c24ce4390c507a6c4e9919c38`。
- 部署腳本：`deploy/gcp/install-line-unlink-on-vm.sh`；最小差異：`deploy/gcp/line-unlink-production.patch`。不需 DB schema 遷移。

## 規則與驗證

`DELETE /api/me/auth-identities/line` 僅處理已登入的 req.userId，正式環境必須 HTTPS，沿用身份管理速率限制。交易鎖住使用者列，驗證有效帳號、可用 Email identity 與密碼後，移除該帳號 LINE identity，清除尚未完成的 Web 綁定。原始 provider 為 LINE 的舊帳號改以同一帳號 Email identity 回填 legacy 欄位，避免服務啟動又補回 LINE。錯誤會 rollback；重複解綁仍要求密碼驗證。

- 完整 Node 213 項測試通過，包含真實 SQLite 交易／rollback、僅 LINE 保護、錯密碼、legacy 回補與關係保留。
- Flutter 登入相關 39 項測試通過，包含共用解綁 UI 的取消／確認／錯密碼／唯一登入方式禁用，以及 DELETE 的 session 保留。
- Flutter analyze 無問題；Web release 建置成功。
- 正式專用 QA 建立三個暫時帳號（Email＋LINE、僅 LINE、legacy LINE＋Email），實際 API 驗證匿名／錯密碼拒絕、唯一登入方式保護、成功解綁與 Email 重登同一 user ID，確認 profile、session、booking、follow、circle_member 保留，並對 QA 使用者執行 scoped legacy backfill 確認不會復原 LINE。測試僅使用合成 LINE subject，不透過真人 LINE 授權。測試帳號及關聯資料全部清除。
- QA 腳本：`deploy/gcp/line-unlink-production-qa.mjs`；需明確 `--run-production-qa`，憑證只從 VM 受限環境讀取。

## Android

已建置並安裝正式簽章 `1.0.0+3` 至連線 Pixel 9a；套件 `com.hikakineame.coscircle`，APK：`build/app/outputs/flutter-apk/app-release.apk`。apksigner 驗證通過。

APK SHA-256：`71fbcd12e56b17f28dfb5bd8ba5c51d2956761a168cd410e11d16b578881c1d2`。

本輪未重建 Play AAB，既有 AAB 仍為 `1.0.0+2`。如要將解綁 UI 發到 Google Play，須使用目前原始碼重建新版本 bundle。未更動簽章金鑰、Firebase 設定或 LINE Channel。

建置期間僅清除專案內可重建的 Flutter／Android 中間快取，保留簽章金鑰與最終 APK／AAB。


公開 Web main 雜湊已經由外部 HTTPS 讀回確認，API health 正常。手機套件查詢確認 versionCode=3，Activity 啟動回報 Status=ok，程序存在且檢查範圍內未見 fatal／類別遺失錯誤；手機當時處於 Dozing／鎖定畫面，未將黑色截圖判為 App 問題，也未繞過解鎖。實機解綁按鈕尚未由本人帳號操作；共用畫面已有 widget 測試，完整解綁規則已由正式專用 QA 驗證。
