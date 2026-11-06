# Android 完整功能驗證續測

本輪接續正式法律同意修復後的 Android 操作驗證。結果不是全功能驗收通過。產品程式與 GCP release 均未在本輪修改或部署。

## 環境與隔離

使用 `emulator-5554`、Android 9 API 28、1080 x 1920、360dp 寬度，沿用已安裝的 debug APK。所有 API 指向 `https://coscircle.app/api`。主流程控制模擬器，兩個代理分別執行限定的社交與活動 API 檢查，均沿用預設模型。

依使用者先前授權，只建立或修改專用 QA 資料。未向真實使用者發送邀請或修改其資料。憑證檔均位於 Git 忽略的 `build/qa-android-20261030`，權限 600。API 檢查沿用模擬器目前 token，未重新登入使模擬器失效。

## 待修問題

| 編號 | 等級 | 實際結果 | 重現與證據 |
| --- | --- | --- | --- |
| AF03 | P1 | 位置分享設定底部溢出 169 像素。確認按鈕無法看到，向上滑仍無法帶出，阻塞此尺寸的分享流程。 | 加入 QA 場次，現場頁點定位圖示，確認隱私後開啟分享設定。`71-location-settings.png`、`72-location-after-swipe.png`。`current_event_page.dart:1480` 的 bottom sheet 內容未提供捲動，且沿用預設高度上限。 |
| AF04 | P2 | 新建小圈圈鍵盤展開後底部溢出 13 像素，建立與取消按鈕受到黃黑警示覆蓋。 | 同好、小圈圈、建立。`66-create-circle.png`。收起鍵盤可繼續建立，見 `67-circle-keyboard-hidden.png`、`68-circle-created.png`。`social_page.dart:457` 的 Dialog 內 Column 未提供捲動。 |
| AF05 | P2 | 分享圖的名字只看到 `QA_Android_`，未完整顯示 `QA_Android_FieldTest`，影響辨認。 | 從活動詳情產生分享圖並取得實際輸出 `booking-share-generated.png`。不是僅依預覽截圖推測。名字區域實作位於 `event_booking_share_page.dart:1275`、`:1407`，確切字型與尺寸修正仍待測。 |

另有兩項低優先改善。首次位置分享的隱私提示文字被省略號截斷，證據為 `70-location-dialog.png`。選圖後將裝置內部 cache 路徑當成說明顯示，證據為 `81-photo-selected.png`。本輪未修正以上問題。先前 AF02 的一般 404 錯誤文案仍未修改。

## 裝置實測

| 流程 | 結果與限制 | 證據 |
| --- | --- | --- |
| 身份與名片 QR | 同時顯示 Coser 與攝影。QR 面板在目前尺寸沒有觀察到溢出。未以另一台實體相機掃描。 | `47-profile.png`、`48-profile-qr.png`。 |
| 編輯與儲存 | 捲動後儲存按鈕仍固定底部。修改暱稱成功，強制停止重開仍保留，沒有重跑 OOBE。 | `49-edit.png` 至 `52-profile-relaunch.png`，以及正式 API 重讀結果。 |
| 日曆與舊活動 | 在日曆區上下滑可帶動整頁。選擇 10/10 後可看到 D2 卡片，點整張卡片進詳情。舊活動可讀，加入按鈕顯示停用或已結束。未逐一窮舉全部日期結果。 | `53-calendar.png` 至 `56-past-event-detail.png`。 |
| 預定修改與上傳 | 在 QA D1 預定改為攝影、輸入備註，經 Android 選圖器選擇專案 logo，儲存成功。本次沒有重現 500。正式 API 重讀身份、備註與圖片 URL 正確，圖片 GET 200 且為 image，507096 bytes。 | `75-booking-edit.png` 至 `85-participants-loaded.png`，`device-persistence-results.json`。 |
| 預定分日 | 畫面 D1 為修改預定，D2、D3 為可加入操作，沒有被連動標示為已加入。 | `83-qa-event-details-lower.png`。分日持久化另由 API 驗證。 |
| 活動參加者 | 未關注 B 時，QA 活動詳情仍顯示 A、B 的 D1 預定，可見 B 為路人、A 為攝影。 | `85-participants-loaded.png`。未在本輪覆蓋封鎖與小圈圈限定的所有組合。 |
| 分享圖 | 可產生圖檔並開啟 Android 原生分享選單，未選收件人或傳送到任何服務。生成檔有 AF05 名字截斷。 | `86-share-preview.png`、`87-native-share-sheet.png`、`booking-share-generated.png`。 |
| 小圈圈 | 收起鍵盤後從 UI 建立成功。正式 API 重讀確認；B 透過 API 加入後成員數為 2。未宣稱 B 已完成掃碼加入。 | `68-circle-created.png`、`device-persistence-results.json`、`social-ui-preparation.json`。 |
| 好友 | B 透過 API 向 A 發出附場次的邀請。A 在 UI 看到活動、D1、日期、介紹文並接受。接受後清單與個人名片仍保留當時介紹，API 重讀為 accepted。 | `88-friend-incoming.png` 至 `92-profile-actions.png`，`device-persistence-results.json`。 |
| 關注 | 在 B 名片按加入關注，再取消關注，畫面狀態切換成功。正式 API 重讀確認最終未關注。 | `93-followed.png`、`94-unfollowed.png`、`device-persistence-results.json`。 |
| 現場地圖 | 無場次時有空狀態，加入 QA D1 後能辨認當前場次並載入 Google 地圖。模擬器注入人工座標，不使用使用者真實位置；UI 分享受 AF03 阻塞，未送出。 | `57-current-empty.png`、`69-current-qa-event.png` 至 `72-location-after-swipe.png`。 |
| 設定 | 認親通知可切關閉並顯示提示，再切回開啟。可切夜間主題，重開後仍保留。一般 QA 帳號完整設定頁未見管理員連線入口。沒有測得背景推播成功。 | `58-settings.png` 至 `64-social.png`、`69-current-qa-event.png`。 |

## API 專項

社交腳本完成 30 次請求、63 項斷言。包含雙向追蹤、重複追蹤、取消追蹤、空介紹拒絕、有效及重複邀請、介紹保存、接受與移除後雙方重新讀取。這些是 API 證據，不等於每一項均經過 UI。

活動腳本完成 165 項斷言。包含只加入 D2、修改不重複、D0 與 D4 拒絕、加入 D1 後取消 D2 保留 D1、B 的合成公開座標可由 A 讀取、更新後 A 讀到新座標、停止後雙方位置名單不再含 B。每次寫入前檢查 API 可見的參加者僅為 QA 帳號，不等同完整 DB 人員清查。

腳本與原始結果分別為 `.audit/qa-social-api-20261030.mjs`、`.audit/qa-event-api-20261030.mjs`，以及 `social-api-results.json`、`event-api-results.json`。本輪沒有重跑先前 395 項 Flutter 與 175 項隔離後端測試，不將它們計入本輪成功數。

UI 準備腳本起初誤把 API 對收件者回傳的 `incoming` 狀態預期成 `pending`。已修正腳本並重跑成功，這是測試工具假設錯誤，不列 App 缺陷。

## 留存資料與未測項目

- QA A 為 user 17，暱稱已改為 `QA_Android_FieldTest`。QA B 為 user 18，暱稱 `QA Social B 20261030`，本輪新建，未註冊裝置推播 token。
- 測試活動為 event 627，來源鍵 `qa-android-20261030-functional-only`，名稱 `QA 功能驗證（非真實活動）`，日期 10/30 至 11/01，地點明示虛擬且請勿前往。準備腳本只針對此來源鍵執行不存在才新增，不會更新其他活動，也沒有 migration。首輪結果未記錄 INSERT 的 affectedRows，不能僅憑該 JSON 區分首次新增與重用。此活動為 approved，會出現在正式公開列表。
- A、B 各保留 D1 預定。A 為攝影，含測試備註及 logo 圖片。B 停止分享位置。A 未從 UI 成功分享位置。
- 小圈圈 2 為 `QA_Only_20261030`，A 建立，成員 A、B。好友邀請由 B 提出、A 在 UI 接受，目前保留 accepted，A 最終未關注 B。
- 未執行真實 LINE 授權、Email 收信、實體 QR 掃描、背景 FCM 收訊、GPS 拒絕與權限恢復、移動中的更新、好友忽略的 UI 與保密性、集合點、同坑配對、全部封鎖與可見範圍組合、完整九項準備度與恭喜動畫。
- 未送出檢舉或刪除帳號。這些功能的完整安全部署仍是另一個未完成項目，不能從此次驗證推論它們已能上線。

所有編號截圖與 JSON 位於 `/Users/frank/FlutterProjects/coscircle/build/qa-android-20261030`。截圖與生成圖片證明了本輪前端缺陷；error 級 logcat 沒有對應輸出，不能因此忽略畫面上的 overflow。

以上留存資料為各次記錄檢查時的快照，不是持續監控。最終持久化檢查補記 `checkedAt` 與 `runKey`。獨立唯讀檢核確認 API 數量與 AF03 至 AF05 證據一致，並要求區分資料快照與現況、準備與首次新增。已補上這些限制，並限制持久化腳本的 QA 身分與來源。該檢核不涵蓋全部程式或部署安全，也不代表產品驗收通過。
