# CosCircle Alpha 使用者與 QA 檢視

日期：2026-10-02（Asia/Taipei）
基準 commit：`1a81bca`

## 結論

建議先修正資料覆蓋、圈圈誤刪、活動重複與錯誤狀態，再擴大 Alpha。現有功能已能組成完整產品流程，但日期切換、網路失敗、平台差異與切換分頁仍有明顯缺口。靜態分析通過或既有測試通過，並不足以代表這些流程正常。

這輪整理 22 個問題：8 個 P1、14 個 P2。P1 是可能造成資料損失、隱私風險或主要功能無法使用；P2 是應在擴大 Alpha 前處理的操作、狀態與排版問題。

## 檢視範圍與證據限制

- 閱讀登入、OOBE、名片、公開名片、活動列表、活動詳情、我的活動、分享圖、現場、社交、設定，以及對應 API、schema 與平台設定。
- 正式 GCP Web：實際查看登入頁，使用 320 × 640 視窗確認 LINE 登入要求貼 access token。沒有登入私人帳號，也沒有新增、修改或刪除正式資料。
- 既有 Flutter 測試：7 項全部通過。
- 暫時 QA 探針：4 項確認目前異常行為，包括離線清除 token、名片離線顯示空白可編輯資料、我的活動離線停在載入畫面、切換預定日期仍保留原日角色。
- 排版探針：6 頁 × 2 種寬度（320／390）× 2 種字體倍率（1.0／1.5），共 24 組。20 組通過，4 組重現 RenderFlex overflow；名片另測編輯模式，各頁可捲動區域最多捲動 5 次。
- 探針使用隔離的記憶體資料與故障注入，未啟動測試後端、未切換 API／DB 環境。探針完成後移除，沒有修改產品功能。
- 排版通過僅代表樣本內容與所測區域未報溢出。社交使用空名單、OOBE 主要測首步，不能推廣到所有真實資料、所有步驟或所有對話框。
- 未完成 Android／iOS 真機相機、定位、通知、鍵盤、背景與恢復流程的端到端測試。下列有程式證據但未實機重現者，會註明。

## P1 問題

### A01：切換預定日期可能覆蓋另一日資料

證據：QA 探針重現表單資料不切換；覆蓋結果由 API upsert 確認，未對正式資料操作。

重現：D1 與 D2 各有不同角色，開啟 D1 修改，點 D2 後儲存。日期只更新 `_dayIndex`，作品、角色、照片與留言仍是 D1 的值，後端會覆蓋 D2 的既有預定。原 D1 也仍保留，容易被誤認為已「移動日期」。切換後點取消預訂，則會刪除新選的日期。

建議與驗收：編輯既有預定時鎖定日期，或切日後載入該日資料並處理未儲存變更。D1 修改不得改到 D2；新增、修改、移動日期必須有明確且不同的行為。

位置：[event_list_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/event_list_page.dart:1254)、[server.js](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:1662)。

### A02：擁有者的「離開小圈圈」實際刪除整個圈圈

證據：前後端與外鍵確認，未執行正式刪除。

重現：建立者選「離開」，確認視窗只說自己離開、不再收集合訊號。API 卻直接刪除 `circles`，連帶刪除成員關係及集合點。其他成員也失去圈圈。

建議與驗收：擁有者提供「轉移管理權」或明確的「解散小圈圈」，確認視窗列出對全體成員與集合點的影響。一般離開不能悄悄變成解散。

位置：[social_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/social/presentation/social_page.dart:323)、[server.js](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:1406)、[schema.sql](/Users/frank/FlutterProjects/coscircle/backend/db/schema.sql:126)。

### A03：多位同好參加同一活動會讓 API 回傳重複活動

證據：SQL 確認，未用正式帳號建立多人重現資料。

重現條件：同一活動有兩位以上已關注的參加者，或兩位以上圈圈成員參加。子查詢保留每位使用者，最後又按 `followed_bookings.user_id` 和 `circle_bookings.user_id` 分組。一個活動會得到多列，兩種關係同時存在時還會形成組合。

影響：活動卡片、逐日展開、月曆數量及我的活動讀取都可能重複；與來源爬蟲是否去重無關。

建議與驗收：用 EXISTS 或按 event_id 聚合成單一關係旗標。每個 event id 永遠只回一筆，不受同好人數影響。

位置：[server.js](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:668)、[event_day_item.dart](/Users/frank/FlutterProjects/coscircle/lib/core/models/event_day_item.dart:28)。

### A04：名片載入失敗後，儲存可能清掉原個人資料

證據：QA 探針確認失敗後仍顯示可編輯的空白名片；資料清除風險由 PUT 全量更新確認。

重現：開啟名片時網路短暫失敗，畫面用空白 `UserProfile` 取代錯誤，仍允許編輯。網路恢復後輸入暱稱並儲存，空白照片、身份、坑單、地區等會送回後端覆蓋原值，出席可見性也可能回到公開。

建議與驗收：載入失敗要顯示錯誤與重試；取得有效資料前禁止儲存。必要時保留上一份成功資料。網路失敗不能轉成空白表單。

位置：[profile_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/profile/presentation/profile_page.dart:97)、[server.js](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:457)。

### A05：Web 版開啟原活動頁缺少支援

證據：程式與本機安裝的插件配置確認，未登入正式帳號點擊重現。

所有平台都建立 `WebViewController`／`WebViewWidget`，但目前只有 Android／WKWebView 實作，沒有 Web 平台實作。Web 使用者點「開啟原活動頁」會進入無法正常建立的頁面，而非開啟官方網站。

建議與驗收：Web 用瀏覽器分頁開啟官方 URL，原生平台保留 WebView；處理開啟失敗。三種平台皆能看來源。

位置：[event_detail_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/event_detail_page.dart:492)、[pubspec.lock](/Users/frank/FlutterProjects/coscircle/pubspec.lock:1268)。

### A06：Web 版產圖分享使用本機檔案流程

證據：程式與插件配置確認，尚未在已登入的正式 Web 點擊匯出。

預覽雖可顯示，分享時卻呼叫 `getTemporaryDirectory()`、建立 `dart:io File` 再分享。專案沒有 Web temporary-directory 實作，瀏覽器也不能走這個本機檔案流程。此方法沒有 catch 顯示友善錯誤，使用者可能只看到按鈕恢復但沒有結果。

建議與驗收：Web 以記憶體 bytes 提供下載／可用的瀏覽器分享，原生平台用暫存檔。Web、Android、iOS 都必須驗證實際輸出圖片，而非只驗證預覽。

位置：[event_booking_share_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/event_booking_share_page.dart:477)。

### A07：目前正式入口與預設 API 使用 HTTP

證據：正式網站實際瀏覽、API 預設與部署設定確認。

Alpha 使用者的登入密碼、session token、個人資料與位置會經過未加密 HTTP。Web 相機、定位等需要安全來源的瀏覽器能力也可能受限，須用正式 HTTPS 入口實測；這部分尚未逐項重現。

建議與驗收：正式 Web、API、uploads 統一 HTTPS，確認 App release 的 API 設定與圖片 URL 也一致。連線中不再使用明文帳密與定位資料。

位置：[api_client.dart](/Users/frank/FlutterProjects/coscircle/lib/core/api/api_client.dart:92)、[nginx-coscircle.conf](/Users/frank/FlutterProjects/coscircle/deploy/gcp/nginx-coscircle.conf:2)。

### A08：登出後裝置推播 token 仍綁定舊帳號

證據：程式確認；登出後實際通知送達情形待真機驗證。

登出只取消本地訂閱、清 session token，沒有呼叫刪除 push token 的 endpoint；後端通知仍按 `device_push_tokens.user_id` 發送。只登出而未換帳號時，裝置仍可能收到原帳號的認親通知。

建議與驗收：登出前解除此裝置 token 綁定，並定義斷線登出的處理；登出帳號 A 後裝置不得再收到 A 的私人通知。

位置：[settings_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/settings/presentation/settings_page.dart:143)、[push_notification_service.dart](/Users/frank/FlutterProjects/coscircle/lib/core/services/push_notification_service.dart:60)、[server.js](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:2909)。

## P2 問題

### A09：短暫離線會清除登入狀態

QA 探針已確認：`restoreToken()` 對所有錯誤都移除 token，逾時、斷線與 500 也被當成登入失效。在活動現場網路差時重開 App，會被迫重新登入。

驗收：只有明確無效的認證才清 session；暫時連線失敗保留 token，顯示重試或離線狀態。

位置：[auth_repository.dart](/Users/frank/FlutterProjects/coscircle/lib/core/repositories/auth_repository.dart:57)。

### A10：「我的活動」載入失敗後永遠停在載入畫面

QA 探針已確認：FutureBuilder 沒有 `hasError` 分支，失敗也落入 `!hasData`。此時看不到重試入口。另 `_loadMyBookings()` 依序抓每個已加入活動的參加者，任何一筆失敗就使整頁失敗。

驗收：區分載入、空清單、錯誤；提供重試，允許部分成功結果。較多預定時改用自己的預定 API 或可控的批次讀取。

位置：[my_events_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/my_events_page.dart:40)、[my_events_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/my_events_page.dart:119)。

### A11：已結束活動仍有修改／刪除入口，逐日過期規則不一致

程式確認：「我的活動」顯示歷史項目時仍提供修改和取消。完全結束的活動修改會被後端拒絕；刪除卻沒有過期檢查。在 D2 當天，從表單選 D1 儲存又會通過，因為 API 只看整個活動的 end_date。

驗收：UI 與 API 都按預定當日判斷。舊活動仍可查看與產圖，但過期日不能新增、修改或刪除，符合已確認的產品規則。

位置：[my_events_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/my_events_page.dart:100)、[server.js](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:1641)、[server.js](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:1694)。

### A12：切換底部頁籤會丟失未儲存輸入與捲動狀態

程式確認：HomeShell 只掛載 `pages[_index]`，切換時原頁被 dispose。編輯名片尚未儲存，點活動再回來，原輸入消失且沒有提醒；現場地圖與社交頁也會重建。

驗收：保留分頁狀態，或離開未儲存表單前確認。保留頁面時需另管理定位與輪詢的啟停，避免背景持續耗電。

位置：[home_shell_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/home/presentation/home_shell_page.dart:100)。

### A13：刪除照片時 URL 清單與新選照片索引失去對應

程式確認，未實際上傳照片：選了第二張新照片，再刪第一張時，`_otherPhotoUrls` 被壓縮，`_pickedOtherPhotos` 沒有一起位移。儲存仍按舊 index 上傳，可能把同一張存兩次，或把尚未上傳的本機／blob 路徑當成永久照片 URL。

驗收：照片以同一個資料結構保存 URL 與選取檔案；刪除或移動時一起變動。測試「新增兩張→刪第一張→儲存→重開」。

位置：[profile_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/profile/presentation/profile_page.dart:324)、[profile_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/profile/presentation/profile_page.dart:242)。

### A14：分享 QR 只能依賴 App 內建掃描，外部開啟流程未完成

程式確認：名片 QR 使用 `coscircle://profiles/...`，Android manifest 沒有相應 intent-filter，iOS 沒有 URL Types；圈圈邀請 URL 則是 `https://coscircle.local/join/...`，專案路由也沒有 `/join`。內建掃描器能解析碼，不能代表手機原生相機或訊息中的連結能開啟。

驗收：使用可開啟的正式 HTTPS 連結；有 App 則導向對應頁，無 App 則顯示可用的 Web 名片／加入流程。登入後仍保留原目標。

位置：[profile_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/profile/presentation/profile_page.dart:392)、[server.js](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:1324)、[app_router.dart](/Users/frank/FlutterProjects/coscircle/lib/core/router/app_router.dart:13)。

### A15：「關注者／小圈圈」篩選仍把不同日混在一起

程式確認：自己的 joinedDayIndexes 已逐日，但 `hasFollowedParticipants` 和 `hasCircleMembers` 仍是活動層級。朋友只參加 D2，D1／D3 也會符合關注者篩選及徽章，使用者以為朋友會在當日出現。

驗收：同好訊號也提供逐日索引並以 EventDayItem 判斷。只有統計與分享圖合併，不合併日別出席訊號。

位置：[event_list_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/event_list_page.dart:351)、[server.js](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:616)。

### A16：點 D2／D3 認親推播會導向預設 D1

程式確認，待真機驗證：推播資料沒有 dayIndex；路由 `/current/:id` 建立 CurrentEventPage 時也不傳日期，預設值是 1。D2 通知可能打開 D1 現場，而登入流程最後的首頁導向還可能覆蓋冷啟動通知目標。

驗收：推播包含 eventId、dayIndex、requestId，冷啟動、背景及前景都導向正確日期與通知；先恢復登入再導向。

位置：[push_notification_service.dart](/Users/frank/FlutterProjects/coscircle/lib/core/services/push_notification_service.dart:99)、[app_router.dart](/Users/frank/FlutterProjects/coscircle/lib/core/router/app_router.dart:31)、[push-service.js](/Users/frank/FlutterProjects/coscircle/backend/src/push-service.js:45)。

### A17：未完成 OOBE 的舊帳號再次登入會跳過設定

程式確認：非新註冊 session 在登入後直接 `markCompleted`。新使用者註冊後中途退出，下次以登入流程進來便會被標成完成，可能漏掉身份與基本資料。OOBE 完成狀態也僅存在本機。

驗收：完成狀態以帳號資料為準，不因「這次不是註冊」就標完成；跨裝置、中途退出及重新登入都驗證。

位置：[login_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/auth/presentation/login_page.dart:179)、[oobe_service.dart](/Users/frank/FlutterProjects/coscircle/lib/core/services/oobe_service.dart:7)。

### A18：窄螢幕與大字體可重現跑版

QA 排版測試已確認：

| 畫面 | 寬度 | 字體倍率 | 結果 |
| --- | --- | --- | --- |
| 活動列表卡片 | 320 | 1.0 | 右側溢出 4 px |
| 活動列表卡片 | 320 | 1.5 | 右側溢出 28 px |
| 名片身份 badge | 320 | 1.5 | 右側溢出約 7.4 px |
| 分享圖 section header | 320 | 1.5 | 右側溢出 25 px |

測試樣本在 390 寬度的 1.0／1.5 倍字體下未報溢出。這不涵蓋更長身份、完整成員名單、橫向或所有對話框。

驗收：活動操作按鈕能改行，badge 可約束與換行，section header 的 trailing 不擠出容器。至少測 320／360／390／430、文字倍率 1／1.5／2、亮暗主題與長文案。

位置：[event_card.dart](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/widgets/event_card.dart:122)、[profile_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/profile/presentation/profile_page.dart:995)、[cos_ui.dart](/Users/frank/FlutterProjects/coscircle/lib/shared/widgets/cos_ui.dart:642)。

### A19：多個操作失敗沒有畫面回饋，認證失效也沒有統一處理

程式確認：離開圈圈、移除成員、取消關注、取消預定等直接 await API，沒有錯誤處理與操作中狀態。登出失敗時本機 token 雖被 finally 清掉，exception 卻阻止頁面跳回登入，留下看似登入中的頁面。一般 API 401 也沒有統一導向重登。

驗收：關鍵操作都有 loading、防重複點擊、友善錯誤與重試；登出最終一定回登入。401 保留原導向目標並統一處理，不停留在無法操作的頁面。

位置：[social_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/social/presentation/social_page.dart:343)、[my_events_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/my_events_page.dart:164)、[settings_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/settings/presentation/settings_page.dart:144)、[api_client.dart](/Users/frank/FlutterProjects/coscircle/lib/core/api/api_client.dart:44)。

### A20：活動照片上傳驗證與個人照片不一致

程式確認，待 Web／iOS 實際選圖驗證：名片使用 XFile.mimeType 與 5 MB 檢查，活動預定卻依 path 副檔名推 MIME，未知一律 JPEG，且無大小檢查。Web blob 路徑通常不保留副檔名，PNG／WebP 可能被標成 JPEG，被後端位元檢查拒絕；超大照片則等上傳後才失敗。

驗收：共用選圖驗證；優先使用可靠 MIME、必要時檢查 bytes，壓縮或限制尺寸。PNG、WebP、JPEG、超過 5 MB 與不支援格式都要有清楚回饋。

位置：[event_list_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/event_list_page.dart:1406)、[event_list_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/event_list_page.dart:1444)、[server.js](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:535)。

### A21：只加入 D2，也可能在 D1 被自動選成「現場活動」

程式確認：預設現場選擇依 `event.isJoined` 與整個活動 active 判斷，不要求今天的 dayIndex 在 joinedDayIndexes。只參加 D2 的人，在 D1 仍可能進入該活動現場，點位置分享再收到「先加入這一天」的拒絕。

驗收：預設選擇使用今天已加入的 EventDayItem；若今天沒有出席，清楚顯示尚無今日場次。顯式指定的現場日期也需驗證有效。

位置：[current_event_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/current_event/presentation/current_event_page.dart:327)。

### A22：社群登入入口對一般使用者不可用

正式 Web 已實際確認：點 LINE 要使用者貼 access token；Facebook 走同一種流程。這不是一般使用者能完成的登入操作，還有工程用 placeholder 文案。Email 密碼登入也沒有找回密碼入口。

驗收：社群入口串正常授權流程，或在 Alpha 隱藏未完成入口；規劃忘記密碼／復原方式。不能要求使用者自行取得 token 才能登入。

位置：[login_page.dart](/Users/frank/FlutterProjects/coscircle/lib/features/auth/presentation/login_page.dart:125)。

## 使用體驗改善

以下是改善建議，與上面已確認問題分開評估：

- 出席表單優先顯示選定的實際日期與 Dn；身份預設可參考個人身份，不必每次從 coser 開始。單純宣告「我會去」與完整出角資訊可採漸進填寫，減少首次操作負擔。
- 活動詳情目前沒有直接加入／修改入口，要返回列表；尚未加入者看不到參加者時，空狀態卻說「還沒有人公開預訂」，應清楚區分「未加入而無權查看」與「真的沒人參加」。
- 月曆恢復上次選日很方便，但隔很久重開仍鎖在舊日期會讓人誤以為沒活動。應清楚顯示目前篩選，提供「今天」與一鍵重設；不強制隱藏歷史活動。
- 設定頁／名片／活動頁常出現重複標題、說明與統計面板。手機首屏應優先放使用者要做的事，減少到名片、活動列表或儲存按鈕之前的捲動距離。
- 原始 `$error` 與未映射的 API code 不宜直接露出；特別是 `event_ended`，應顯示「此日期已結束，無法修改」，並保留輸入供使用者調整。
- 現場頁一進入就定位，登入流程又等待推播初始化；權限請求時機與通知服務失敗會影響第一印象。建議讓相關權限在使用者執行相應動作時有明確理由，通知初始化失敗也不阻擋登入。
- 目前位置分享是一次定位快照，30 秒輪詢只抓其他資料，沒有持續更新自己的位置。需明確標示分享時間與最後更新，並決定是否提供「更新位置」或受控的移動追蹤。
- 表單尚未儲存便關閉、返回或切頁時應提醒；長表單可保留草稿。圖片上傳成功但後續儲存失敗時，重試應避免重複上傳與留下無主檔案。
- 使用者照片、活動圖片載入失敗要有統一 fallback；另以長暱稱、長活動名、多身份、多坑單、很多參加者測試，不能只用空狀態測 UI。

## 建議處理順序

1. 修 A01／A02／A03／A04：避免改錯日期、解散圈圈、活動重複及空資料覆蓋。
2. 修 A09／A10／A11／A19：網路錯誤、認證失效與歷史活動操作規則。
3. 修 A05／A06／A07／A14／A20／A22：Web 可用性、HTTPS、分享入口與選圖。
4. 修 A08／A15／A16／A17／A21：逐日社交與現場訊號、通知／OOBE 狀態。
5. 修 A12／A13／A18，再整理表單與資訊層級。

## 下一輪 QA 驗收清單

- 新註冊→OOBE 中途退出→重新登入→補完身份→名片顯示；跨裝置重登。
- D1／D2／D3 各有不同角色、照片和留言，修改／取消任一日只影響該日。
- 過去單日、今日、未來單日，以及多日活動中「昨天／今天／明天」的讀寫限制。
- 同活動至少 2 位關注者與 2 位圈圈成員，確認 API、月曆和列表不重複且日別訊號正確。
- 同圈圈與非同圈圈、雙向封鎖、取消關注、離圈後的名片／預定／位置／集合點可見性。
- 擁有者離圈、轉移擁有者、明確解散，確認成員與集合點後果。
- 飛航模式啟動、登入 token 過期、500、逾時、操作中切頁與連點；驗證資料及草稿保留。
- JPEG／PNG／WebP、大圖、圖片上傳成功後儲存失敗、刪第一張與照片重新排序。
- Web 開官方來源、下載分享圖；用系統相機掃 QR，沒有 App／未登入時也可完成流程。
- Android／iOS 前景、背景、冷啟動的 D2／D3 認親通知；登出後不收原帳號通知。
- 定位拒絕／永久拒絕、精確與近似位置、停止分享、到期、緊急隱身、移動後更新。
- 窄螢幕、大字體、長內容、鍵盤開啟、橫向、亮暗主題；包含所有 OOBE 步驟、彈窗及有資料的社交頁。

本輪未部署、未變動正式 DB、未修正產品程式。此報告是問題與驗收依據，不代表完整實機 QA 已完成。
