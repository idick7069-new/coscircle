# 動態牆（首版）

版本：1.0.1（10），2026-11-25。

## 操作與功能

底部導覽為「動態、活動、現場、同好、我的」。預設開啟動態；「我的」保留原個人名片、編輯、準備度與場次安全，右上角齒輪進入設定。活動詳情右上角的動態圖示可進入本場動態。

### 發佈內容

- 「分享預定」選擇自己的活動及 D1／D2 等獨立日期，補上文字即可分享；沒有預定時引導至活動頁。也可於原預定編輯表單勾選「同步分享到動態牆」。既有預定不會被自動發文。
- 預定卡直接讀取原預定的作品、角色、身份及照片，修改即同步；取消後保留原貼文及討論並標示「已取消預定」。重新參加同日會恢復卡片，不重複建立貼文。
- 一般貼文可含文字、最多四張本人上傳的照片，並選填作品及活動；文字上限 2,000 字。
- 發文／編輯頁底部固定發佈或儲存按鈕。上傳失敗保留草稿及已成功上傳的照片，返回會確認放棄。
- 可見範圍為公開、戳友限定、指定小圈圈。圈圈需為作者現有成員。原預定限定小圈圈時，不可分享成公開或戳友限定。

### 瀏覽與互動

- 依最新貼文排序，游標分頁，每頁 20 篇。
- 內容篩選：全部、預定、一般貼文。同好篩選：看看大家、關注與戳友、與我同坑、小圈圈。
- 對應自己坑單的作品標籤亮色顯示，附「跟你同坑」提醒。
- 點作者或留言者頭像／名稱開啟既有名片，沿用關注、戳友及封鎖功能。
- 單一按讚，可取消；重送同一按讚不增加計數。
- 貼文作者的留言與回覆在名稱旁顯示圖示及「原 PO」，所有可見該貼文的使用者均可辨認。
- 留言上限 1,000 字，支援回覆、較早留言分頁；使用者可刪除自己留言，作者可移除自己貼文下的留言，並隨時關閉／開啟留言。
- 互動通知以站內通知提供，同篇同類互動合併、可標記已讀。動態頁開啟時每 45 秒更新，進頁及手動刷新亦更新。首版未額外串接背景互動推播。

### 安全與檢舉

- 列表、單篇、留言、按讚、通知與圖片皆重新核對可見權限，包含雙向封鎖、停權、審查資料隔離、現有戳友關係及圈圈成員資格。
- 已離圈者失去圈圈限定內容及照片連結的存取權。取消戳友後無法續看戳友限定內容。
- 上傳圖片維持既有短時效簽章／no-store 機制；不能引用別人的上傳圖片冒充自己的附件。
- 社群發文、編輯、留言及按讚需已確認使用規則；檢舉、刪除及讀取通知不以此阻擋。
- 貼文／留言均可檢舉，原因含騷擾、色情與兒少安全、隱私、垃圾訊息、仇恨、冒用及其他。待處理的同一內容檢舉會去重。
- 後台右上角「動態檢舉」入口提供證據、移除內容並結案、不處分並結案。處分前核對內容是否已改變；過期證據不允許直接移除內容。
- 證據最長 90 天，由既有背景維護清除；刪除帳號時清除相關證據個資及社群資料。原有其他類型檢舉仍走原審核頁。

## API

所有動態 API 均需登入，正式服務使用 HTTPS。

| 方法與路徑 | 用途 |
|---|---|
| GET `/api/feed` | 列表，query：kind、scope、eventId、before |
| GET `/api/feed/booking-share` | 目前帳號指定 eventId／dayIndex 的分享設定 |
| GET `/api/feed/notifications`、POST `/api/feed/notifications/:id/read` | 通知列表／指定項目標已讀 |
| GET／PUT／DELETE `/api/feed/:id` | 單篇、作者編輯、作者刪除 |
| POST `/api/feed` | 發文，kind 為 booking 或 general |
| GET／POST `/api/feed/:id/comments` | 留言分頁、發佈留言／回覆 |
| DELETE `/api/feed/:id/comments/:commentId` | 刪除留言 |
| PUT／DELETE `/api/feed/:id/like` | 按讚／取消 |
| POST `/api/feed/:id/reports` | 檢舉貼文或 commentId 指定的留言 |
| GET `/api/admin/feed-reports` | 管理員檢舉列表 |
| POST `/api/admin/feed-reports/:id/review` | 管理處理，action：remove／dismiss |

預定 API 的可選分享欄位：`shareToFeed`、`feedVisibility`、`feedCircleId`、`feedBody`。原預定與分享設定在同一交易寫入；未傳欄位不改變既有分享設定，明確 false 則停止分享。關閉留言的狀態不會因預定編輯被重設。

## 資料與程式入口

- 後端主模組：`backend/src/social-feed.js`，路由由 server.js 註冊。
- 資料表：social_posts、social_post_media、social_comments、social_likes、social_notifications、social_reports。遷移：`backend/db/migrate_social_feed.sql`。
- 前端 model／repository：`lib/core/models/feed_post.dart`、`lib/core/repositories/feed_repository.dart`。
- UI：`lib/features/feed/presentation/`。
- 導覽：`lib/features/home/presentation/home_shell_page.dart`、`lib/core/router/app_router.dart`。
- 檔案存取：`backend/src/private-media.js` 串接共用動態權限判斷。

## 作品初始資料

採人工整理的 109 個常見 Cosplay 作品候選，不是人氣排行榜；僅名稱及別名，不含第三方圖片、劇情介紹或角色資料。參考公開名稱來源包含 [HoYoverse](https://www.hoyoverse.com/zh-tw/about-us) 與[授權動畫頁](https://www.crunchyroll.com/zh-tw/series/GG5H5XQX4/frieren-beyond-journeys-end)。巴哈 ACG 資料庫本次讀取為 403，因此採整理清單匯入，未建立資料庫爬蟲。

- 原始清單：`backend/data/cosplay-works.json`。
- 正規化／去重：`backend/src/work-catalog.js`，處理全半形、標點、空白與英文字母大小寫。
- 匯入工具：`deploy/gcp/seed-work-catalog.mjs`，先 preview，再在受限完整備份存在時 apply。
- 別名表：`work_aliases`，遷移 `backend/db/migrate_work_aliases.sql`。
- 正式結果：新增 104 筆、沿用 5 筆，總計 110 筆非測試作品及 263 個名稱／別名鍵。重新預覽為新增 0、沿用 109，無別名衝突。
- 既有 ID 1「我英」與 ID 6「我的英雄學院」保留，未擅自合併使用者坑單；正式名稱命中時沿用 ID 6，重複群組記錄在匯入報告。

## 驗證

- 後端 247 項測試通過，包含動態權限、圈圈／戳友、封鎖、停權、審查隔離、預定同步與獨立日期、取消後討論保留、按讚冪等、精確回覆通知、檢舉處理及作品去重。
- Flutter 最終完整回歸 474 項通過、1 項既有測試略過；鍵盤開啟時的發文操作另於 1／2 倍字體補測通過。新動態與發文介面檢查 320／390px、1／2 倍文字縮放、鍵盤開啟仍可直接發佈；靜態分析通過。
- GCP 以內部候選及正式 API 分別驗證完整 HTTP 流程，所有 QA 內容使用隔離帳號，一般使用者看不到；完成後清理本輪帳號、貼文、圈圈、活動及合成照片。
- 未宣稱背景推播、實體 iOS 操作或所有裝置的手動 UI 驗證通過。

## 首版發布紀錄（2026-11-24）

- API：`/opt/coscircle/api/releases/social-feed-SxVIVqmK`。
- Web／管理頁：`/var/www/coscircle/releases/social-feed-A4DSuvO0`。
- 完整 DB 受限備份：首次匯入 `/var/backups/coscircle/social-feed-mjw5Uzne`；最終通知修正 `/var/backups/coscircle/social-feed-0vzC5e13`。
- 作品匯入報告、候選／正式 QA 與清理紀錄均留在對應備份目錄，不含於 Git。
- 使用者入口：https://coscircle.app/app/；管理入口：https://coscircle.app/admin/。
- Android 正式簽章 APK：`build/releases/CosCircle-1.0.1-7.apk`，已更新到 Pixel 9a 並確認啟動，保留原有 App 資料。這是啟動驗證，不等同所有頁面的實機人工操作。
- 這次未操作 Google Play 或 TestFlight 發布；先前商店登入／上傳交接仍另行待處理，勿將 Web 發布視為商店已更新。

## 2026-11-25 操作與權限修正

本輪操作修正、正式 HTTPS 權限驗證及發布紀錄見 [完整驗證紀錄](../deployment/feed-verification-2026-11-25.md)。分享預定切換日期會清除前一天的草稿與可見設定；載入分享設定失敗時，需重試成功才能發佈。留言空白時停用送出，失敗保留草稿並可重試。
