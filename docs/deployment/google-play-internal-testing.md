# CosCircle：Google Play 內部測試上傳

本指引依 2026-11-18 的專案與 Google／LINE 官方文件整理。建置與簽章可在本機驗證；本文沒有代替使用者登入 Play Console，也不代表版本已上傳或測試軌道已發布。

## 要上傳的檔案

已完成本輪重建與驗證，使用 `build/releases/android/coscircle-1.0.0+3.aab`（63,540,799 bytes）。正式簽章與 upload certificate 相符、bundletool validate 及 64 位元 ELF 16KB 對齊驗證通過。尚未上傳至 Play Console。

SHA-256：`60a20fb5b907b2eea0165ecf8f3e148a49f722b9177442dc71a3b8b9ef9b5f4f`。

- 套件：`com.hikakineame.coscircle`
- versionName：`1.0.0`；versionCode：`3`
- 正式 API：`https://coscircle.app/api`
- LINE Channel 從正式 API 動態讀取；包含最新綁定／解綁、帳號安全入口。
- 重建命令：`JAVA_HOME=/Users/frank/Library/Java/JavaVirtualMachines/jbr-21.0.11/Contents/Home python3 tools/android/build_play_bundle.py`
- 若 Play 已用過 versionCode 3，須先遞增 `pubspec.yaml` 的 build number 並重新建置；單純改檔名不能重用版本號。

## 1. 選擇正確 App

登入 [Google Play Console](https://play.google.com/console/)。如果尚未建立 App，先建立 CosCircle，預設語言選繁體中文，類型選應用程式，價格依產品實際規劃填寫，確認畫面上的開發者與 Play App Signing 聲明。帳號身分驗證或其他必填工作依 Console 顯示完成。

若已建立 App，確認是要使用 `com.hikakineame.coscircle` 的項目。第一次上傳 bundle 後套件名稱會固定；如果舊項目已綁 `com.coscircle.coscircle`，不能直接更名套件，需用新套件對應的 App。

內部測試可以在部分 App 設定尚未完成時開始，但仍以 Console 當次顯示的必要條件為準；第一次審查前可能顯示暫時名稱。[官方測試說明](https://support.google.com/googleplay/android-developer/answer/9845334?rd=1)

## 2. 新增測試者

進入「測試與發布（Test and release）→ 測試（Testing）→ 內部測試（Internal testing）」。不要選「內部應用程式分享（Internal app sharing）」，這是不同流程。

在「測試人員／Testers」分頁建立或選擇 Email 名單，加入自己與測試者實際用在 Play 商店的 Google 帳號，儲存並勾選該名單。回饋網址可使用專案已有的 [Google 表單](https://forms.gle/WGFe57Y1AFW1LQda8)。[官方測試說明](https://support.google.com/googleplay/android-developer/answer/9845334?rd=1)

## 3. 建立及上傳版本

回到內部測試「版本／Releases」分頁，點「建立新版本／Create new release」。第一次依 Console 指示啟用 Play App Signing，使用 Google 管理的 App signing key；本 AAB 已由既有 upload key 簽好，不需另建或換掉本機簽章金鑰。

在 App bundles 區塊上傳 `coscircle-1.0.0+3.aab`。Mac 檔案選擇視窗可按 Command＋Shift＋G，輸入：

```text
/Users/frank/FlutterProjects/coscircle/build/releases/android/
```

再選 `coscircle-1.0.0+3.aab`。等待處理完成，核對套件名稱與 versionCode 3，勿選 APK 或舊版 +2 bundle。

版本名稱可填 `1.0.0 (3) - 內部測試`。以下版本說明可貼到繁體中文欄位；若 Console 提供帶語言標籤的編輯器，可使用：

```text
<zh-TW>
CosCircle 內部測試版。
包含活動瀏覽與預定、名片與 QRCode、同坑雷達、小圈圈及現場互動。
支援 Email／LINE 登入、綁定與解綁，以及檢舉、封鎖和刪除帳號。
本版請協助回報操作、顯示或登入問題。
</zh-TW>
```

依序儲存、下一步並檢查錯誤；確認是內部測試軌道後發布。介面可能顯示「儲存並發布」「開始推出至內部測試」或送審／發布提示，以當次 Console 為準。先修正阻擋發布的錯誤，不要只停在草稿便分享連結。[官方發布流程](https://support.google.com/googleplay/android-developer/answer/9859348?hl=en)

## 4. 核對 Play 的 App signing 憑證

在 App signing 頁面查看 **App signing key certificate**，不是 Upload key certificate。依 Console 版本，可在「App integrity／應用程式完整性」或「Protected with Play → Play Store protection → Manage Play app signing」找到。

下載公開憑證並記錄 SHA-1／SHA-256；這些是公開資訊，可提供給開發者。不要提供私鑰、keystore 密碼或 API secret。Google 使用 App signing key 簽署實際發送的 APK，所以 API 供應商可能需要這組指紋，而非本機 upload key。若 Console 顯示多組實際發送的簽章金鑰，依各服務支援及 Console 說明逐一核對。[Play App Signing 官方說明](https://support.google.com/googleplay/android-developer/answer/9842756?hl=en)

本專案需確認：

- Firebase 專案 `coscircle` 的 Android App `com.hikakineame.coscircle` 登記 Play 簽章 SHA-1／SHA-256。
- LINE Channel `2012627208` 的 Android 套件與 Package signatures；若使用簽章限制，加入實際 Play 憑證對應的 SHA-1 Base64，不能直接把冒號格式 SHA-1 或 SHA-256 填入該欄。
- Maps key 若有 Android package／certificate 限制，加入此套件及實際 Play 簽章；本專案先前只讀確認沒有 Android allowlist，仍需以目前設定為準，不要為此放寬權限。

LINE Channel 若仍是 Developing，只有 Channel Admin／Tester 能測試；加入 Google Play 名單不會自動取得 LINE 測試資格。讓其他人測試時，可先在 LINE Console 配置 Tester。發布 LINE Channel 是另外的決定，且不能改回 Developing；本次不代為變更。[LINE 官方說明](https://developers.line.biz/en/docs/line-login/getting-started/)

## 5. 分享加入連結及安裝

回到內部測試 Testers 分頁，複製 Console 提供的「加入測試」連結。測試者以名單中的同一 Google 帳號開啟並加入，再從該頁前往 Google Play 安裝。內部測試尚未公開的 App 不能靠商店搜尋找到；第一次發布或連結生效可能需要等候。[官方測試說明](https://support.google.com/googleplay/android-developer/answer/9845334?rd=1)

若本機側載版本與 Play 版本簽章不同，可能無法直接覆蓋。先確認帳號可重新登入及重要資料已同步，再決定是否移除側載版；不要直接刪除 App 資料來排錯。

安裝 Play 發送版本後，優先驗證 Email／LINE 登入、LINE 綁定／解綁、地圖與位置分享、通知、圖片上傳、檢舉／封鎖及刪除專用測試帳號。AAB 結構或簽章驗證通過，不等於上述 Play 實機流程已測完。

官網的 Android 測試教學目前仍待真實加入網址；取得 Console 的連結及測試加入方式後再更新 `web/official/android-testing.json`，不要猜測加入網址。

## Console 要求填寫時可參考

- 官網：https://coscircle.app/
- 隱私政策：https://coscircle.app/privacy.html
- 服務條款：https://coscircle.app/terms.html
- 刪除帳號說明：https://coscircle.app/delete-account.html
- 意見回饋：https://forms.gle/WGFe57Y1AFW1LQda8

內容分級、目標年齡、資料安全、廣告聲明與審查人員登入資訊須依實際功能及 Console 要求填寫，不能因屬測試版而填不實資料。

公開隱私、條款與刪除帳號頁已於 2026-11-19 修復並以真實瀏覽器及一次性刪除流程驗證，詳見 [公開法律頁修復紀錄](public-legal-pages-2026-11-19.md)。
