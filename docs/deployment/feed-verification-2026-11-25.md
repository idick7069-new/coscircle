# 動態牆完整驗證與正式部署（2026-11-25）

## 修正內容

- 動態刷新失敗後記住失敗的是刷新或分頁，重試不再因沒有下一頁而失效。
- 切換活動預定日期時清除前一天的文字、照片與可見範圍；過期回應不再覆寫目前日期。分享設定取得失敗時停用發佈並提供重試。
- 預定分享編輯讀取完整貼文，保留照片與留言開關。
- API 回傳當前檢視者的 `isMe`，作者管理操作不必等待另一個個人資料請求；留言亦使用伺服器提供的身分資訊。
- 互動列可換行，320px 寬及兩倍文字下不溢出。
- 空白留言停用送出；輸入後啟用。送出失敗保留文字、在輸入區顯示錯誤並允許重試，避免提示訊息遮住送出按鈕。
- 選取照片期間防止重複開啟選圖或發佈；離開該預定日期或變更登入身分後忽略舊選圖結果。

## 已完成驗證

- Flutter 完整測試：473 通過，1 既有略過。
- 後端：247 通過。
- 正式 HTTPS API：發文、編輯、刪除、按讚與取消、留言與回覆、留言開關、留言刪除權限、公開／戳友／指定小圈圈、移除好友／離圈／封鎖後撤銷存取、受保護圖片、預定更新／取消與 D1/D2 獨立、重新分享保留設定、檢舉與管理員權限、審查測試資料隔離，均通過。
- 測試建立活動日期使用台灣時區，與正式預定 API 的日期規則一致。

## 發布紀錄

- 正式 API：`/opt/coscircle/api/releases/social-feed-QdEXzgqM`。
- 正式 DB 與設定備份：`/var/backups/coscircle/social-feed-N85JjIbS`，僅 root 可讀。
- 正式 Web／管理頁：`/var/www/coscircle/releases/social-feed-ztnCYrsk`。
- 公開 `/app/main.dart.js` 與 `/admin/main.dart.js`：HTTP 200、與本次建置 SHA-256 一致，回應為 `Cache-Control: no-store`。正式 API health 正常。
- Android 畫面測試：Pixel 7a Android 15 模擬器完整流程通過，使用正式 HTTPS API 與隔離帳號，實際點擊同意、發文／編輯／刪除、按讚／取消、留言／回覆／刪除、關閉／開啟留言、戳友／指定小圈圈可見設定，並確認預定更新及取消的畫面。
- 原生測試為 debug 建置；一般正式簽章 APK 另外重建。實體 Pixel 9a 因鎖定未進行完整畫面測試。
- Flutter 靜態分析：無問題。
- 一般正式簽章 APK：`build/releases/CosCircle-1.0.1-9.apk`，已以更新安裝方式換回 Pixel 9a，裝置回報 versionCode 9、versionName 1.0.1，無 DEBUGGABLE 旗標；保留原 App 資料。

## 測試資料與帳號

本輪專用帳號使用獨立憑證；測試作者、戳友、非好友及活動／小圈圈均隔離，一般帳號不能看到。原 Google Play 審查帳號及其資料保留。Android 測試只在記憶體注入專用 session，不寫入裝置使用者的登入儲存。

重跑 Android 畫面測試使用 `integration_test/feed_live_test.dart` 與正式 HTTPS API，需先透過受限的 GCP QA 工具產生專用憑證。`coscircleQaSigning=true` 僅供本機測試建置沿用既有簽章，避免移除已安裝 App 與清除資料。測試結束須換回一般 release APK、刪除專用測試帳號與暫存憑證。不得將測試建置上傳商店。

通知為 App 內互動通知。本輪不將其視為背景推播；手機原生相簿選圖器、iOS 實機與商店上傳並非這輪驗證範圍。

## 清理結果

正式 DB 已確認本輪臨時帳號、活動、小圈圈均為 0 筆，原兩個審查帳號仍保留；本輪貼文、留言與合成照片已隨專用資料清理。已刪除本機測試 session 檔案並關閉臨時模擬器。正式 HTTPS 驗證紀錄及清理狀態在受限備份 `/var/backups/coscircle/social-feed-Clw2JYW8`。
