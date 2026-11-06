# CosCircle 功能規格書

| 項目 | 內容 |
| --- | --- |
| 文件版本 | 1.0，現況整理版 |
| 基準日期 | 2026-10-30，Asia/Taipei |
| 產品 | CosCircle／Cos 小圈圈 |
| 專案 | `/Users/frank/FlutterProjects/coscircle` |
| 程式基準 | Git `42bff54` 加目前未提交工作目錄；不是只描述該 commit |
| 主要使用者端 | Flutter Android、iOS、Web；本輪既有實測以 Android 模擬器為主 |
| 正式服務 | [CosCircle](https://coscircle.app)，API 為 `https://coscircle.app/api` |
| 文件用途 | 產品溝通、開發交接、功能驗收及版本範圍核對 |

## 1. 範圍與證據

本文從目前程式、資料結構、部署文件及既有 QA 紀錄反向整理功能，不是重新設計產品，也不代表全部功能已上線。本文產出期間沒有修改 App、呼叫外部來源或變更正式資料。

功能敘述分為以下證據層級，與上線狀態分開判讀。

| 標記 | 意義 |
| --- | --- |
| 已確認 | 有程式、資料結構、部署紀錄或指定 QA 結果支持；不自動等於實機驗收通過。 |
| 推論 | 可從現有流程推導的產品目的，不作為已確認行為。 |
| 待確認 | 產品決策、正式部署或平台實測缺乏足夠證據。 |
| 範圍外 | 本文件不新增的需求，不代表永遠不會支援。 |

功能章節的「驗收條件」是後續測試應檢查的可觀察結果，不是本輪全部通過的宣告。已知不符合項目集中於第 13 節。

依「實際驗證」原則，現況以程式與有日期的紀錄為依據。對於刪除帳號、檢舉及同意管制，特別區分工作目錄實作與正式環境。舊文件若與較新的部署紀錄衝突，以較新且範圍明確的紀錄為準。

## 2. 產品定位

CosCircle 為 cosplay、ACG 及同人活動參與者提供活動前發預定、活動中找人及活動後辨認同好的工具。互動以名片、共同作品、戳友與小圈圈為主，不以男女配對或約會為定位。

主要使用情境如下。

1. 使用者整理個人身份、坑單及照片，產生可掃描的名片。
2. 使用者瀏覽場次，對特定日期發布攝影、Coser、馬內或路人預定。
3. 現場交換 QRCode，選擇單向關注或留下自我介紹提出戳友邀請。
4. 雙方日後透過場次、日期及當時介紹辨認對方。
5. 使用者依可見範圍主動分享位置，或與小圈圈成員約定集合點。
6. 管理員維護活動、審核投稿及查看同步結果。

完整即時聊天、付費交易、售票及自動配對不屬於本文新增範圍，不能從社交功能推論已有這些能力。

## 3. 角色與名詞

### 3.1 權限角色

| 角色 | 主要能力 | 限制 |
| --- | --- | --- |
| 未登入訪客 | 使用登入、註冊、忘記密碼及公開信箱操作頁；閱讀條款與隱私政策；匿名開啟 App 公開名片頁及其 API。 | 不取得個人化預定、社交與現場操作權限，關注或戳友等互動仍需登入。 |
| 一般使用者 | 維護自己的名片與預定，操作關注、戳友、小圈圈及現場互動。 | 受帳號狀態、雙向封鎖、可見範圍及場次條件限制。 |
| 小圈圈擁有者 | 編輯自己建立的小圈圈、管理成員及解散。 | 不是全站管理員，不能操作其他小圈圈或全站活動管理。 |
| 管理員 | 使用管理後台，維護活動、處理投稿與管理帳號。 | 管理端操作仍需服務端驗證；檢舉審核屬尚待完整部署範圍。 |

個人身份與權限角色不同。Coser、攝影等個人身份為複選展示資訊；單日預定的身份為該日扮演的單一角色，不會因此取得管理員權限。

### 3.2 核心名詞

| 名詞 | 定義 |
| --- | --- |
| 活動 | 同一場次的主資料，包含日期範圍、地點、主辦及來源。 |
| 單日場次 | 活動內的一天，以 `dayIndex` 從 1 開始區分 D1、D2、D3。 |
| 預定／出席 | 某帳號對某活動某一天的參加資訊；不是整個多日活動共用的一筆勾選。 |
| 名片 | 個人資料與公開識別碼連結，可透過 QRCode 開啟。 |
| 關注 | 單向關係，不要求對方同意。 |
| 戳友 | 先邀請、再由收件者確認的雙向關係，保留認識上下文。 |
| 小圈圈 | 由擁有者建立、使用邀請碼或 QR 加入的群組。 |
| 同坑 | 依雙方坑單的共同作品比對，不等於好友或位置共享授權。 |
| 認親 | 活動當天對特定對象發出的短時效互動訊號，不等於永久戳友。 |

## 4. 導覽與功能分組

底部主要導覽為「名片、活動、現場、同好、設定」。進一步頁面包含活動詳情、我的活動、分享圖、公開名片、掃碼、帳號操作及管理後台。詳細路由及來源見第 14 節。

| 分組 | 功能編號 | 入口及輸出 |
| --- | --- | --- |
| 帳號 | AUTH | 註冊、Email 登入、LINE 登入與綁定、信箱驗證、密碼重設、登出。 |
| 首次設定 | ONB | 啟動等待、明確同意、首次資料引導及完成狀態。 |
| 個人名片 | PROF、WORK | 資料編輯、身份、坑單、照片、QRCode、認親準備度及場次安全。 |
| 活動 | EVT、BKG、SHARE | 月曆、篩選、活動詳情、單日預定、我的活動及分享圖。 |
| 同好 | FOLLOW、FRIEND、CIRCLE、SAME | 關注、戳友、小圈圈與先選作品的尋找夥伴。 |
| 現場 | LOC、MEET、REC | 地圖、位置分享、集合點與認親訊號。 |
| 設定與安全 | SET、SAFE | 主題、通知、意見回饋、政策、帳號刪除與檢舉。 |
| 管理與同步 | ADMIN、SYNC | 管理後台、活動投稿審核、帳號管理與多來源同步。 |

## 5. 主要使用流程

### 5.1 首次註冊與再次開啟

1. App 開啟後先還原登入狀態，判斷前顯示 loading 與品牌動畫。
2. 沒有有效登入狀態時顯示登入入口。使用者可用 Email 註冊或啟用的原生 LINE 登入。
3. 登入頁依帳號 OOBE 完成狀態選擇首次設定或返回目標頁；目的頁有法律 gate 時，先要求目前版本明確同意。
4. 尚未完成首次設定的帳號經同意後使用 OOBE，完成後進入主頁。
5. 已完成帳號重新登入、換裝置或重裝後，不因缺少本機 OOBE 記錄而再次強制引導；以帳號資料為準。

Email 註冊會嘗試寄驗證信，但不等待收信才建立帳號。驗證目前不是進入主頁的強制門檻。使用者可從設定頁主動重看引導。

以上是從登入頁進入的一般流程，不是所有路由的全域強制順序。全域 redirect 目前檢查 token 及 sessionExpired，未全域檢查 OOBE；公開名片及 `/admin` 未包同一法律 gate。若要求所有入口一致強制 OOBE 與同意，需另行規範及驗收。

### 5.2 活動前發布單日預定

1. 在活動月曆選日期，或以清單與關係篩選瀏覽。
2. 點活動卡片進入詳情，選擇實際參加日。
3. 已有該日預定時開啟修改，否則開啟新增。
4. 選擇當日身份，補充角色、作品、可互動時間、互動方式、現場狀態、照片及備註。
5. 儲存後只改變該帳號的該活動該日預定，可在活動詳情及我的活動查看。
6. 需要分享時產生預定分享圖，再由使用者選擇外部分享對象。

過去日期保留瀏覽，不提供新增、修改或取消出席。統計與分享可彙整同一活動的多日內容，參加狀態與日期篩選不得跟著合併。

### 5.3 掃碼認識同好

1. 對方出示個人名片 QRCode。
2. 掃碼者開啟對方名片，可單純關注，也可另行提出戳友邀請。
3. 戳友前輸入簡短自我介紹，可帶入明確選取的場次與日期。
4. 收件者在現場或事後閱讀介紹，再確認或忽略。
5. 確認後雙方名單保留認識場次、日期與介紹；忽略不向邀請者透露拒絕狀態。

例如「我是戴黑色帽子，在水池旁拍照的攝影」屬邀請上下文，不會自動改寫邀請者公開自介。

### 5.4 現場找人

1. 加入符合現場操作條件的活動日期後，從現場頁選擇對應活動。
2. 使用者自行開啟位置分享，選擇可見對象與自動停止時間，再授權定位。
3. 其他符合可見條件的使用者透過地圖與雷達讀取目前有效位置。
4. 分享者可主動更新座標或停止分享；到期後不可繼續當成有效位置。
5. 認親訊號與小圈圈集合點提供不同互動入口，各自依權限處理。

目前沒有承諾背景持續追蹤或隨使用者移動自動上報。詳見 LOC 功能規則。現場位置分享的已知面板阻塞仍須修正。

## 6. 功能明細

以下功能預設為「已確認程式實作」。正式可用性及已知缺陷另見第 13 節。沒有實測的項目不標成驗收通過。

### 6.1 AUTH：帳號註冊、登入與復原

| 編號 | 功能與規則 | 例外或限制 |
| --- | --- | --- |
| AUTH-01 | Email 註冊接受暱稱、Email 與密碼。Email 去頭尾空白、轉小寫，服務端檢查格式及最多 191 字元；密碼至少 8 字元。空暱稱使用預設名稱。 | 重複 Email 拒絕，不建立第二個同 Email identity。驗證信寄送失敗不回滾帳號建立。 |
| AUTH-02 | Email 登入核對 identity 與密碼，成功後取得 CosCircle session。帳號須為 active。 | 錯誤憑證拒絕，停權拒絕。現行每帳號單一有效 session，新登入使先前裝置 token 失效；不是多裝置同時在線。 |
| AUTH-03 | 啟動從本機還原 token，再向服務端確認。網路失敗顯示重試，不先跳登入再跳主頁。 | 無效 session 清除登入；舊請求的延遲失敗不得清除新登入狀態。 |
| AUTH-04 | 原生 LINE 登入限 Android、iOS 且建置開關啟用。SDK 只要求 profile，服務端驗證 channel、期限及身份。 | 使用者取消不建立帳號。Web 沒有等效原生 LINE 流程；真實授權尚待完整驗收。 |
| AUTH-05 | 首次未綁定 LINE 登入建立獨立帳號。Email 使用者可在登入方式頁，重新驗證原密碼並完成 LINE 授權，明確綁至原帳號。 | 不按 Email 自動合併；已屬其他帳號的 LINE 拒絕綁定。LINE-only 新增 Email、解除綁定及合併既有兩帳號尚未提供。 |
| AUTH-06 | 已有 Email identity 可申請驗證信。驗證有效一小時，須按確認才消耗一次性連結。 | GET 開啟頁面不自動驗證；錯誤、過期、重複使用或用途不符的 token 拒絕。未驗證仍可使用目前功能。 |
| AUTH-07 | 忘記密碼對格式有效的 Email 統一回覆申請已受理，不透露帳號是否存在。可復原的對象只有 Email identity。 | LINE 個人資料中的 Email 不會自動成為復原身份。未知、停權及 LINE-only 帳號不因回覆差異被列舉。 |
| AUTH-08 | 重設連結有效十五分鐘。新密碼 8 至 1024 字元，前端兩次輸入一致。成功後驗證 Email、作廢未完成信箱操作、撤銷 session 與推播 token，要求重新登入。 | 保留既有名片、預定、社交與 LINE 綁定。寄信通知失敗不撤銷已完成的密碼變更。 |
| AUTH-09 | 同一 Email identity 共用寄信頻率限制，每六十秒一次，滾動二十四小時最多六次。登出清除本機登入。 | 現行初始驗證與重設寄送不是持久化 outbox，API 重啟可能使尚未送出的背景工作遺失。 |

驗收條件：重複註冊不產生重複身份；LINE 綁定後仍為原 user ID；未驗證 Email 可完成引導；重設後舊 session 無效；登出時即使 API 失聯也不得保留本機登入。Facebook 手動 token 測試入口不列為完成的原生 Facebook 登入產品。

來源：[登入流程](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:183)、[身份分離](/Users/frank/FlutterProjects/coscircle/backend/src/auth-identities.js:36)、[信箱服務](/Users/frank/FlutterProjects/coscircle/backend/src/email-account-service.js:26)、[啟動還原](/Users/frank/FlutterProjects/coscircle/lib/core/repositories/auth_repository.dart:75)。

### 6.2 ONB：明確同意與首次設定

- ONB-01：條款與隱私目前版本為 `2026-10-28`。初始不勾選；使用者明確勾選及成功送出後，才進入主要社群頁面。
- ONB-02：同意查詢不產生同意紀錄。同版本重送不重複新增，錯誤內容或過期版本拒絕。初次查詢失敗保留阻擋與重試入口。
- ONB-03：OOBE 包含三頁介紹與一頁暱稱、複選身份、地區設定，可略過。正常完成儲存資料並記錄帳號完成狀態；略過只記錄完成。
- ONB-04：既有資料尚未載入或儲存失敗時，不可假成功離開。OOBE 不要求一次填滿個人資料九項準備度。
- ONB-05：已完成帳號在換裝置或重裝後不重跑；使用者仍可主動重看教學。不同意時保留閱讀法律、登出、聯絡及刪除入口，刪除正式可用性另列。

此 gate 作用於有包裝的頁面，不是全域 router 或每個 API 的共同保證；一般登入流程與公開名片、管理頁例外見第 5.1 節。

驗收條件：未勾選不能繼續，成功後重開不重複要求同版本同意；略過不覆寫原名片；重新登入已完成帳號直接回主要頁面。正式法律 hotfix 只證明同意端點可用，不代表舊客戶端已受到全面服務端發布限制。

來源：[法律服務](/Users/frank/FlutterProjects/coscircle/backend/src/legal-consent.js:1)、[首次設定](/Users/frank/FlutterProjects/coscircle/lib/features/profile/presentation/onboarding_profile_page.dart:182)、[同意畫面](/Users/frank/FlutterProjects/coscircle/lib/features/safety/presentation/legal_acceptance_page.dart:100)。

### 6.3 PROF：個人名片、準備度與場次安全

| 欄位或操作 | 規則 |
| --- | --- |
| 暱稱、頭像、自介 | 暱稱去空白後不得空白；資料儲存成功才離開編輯。 |
| 個人身份 | Coser、攝影、馬內、路人，可複選，在名片以圖示與身份標籤顯示。 |
| 個人資訊 | 年齡、性別、Facebook 網址、雷點。性別含不公開；現有年齡欄位沒有明確數字範圍驗證，不等於已實作年齡限制。 |
| 座標與跑場 | 座標在此代表常駐地區，不是 GPS；選項包含北部、中部、南部、離島、海外，另有跑場範圍及同常駐地區選擇。 |
| 照片 | 頭像及其他照片。其他照片最多三張；圖片檔頭接受 JPG、PNG、WebP，讀取上限 5 MiB。 |
| 編輯操作 | 同類訊號及準備度項目可開對應編輯位置；儲存列固定底部，失敗保留草稿與錯誤。 |
| 個人 QRCode | 編碼公開名片 URL，公開碼缺少時提示；掃描成功開啟名片，不自動關注或自動戳友。 |
| 場次安全 | 設定預定公開或僅小圈圈可見；可移除追蹤者、封鎖與解除封鎖。追蹤者細節預設收合。 |

PROF-01：認親準備度共九項，為暱稱、頭像、自介、身份、座標、跑場、深坑、淺坑、照片。各項依目前非空狀態計數，不是人工審核或內容品質評分。

PROF-02：未滿時可點缺項補齊；本次儲存由未滿轉為九項全滿時，且名片頁仍可見，顯示恭喜動畫。已滿再次儲存不重播。滿九項後隱藏準備卡，減少動畫設定停用動態效果。

PROF-03：公開名片提供基本資料、身份、照片與坑單，不提供 Email 或登入憑證，雷點在公開回應中清空。已登入使用者之雙向封鎖會阻止讀取，但匿名持有公開連結仍可讀公開資料，不能承諾封鎖能撤回已公開名片。

驗收條件：複選身份重開仍保留；儲存失敗仍可修改原草稿；QR 小螢幕不溢出；九項完成只在轉換時恭喜且隱藏；公開名片不洩漏帳號憑證。

來源：[名片儲存](/Users/frank/FlutterProjects/coscircle/lib/features/profile/presentation/profile_page.dart:357)、[準備度](/Users/frank/FlutterProjects/coscircle/lib/features/profile/presentation/profile_page.dart:633)、[恭喜動畫](/Users/frank/FlutterProjects/coscircle/lib/features/profile/presentation/profile_readiness_celebration.dart:40)、[公開資料界線](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:2991)。

### 6.4 WORK：作品與坑單

- WORK-01：搜尋及選取作品，必要時建立作品標籤，供名片與預定引用。
- WORK-02：深坑與淺坑分別多選，資料以作品 ID 關聯，不以顯示名稱作身份。
- WORK-03：同作品同時被選深坑與淺坑時，依目前唯一鍵及寫入順序推論深坑保留；是否應在 UI 禁止雙選屬待確認規則，不列為已驗收行為。

驗收條件：作品選擇儲存後能還原，沒有作品時不誤顯示為已填寫；同坑比對依共同作品而非暱稱。

來源：[坑單關聯](/Users/frank/FlutterProjects/coscircle/backend/db/schema.sql:54)、[寫入規則](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:588)。

### 6.5 EVT：活動探索與詳情

- EVT-01：一般列表顯示 approved 活動，按日期排序；已結束活動仍可取得。審核狀態為 pending、approved、rejected，與時間狀態「未開始、進行中、已結束」分開。
- EVT-02：多日活動逐日展開，月曆日期與列表以實際 D 日篩選。上下滑動月曆仍可帶動整頁，橫滑可換月。
- EVT-03：快速篩選包含全部、我有加入、關注者、小圈圈、戳友，可搭配日期及隱藏已結束。關係訊號依日次判斷，不把同活動其他日當成同日參加。
- EVT-04：篩選與月曆焦點保存於本裝置。活動探索預設不隱藏已結束；我的活動清單則預設隱藏已結束，兩者預設不同。
- EVT-05：整張活動卡可開詳情；顯示日期、場地、地址、分類、來源名稱與原網址。原生 App 可用 WebView 閱讀來源，Web 開外部頁。
- EVT-06：詳情可看所有符合公開或圈內可見規則的預定，不必先關注作者；排除非 active 及任一方向封鎖對象，依日期分組。
- EVT-07：活動總參加人數按 user ID 去重；各日仍保留獨立內容。探索的場數可按展開後日數計，已加入摘要按活動計，不能將兩者當成同一數量。

現況差異：探索「同好訊號」摘要目前只計關注或圈友活動，尚未把戳友納入同一公式；戳友篩選本身已有實作。這是統計口徑差異，不應寫成所有社交計數已同步。

驗收條件：點 10/10 只列符合 10/10 的 D 日；舊活動可讀但不能操作過去預定；未關注仍可看到公開預定；只加入 D2 不使 D1、D3 顯示已加入。

來源：[分日模型](/Users/frank/FlutterProjects/coscircle/lib/core/models/event_day_item.dart:10)、[篩選](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/event_list_page.dart:343)、[參加者可見性](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:1791)、[摘要口徑](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/event_list_page.dart:614)。

### 6.6 BKG：單日預定與我的活動

| 資料 | 規則 |
| --- | --- |
| 活動與日期 | 唯一鍵為活動、使用者、dayIndex；日次須為 1 至活動總日數的整數。 |
| 當日身份 | 攝影 photographer、Coser coser、馬內 manager、路人 self，單選。manager 不是管理員。 |
| 作品與角色 | 支援作品 ID、角色名稱；前端只在 Coser 身份送作品 ID。 |
| 互動 | 認親、拍照、交換無料、聊天、一起逛、找同作品等 UI 選項。 |
| 現場狀態 | 可來找我 open、移動中 moving、休息中 resting、暫不互動 quiet、已離場 left。後端未同等白名單驗證，不宣稱所有非法值均被拒絕。 |
| 其他資訊 | 可互動時間、當日照片、備註。角色與時間資料欄各 120 字元，不代表 UI 已有完整字數驗證。 |

BKG-01：儲存同一天為更新，不新增重複預定；取消指定日只刪該日，保留其他日期。前端修改前先讀既有資料，載入失敗不開空白表單覆寫。

BKG-02：服務端依台北日期判斷過去日，加入、修改、取消回拒絕，不等整個活動結束。API 的未指定日次整批取消與 UI 單日取消不同；若整批內含過去日，整次拒絕。

BKG-03：照片先成功上傳再儲存預定。我的活動逐日列出自己的預定，未結束排前。參加過活動的彙整不得改寫原有分日資料。

驗收條件：D0 與超出活動天數拒絕；重存 D2 不重複；取消 D2 保留 D1；D1 已過但 D2 今天時，只有 D2 可改。上傳失敗不得顯示儲存成功。

來源：[預定鍵與欄位](/Users/frank/FlutterProjects/coscircle/backend/db/schema.sql:109)、[新增與修改](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:1641)、[單日取消](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/event_booking_sheet.dart:530)。

### 6.7 SHARE：預定分享圖

- SHARE-01：從同一活動收集自己的各日預定，在一張分享圖中呈現；畫布可涵蓋活動全日數，未加入日不能虛構預定。
- SHARE-02：支援照片及角色文字的拖曳、縮放、旋轉，以及顏色、字級調整，輸出 PNG。
- SHARE-03：使用者按分享後開啟原生分享選單，不自動傳送或選取收件人。編輯分享外觀不等於更新後端預定。
- SHARE-04：輸出需能辨識暱稱、日期、身份及內容，不可只驗證畫面預覽。現有長暱稱截斷 AF05 尚待修復。

驗收條件：單日照片與角色放在正確 D 日；多日資料合併輸出但不連動修改參加狀態；產出的 PNG 與預覽一致且長文字可辨識。

來源：[多日收集](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/my_events_page.dart:207)、[分享輸出](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/event_booking_share_page.dart:471)。

### 6.8 FOLLOW：單向關注

- FOLLOW-01：A 關注 B 不代表 B 關注 A；不能關注自己，重複請求不建立重複關係。
- FOLLOW-02：取消關注只刪自己追蹤對方的方向；移除追蹤者只刪對方追蹤自己的方向。
- FOLLOW-03：活動篩選的「關注者」實際為「我關注的人有預定」；場次安全的追蹤者名單為「關注我的人」。該名單不是名片瀏覽紀錄。
- FOLLOW-04：關注、好友、小圈圈分別維護，任何一種成功都不自動建立其他兩種關係。

驗收條件：A 關注 B 後 B 的追蹤清單不自動新增 A；取消後可重新關注，且畫面與重新讀取結果一致。

來源：[關注與移除方向](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:1829)、[活動關係查詢](/Users/frank/FlutterProjects/coscircle/backend/src/event-queries.js:33)。

### 6.9 FRIEND：戳友邀請與關係

- FRIEND-01：邀請必填去空白後 1 至 200 個 Unicode 字元的簡短介紹，可附 approved 活動與有效 dayIndex。後端不要求雙方已有預定或活動尚未結束，因此可事後補上認識場次。
- FRIEND-02：每對使用者只有一組關係。介紹、場次名稱、日期及日次保存為當時快照，不以接受時間取代認識日期；清單區分自己與對方留下的介紹。
- FRIEND-03：只有原收件者可以接受或忽略待處理邀請。接受後成為雙向戳友，不自動關注。
- FRIEND-04：忽略狀態只供內部使用，邀請者仍見等待確認，不收到拒絕通知；重送不覆寫介紹或重新進入收件匣。原收件者可反向提出新邀請。
- FRIEND-05：雙方同時邀請不自動接受。已接受可解除，保留各自獨立的關注及圈子關係。
- FRIEND-06：只把 accepted 納入活動及地圖好友篩選；好友關係不直接授予圈內預定或私人位置讀取權。

| 狀態 | 對發送者 | 對收件者 |
| --- | --- | --- |
| pending | 等待確認 | 收到邀請，可接受或忽略。 |
| ignored，僅內部 | 仍為等待確認 | 不再列為來邀。 |
| accepted | 已成為戳友 | 已成為戳友。 |

驗收條件：空介紹拒絕；重送不洗掉原介紹；忽略不洩漏拒絕；非收件者不能回覆；接受與解除不改動關注；任一方向封鎖者不可邀請。戳友沒有套用認親訊號的五分鐘到期規則。

來源：[好友狀態與驗證](/Users/frank/FlutterProjects/coscircle/backend/src/friendships.js:24)、[好友產品規則](/Users/frank/FlutterProjects/coscircle/docs/product/friendships.md)。

### 6.10 CIRCLE：小圈圈

- CIRCLE-01：使用者可建立小圈圈，填寫名稱及說明。名稱去空白後不可空；建立者自動成為擁有者及成員。
- CIRCLE-02：透過邀請碼、網址或 QR 加入。重複加入不重複增員，無效邀請顯示失敗。
- CIRCLE-03：成員可看圈子與成員名片。只有擁有者可編輯、移除成員、解散；擁有者不能用一般退出或踢自己代替解散。
- CIRCLE-04：解散會移除成員關聯及集合點。封鎖不等於自動退出同圈；一般成員名單隱藏互相封鎖者，圈主可見遮蔽列以便管理。

驗收條件：建立後成員數為一；同邀請重入不增加人數；非圈主修改被拒絕；解散與踢人須確認。鍵盤展開時仍可操作建立與取消，現況 AF04 未達此條件。

來源：[圈子建立與權限](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:1316)、[圈成員遮蔽](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:1264)、[圈子表單](/Users/frank/FlutterProjects/coscircle/lib/features/social/presentation/social_page.dart:457)。

### 6.11 SAME：同坑雷達與尋找夥伴

- SAME-01：他人公開名片以雙方 `pitWorks`、深坑及淺坑的作品 ID 交集比對，每個非空 ID 只計一次。有交集時顯示「同坑雷達！你們有 N 部共同作品」，並高亮對方深淺坑內的共同標籤，附雷達圖示與「與我同坑」無障礙語意。
- SAME-02：訪客、自己的名片、沒有交集時不顯示提醒。登入者坑單載入中或失敗不宣稱沒有共同作品；失敗提供重新讀取，登入者資料依工作階段版本重新取得。
- SAME-03：「同好」的「尋找夥伴」先列作品，再點作品查看人員。「與我同坑」使用 `scope=mine`，列自己深淺坑作品，包含零位夥伴；「看看大家坑什麼」使用 `scope=all`，只列至少一位合資格其他使用者的作品，不要求自己已加入該作品。
- SAME-04：作品卡顯示名稱、不重複合資格其他使用者的 `partnerCount` 及 `isMine` 對應的「我的坑」。兩個範圍皆按資料庫作品名稱、作品 ID 升序排序。人數與人員清單排除自己、非 active、無公開碼及任一方向封鎖者，不因已關注或已是戳友而排除。
- SAME-05：兩分頁各保留自己的已提交搜尋字串，按搜尋鍵後以作品名稱包含字串查詢。上限為 100，後端按字串長度檢查；`%`、`_` 與 `!` 是字面值，不作萬用字元。名稱比對與排序依資料庫定序規則。
- SAME-06：所選作品的人員按使用者 ID 升序排列，不按共同作品數排序。顯示名片基本資料與雙方全部共同作品，可查看名片及依現有邀請流程戳友；雙方沒有交集仍可出現在所選作品的人員頁。回應不附 Email、登入憑證、預定或位置。戳友狀態尚未成功讀取時停用邀請，失敗可重試。
- SAME-07：新作品與人員端點每頁預設二十筆，最多五十筆，offset 上限十萬；非法分頁、scope、搜尋或作品 ID 回傳 400。可下拉重新整理、載入更多與重試。載入更多失敗保留原內容，追加按 ID 去重；重新整理及切換工作階段後，舊請求不得追加到新結果。修改坑單與更新社交關係會重新讀取探索資料。
- SAME-08：舊 `/social/same-works` 保留原人員回應及共同作品數降序、使用者 ID 升序排序。沒有共同作品仍回傳空頁，不代替新入口的全站作品探索。同坑結果不授予好友或位置可見權限。

驗收條件：跨深淺坑能正確高亮與計數；訪客、自己及讀取失敗不誤報；mine 保留零夥伴作品，all 排除無合資格其他使用者的作品；作品到人員流程、字面搜尋、分頁重試、雙向封鎖及換帳號隔離符合以上規則。前端不能因缺少正式 API 而改連本機服務。

來源：[同坑與探索契約](/Users/frank/FlutterProjects/coscircle/docs/features/same-works.md)、[名片雷達](/Users/frank/FlutterProjects/coscircle/lib/features/profile/presentation/profile_work_radar.dart)、[尋找夥伴畫面](/Users/frank/FlutterProjects/coscircle/lib/features/social/presentation/partner_discovery_page.dart)、[探索狀態](/Users/frank/FlutterProjects/coscircle/lib/core/providers/partner_discovery_providers.dart)、[探索查詢](/Users/frank/FlutterProjects/coscircle/backend/src/partner-discovery.js)、[舊同坑查詢與路由註冊](/Users/frank/FlutterProjects/coscircle/backend/src/same-works.js)。2026-10-30 已部署正式 API 與 Web，專用 QA 正式 API 及 Android 模擬器路徑通過，範圍與限制見[驗證紀錄](/Users/frank/FlutterProjects/coscircle/docs/deployment/partner-discovery-2026-10-30.md)。原生 App 需更新才能顯示新介面。

### 6.12 LOC：現場地圖與位置分享

- LOC-01：App 現場頁選擇台北「今天」且自己已加入的 D 日，可切換今天多個活動；沒有有效場次顯示空狀態，不代表地圖壞掉。
- LOC-02：分享預設小圈圈、三十分鐘，可選關注者、活動參加者及十五、三十、六十分鐘。分享前顯示隱私確認。
- LOC-03：分享與更新要求 approved 活動、本人今天對應 D 日有預定。每活動每人只留最新位置，不保存移動路線；位置唯一鍵不含 dayIndex。
- LOC-04：GPS 在手動分享或更新時單次取得，定位服務關閉、拒絕與永久拒絕分別提示。沒有背景定位或持續移動上傳承諾。
- LOC-05：更新只改座標與更新時間，不延長原到期、不變更可見範圍。過期或不存在的分享不能靠更新復活，需重新明確分享。
- LOC-06：現場可見且 App 在前景時每三十秒重新讀取位置、集合點與認親；切走或離開前景停止，回前景立即刷新。這是讀取別人的資料，不是自動上傳自己的 GPS。
- LOC-07：篩選全部、我關注、圈友、戳友時保留本人；篩選不擴大服務端可見範圍。停止分享後刪除本人的該活動位置。
- LOC-08：緊急隱身先停止目前活動位置，再將預定改圈內；兩步不是單一交易，失敗可能部分完成，不等同全站位置一鍵隱藏。

讀取端界線：GET 位置查詢本身沒有「今天」或活動 approved 條件，依活動 ID、關係及有效期限取回，App 再依目前 D 日過濾。不可把分享與更新的日期資格當成所有 API 讀取保證。查詢亦接受 expiresAt 為空的相容資料，不能保證所有歷史列都有自動到期。

驗收條件：位置面板可完整操作；更新後到期時間及範圍不變；過期不能復活；停止後重新讀取不再出現；定位拒絕不假成功。目前 UI 分享受 AF03 阻塞，API 成功不得代替此驗收。

來源：[現場資格](/Users/frank/FlutterProjects/coscircle/lib/features/current_event/presentation/current_event_page.dart:55)、[前景輪詢](/Users/frank/FlutterProjects/coscircle/lib/features/current_event/presentation/current_event_page.dart:168)、[位置可見性](/Users/frank/FlutterProjects/coscircle/backend/src/location-queries.js:45)、[座標更新](/Users/frank/FlutterProjects/coscircle/backend/src/location-queries.js:88)。

### 6.13 MEET：小圈圈集合點

- MEET-01：在地圖長按建立草稿，可調整位置、所屬小圈圈、集合時間及描述，預設約三十分鐘後。
- MEET-02：建立及修改要求圈子成員資格；只有建立者可修改或取消。
- MEET-03：讀取只回今天、本人所屬小圈圈且未與建立者互相封鎖的集合點；UI 將集合時間已過十分鐘者排除，優先顯示最早有效集合。
- MEET-04：讀取失敗保留上次成功資料，不誤判全部取消。既有他人集合異動可產生本機通知，首次快照不重複通知。

驗收條件：非建立者無法修改、離圈後不能再讀該圈集合點、刷新失敗不顯示假取消。待確認 API 對座標範圍、未來時間及同日預定的完整驗證，不能把 UI 入口限制當成後端保證。

來源：[集合操作](/Users/frank/FlutterProjects/coscircle/lib/features/current_event/presentation/current_event_page.dart:998)、[集合 API](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:2109)、[快照規則](/Users/frank/FlutterProjects/coscircle/lib/core/models/meetup_point.dart:60)。

### 6.14 REC：認親訊號與導航

- REC-01：對他人發起認親，雙方須有今天同活動同 D 日預定，不能對自己，且不存在雙向封鎖。目標不必正在分享位置才具備後端邀請資格。
- REC-02：有效五分鐘。只有收件者可回覆未過期 pending，回覆為 accepted「快來」或 declined「當前不方便」。
- REC-03：相同日次及方向的有效待處理邀請不重複建立；被拒絕後冷卻十五分鐘，每小時最多三次。
- REC-04：列表只回本人參與、當天對應日次且未封鎖的訊號。過期 pending 顯示 expired；模型含 cancelled，但未確認使用者可主動取消的入口，不列為完成能力。
- REC-05：現有地圖操作在發起成功後即可開步行導航，不等待對方接受。這不表示對方已同意見面。

驗收條件：非收件者不能回覆；五分鐘後不可接受；跨日或跨活動不得誤顯示；拒絕冷卻及額度正確。通知是否送達另依平台驗收。

來源：[認親建立](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:2274)、[認親回覆](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:2328)、[狀態模型](/Users/frank/FlutterProjects/coscircle/lib/core/models/recognition_request.dart:1)。

### 6.15 SET：設定、通知與回饋

- SET-01：主題為活力亮色及夜間撞色，新安裝預設亮色，保留本機既有偏好。風格為圓潤卡片、鮮明撞色與插畫，準備度為輕量完成度回饋，不新增虛構積分或獎勵。
- SET-02：認親通知使用開關。原生服務就緒、系統授權與 token 同步後才具備通知條件；關閉移除本裝置 token。開關變化不等於背景推播已送達。
- SET-03：可重看教學、投稿活動、查看版本及登入方式、登出。診斷與管理入口限管理員顯示，服務端仍須自行授權。
- SET-04：意見回饋開啟外部 Google 表單，預設為既有填寫連結。空建置設定隱藏入口，不自動附加 user ID、Email、token 或裝置資料；不是站內客服聊天室。

驗收條件：主題重開保留；拒絕系統通知權限不顯示假啟用；一般帳號看不到管理入口；回饋連結正確且未附加機密。

來源：[設定頁](/Users/frank/FlutterProjects/coscircle/lib/features/settings/presentation/settings_page.dart:53)、[推播服務](/Users/frank/FlutterProjects/coscircle/lib/core/services/push_notification_service.dart:126)、[回饋規則](/Users/frank/FlutterProjects/coscircle/docs/deployment/feedback-form.md)。

### 6.16 SAFE：帳號刪除、檢舉與政策

本節為「已確認工作目錄實作、完整正式部署未完成」，不可當成目前正式服務可成功執行的承諾。政策內容是現有產品告知，不代表已經法律審閱或商店核准。

- SAFE-01：App 可閱讀條款與隱私政策，法律文件有公開頁實作及 App 內閱讀頁。
- SAFE-02：自行刪除需輸入 `DELETE`、勾選永久刪除，再以目前 Email 密碼或已綁定 LINE 身份重新驗證。錯誤身份不得刪除，最後一名有效管理員不可刪除。
- SAFE-03：成功刪除清除帳號、登入身份、預定、社交、位置及擁有的小圈圈與集合點，撤銷登入。已知歸屬照片走持久化清理與失敗重試；舊照片歸屬不明須人工核實，不保證所有歷史圖檔立即消失。
- SAFE-04：公開刪除網站實作允許 Email 再驗證操作；LINE-only 或無法登入者走營運核實申請。網站原始碼存在不代表已正式發布。
- SAFE-05：可檢舉使用者、單日預定或小圈圈，選原因並填選填補充，補充最多一千 Unicode 字元。不可檢舉自己或無權讀取內容，未結案或最近二十四小時同目標重送拒絕。
- SAFE-06：檢舉送出建立 pending，不自動封鎖或處罰。管理員可審核、駁回、結案及依權限停權或移除內容；需要核對目標未變、版本及附註。檢舉不能用於停權管理員。
- SAFE-07：檢舉證據最長保存九十天的處理邏輯已有實作；備份、歷史照片與系統紀錄的正式保存及刪除政策仍待營運確認。

驗收條件：錯誤密碼不刪資料；刪除後 token 無效；圖片清理失敗可重試；檢舉重複與審核衝突被拒絕；換帳號不得把原草稿提交為新帳號。檢舉 UI 的工作階段隔離仍需完成安全驗證。

來源：[帳號刪除](/Users/frank/FlutterProjects/coscircle/backend/src/account-deletion.js:210)、[檢舉服務](/Users/frank/FlutterProjects/coscircle/backend/src/content-reports.js:143)、[正式部署限制](/Users/frank/FlutterProjects/coscircle/docs/deployment/account-safety.md)。

### 6.17 ADMIN：管理後台與投稿審核

- ADMIN-01：提供管理儀表板、活動、使用者、投稿、同步與工作目錄中的檢舉管理。一般 App 有管理入口，另有獨立 Admin Web。
- ADMIN-02：管理 API 要求有效登入、active 帳號與 isAdmin；非管理員拒絕。沒有多層級管理角色設定。
- ADMIN-03：新增與編輯活動要求名稱、場地、日期，結束不得早於開始，審核狀態限三種。現有日期驗證不應被描述成完整曆法驗證，sourceType 也未嚴格限制五種列舉。
- ADMIN-04：投稿先進 pending，管理員可核准或拒絕。核准以交易建立 approved 活動並更新投稿；重複處理不重複建立。
- ADMIN-05：目前帳號管理程式可停權、恢復、授予或撤銷管理員與刪除使用者。自我操作與最後有效管理員有保護；涉及新版帳號安全的保護須連同正式部署確認，不由程式存在推論正式全數生效。
- ADMIN-06：檢舉管理屬 SAFE 待部署範圍，不能把管理頁可見視為正式審核 API 可用。

驗收條件：一般帳號直接打管理 API 被拒絕；投稿重複核准不新增活動；活動刪除與帳號處分有確認；最後有效管理員不被移除。

來源：[管理授權](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:2945)、[投稿審核](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:1158)、[後台畫面](/Users/frank/FlutterProjects/coscircle/lib/features/admin/presentation/admin_dashboard_page.dart:84)。

### 6.18 SYNC：多來源活動同步

| sourceType | 顯示名稱 | 資料取得方式 |
| --- | --- | --- |
| 1 | 同人誌中心 | 正式 GCP 透過 ZenRows 取得公開活動清單 HTML。 |
| 2 | 投稿活動 | 使用者投稿經管理員核准。 |
| 3 | 官方人員建立 | 管理員建立，不顯示成爬蟲來源。 |
| 4 | COSMOS 創作攝影展 | 目前固定 Oen 場次頁，不代表已能自動發現未來每一屆。 |
| 5 | acosta! | 台灣活動頁探索並解析場次。 |

- SYNC-01：來源請求只在正式 GCP VM 執行。同期同人誌 transport 使用 ZenRows，COSMOS 與 acosta 直接 HTTP；不使用本機爬取、APK 逆向、DataImpulse 或常駐本機瀏覽器後備。
- SYNC-02：每日成功一次的同步邏輯以 Asia/Taipei 日期計，十二點起檢查，服務重啟可補跑。失敗或部分失敗至少隔三十分鐘，最多三次嘗試；不是每天無條件只發一次 HTTP。
- SYNC-03：以跨程序鎖避免重疊，手動觸發回工作 ID，管理頁每兩秒讀進度。重按可沿用執行中或六十秒內結果。端點雖含 doujin 名稱，工作涵蓋三個爬取來源。
- SYNC-04：工作可為 running、success、partial、failure；逐來源分開顯示結果。顯示「有執行」不等於三個來源都取得新資料。
- SYNC-05：來源 HTML 完整性、解析筆數、日期及身份衝突驗證未過時保留舊資料。各來源獨立交易，單一來源失敗不回滾其他來源成功。
- SYNC-06：依來源 URL、來源鍵及相同日期下的名稱與場地相似度處理更新與跨來源去重。不同同人誌活動 ID 不因同場地同日期就合併。
- SYNC-07：跨來源去重目前保留既有主來源欄位，不保存完整多來源歸屬清單。不得宣稱同一活動可同時呈現所有原始來源。
- SYNC-08：一次清單缺少舊活動不自動下架；明確標示取消才依規則轉 rejected。管理頁來源比對讀上次成功快照，不是每次開頁都重新爬取。
- SYNC-09：活動詳情標示來源名稱及網址；同步數為處理筆數，不是新增筆數。ZenRows 額度與排程實際啟用狀態需由正式維運確認，文件不保證免費或無限額。

驗收條件：同一活動跨來源同步不重複建列；同日期同場地但不同活動保留獨立；來源失敗不清空舊資料；來源結果分開顯示；每日已成功不因重啟重跑。不得為驗收改用公用本機網路抓來源。

來源：[來源與去重](/Users/frank/FlutterProjects/coscircle/backend/scripts/scrape-events.js:453)、[每日工作](/Users/frank/FlutterProjects/coscircle/backend/src/event-sync-service.js:18)、[來源快照驗證](/Users/frank/FlutterProjects/coscircle/backend/scripts/event-snapshot.js:17)、[ZenRows 部署紀錄](/Users/frank/FlutterProjects/coscircle/docs/deployment/zenrows-crawler.md)。

## 7. 權限與隱私矩陣

下表描述程式可見性規則，不代表這些組合已全部完成實測。除匿名公開名片外，他人讀取仍受 active 及雙向封鎖檢查。

| 資料 | 本人 | 其他使用者的讀取條件 |
| --- | --- | --- |
| 公開名片 | 可讀與編輯。 | 可匿名讀公開碼；已登入封鎖者拒絕，但匿名持連結不套用個人封鎖。 |
| 帳號 Email、登入憑證 | 經帳號相關流程使用。 | 不出現在公開名片或同坑回應。 |
| public 預定 | 可讀，未過日可增改取消。 | 登入後可在活動詳情看，不要求已關注或同日參加。 |
| circle 預定 | 同上。 | 需要與作者有共同小圈圈；只是好友或單向關注不夠。 |
| public 位置 | 有效列可讀。 | 觀看者須有同活動、同 D 日預定，且位置未到期。 |
| followed 位置 | 同上。 | 觀看者關注分享者，且未到期；位置查詢本身不另外要求觀看者同日預定，App 現場入口仍限今天已加入。 |
| circle 位置 | 同上。 | 與分享者有共同小圈圈，且未到期；查詢與 App 入口限制須分開。 |
| 戳友介紹與認識快照 | 關係雙方可讀。 | 不因知道公開名片碼就能讀。 |
| 小圈圈集合點 | 符合圈子條件可讀，建立者可改。 | 本圈成員、今天及未與建立者互相封鎖，前端再排除超過時效者。 |
| 認親訊號 | 發送者與收件者在有效活動日期可讀。 | 無關第三人不可讀，只有收件者可回覆。 |
| 檢舉與證據 | 依檢舉及管理流程。 | 不公開給被檢舉者或其他使用者；屬待完整安全部署範圍。 |

封鎖會移除雙方關注與戳友，不會自動離圈。解除自己的封鎖不會解除對方封鎖，也不恢復被移除關係。已下載或對外分享的 PNG 不具備撤回能力，不能用後續隱私變更保證回收外部副本。

位置 GET 沒有額外限制活動為 approved 或今天；表中的同 D 日條件是 public 範圍與觀看者預定的日次配對，不等於只能讀今天。App 的今日場次入口及日次過濾是另一層，日期與活動狀態若需後端統一限制仍待產品決策。

來源：[位置可見性查詢](/Users/frank/FlutterProjects/coscircle/backend/src/location-queries.js:45)、[預定與封鎖](/Users/frank/FlutterProjects/coscircle/backend/src/server.js:1791)、[好友資料](/Users/frank/FlutterProjects/coscircle/backend/src/friendships.js:45)。

## 8. 資料規格摘要

| 實體 | 主要內容 | 關鍵識別或生命週期 |
| --- | --- | --- |
| 帳號 users | 暱稱、公開碼、個人資料、身份、可見性、OOBE 完成、active／suspended、管理員旗標。 | user ID 為各功能共用身份；個人身份不是帳號權限。 |
| 登入身份 user_auth_identities | Email 或外部 provider、provider subject、驗證資訊。 | 多種登入方式可指向同一 user；不按社群 Email 自動合併。 |
| 信箱操作 email_action_tokens | 用途、雜湊 token、identity、Email 快照、期限與消耗紀錄。 | 驗證與重設單次有效；不儲存原始 token。 |
| 作品 works、user_pit_works | 作品名稱及使用者深淺坑。 | 使用者與作品配對唯一。 |
| 活動 events | 來源鍵、類型、名稱、URL、圖片、日期、地點、費用、主辦、描述、審核狀態。 | 同活動主資料可有多個單日預定。 |
| 預定 event_bookings | user、event、dayIndex、身份、作品、角色、照片、互動、時間、狀態、備註。 | 活動＋使用者＋日次唯一。 |
| 關注 follows、封鎖 user_blocks | 來源與對象使用者。 | 紀錄有方向，封鎖讀取限制採雙向檢查。 |
| 戳友 friendships | 排序後雙方 user ID、收發者、狀態、介紹與活動日期快照。 | 每對使用者唯一，不以邀請次數新增多人關係。 |
| 圈子 circles、circle_members | 擁有者、名稱、說明、邀請碼及成員。 | 圈主刪除或解散會連帶影響成員與集合點。 |
| 位置 shared_locations | event、dayIndex、user、經緯度、範圍、更新與到期。 | 活動＋使用者唯一，只保留最新點，不是路線歷史。 |
| 集合與認親 | 圈子集合時間位置、雙方認親狀態與期限。 | 與活動關聯，各自有成員或雙方權限。 |
| 同步工作與快照 | 工作狀態、嘗試次數、日期、逐來源結果、最近成功內容。 | 成功匯入與快照一起提交，失敗不覆蓋成功快照。 |
| 法律、安全、清理 | 同意版本、檢舉審核、上傳歸屬、刪除清理佇列。 | 法律同意已有最小正式修補，其餘完整部署待完成。 |

本機保存登入 token、主題、通知及活動瀏覽偏好；不能據此推論有完整離線資料庫或離線發布佇列。個人資料與預定仍以 API 儲存結果為準。

來源：[資料表](/Users/frank/FlutterProjects/coscircle/backend/db/schema.sql:1)、[信箱資料服務](/Users/frank/FlutterProjects/coscircle/backend/src/email-account-service.js:26)。

## 9. 主要 API 契約索引

以下省略共同 `/api` 前綴。這是功能索引，不取代完整欄位定義或服務端授權。SAFE 類端點的存在指工作目錄，不能當成正式可用。

| 功能 | 主要端點 | 用途 |
| --- | --- | --- |
| AUTH | POST `/auth/register`、`/auth/login`、`/auth/social`、`/auth/logout` | 建立帳號與工作階段。 |
| Email | POST `/auth/forgot-password`、`/auth/verify-email`、`/auth/reset-password`；GET `/me/email-status`；POST `/me/email-verification` | 驗證及密碼復原。 |
| 名片 | GET／PUT `/me`；GET `/profiles/:publicCode`；POST `/uploads/image` | 個人資料、公開名片與圖片。 |
| 法律 | GET／POST `/me/legal` | 查詢目前版本同意狀態、明確同意。 |
| 活動與預定 | GET `/events`、`/events/:eventId/participants`、`/me/bookings`；POST `/events/:eventId/bookings`；DELETE `/events/:eventId/bookings/me?dayIndex=N` | 活動探索與單日出席。 |
| 作品 | GET／POST `/works` | 搜尋與建立作品。 |
| 關注與封鎖 | POST／DELETE `/users/:userId/follow`、`/users/:userId/block`；GET `/following`、`/blocked-users` | 社交方向與隱私限制。 |
| 戳友 | GET `/friends`；POST `/friend-invites/:userId`、`/friend-requests/:requestId/respond`；DELETE `/friends/:userId` | 邀請、接受、忽略與解除。 |
| 小圈圈 | GET／POST `/circles`；PUT／DELETE `/circles/:circleId`；POST `/circles/join`；DELETE `/circles/:circleId/members/me` | 圈子維護及入退圈。 |
| 尋找夥伴，正式已部署 | GET `/social/partner-works?scope=mine&q=&offset=0&limit=20`；GET `/social/partner-works/:workId/users?offset=0&limit=20` | 先列自己或全站可探索作品，再列作品夥伴；參數、欄位及錯誤見同坑與探索契約。 |
| 舊同坑相容端點 | GET `/social/same-works?offset=0&limit=20` | 保留按共同作品數排序的人員分頁，不作新入口的全站作品探索。 |
| 現場位置 | GET `/events/:eventId/locations`；PUT／DELETE `/events/:eventId/location` | 讀取、開始及停止分享；座標更新另由 repository 對應專用端點。 |
| 集合與認親 | `/events/:eventId/meetups`、`/events/:eventId/recognitions`、POST `/recognitions/:requestId/respond` | 集合點維護與認親回覆。 |
| 管理與同步 | `/admin/events`、`/admin/users`、`/admin/event-submissions`、POST `/admin/sync-doujin-events`、GET `/admin/event-sync-jobs/current` | 後台與背景同步工作。 |
| SAFE，待部署 | POST `/me/delete-account`、`/reports`；`/admin/reports` | 自行刪除與檢舉審核。 |

## 10. 平台、權限與品質要求

| 項目 | 現況與驗收界線 |
| --- | --- |
| Android | 套件 `com.coscircle.coscircle`，最低 API 24；9.0 模擬器實測不代表所有支援版本及 release build 已通過。 |
| iOS | 專案含相機、相簿、使用期間定位及 LINE callback 設定；最低版本設定 13.0，仍需完整原生建置與裝置驗收。 |
| Web | 提供使用者 App 及獨立管理入口；定位、分享、相機、推播與原生平台能力不同，不能直接套用 Android 驗收結果。 |
| 相機 | QR 掃描使用，需要平台授權；拒絕不得造成循環或自動建立關係。 |
| 定位 | 目前使用期間單次定位；Android 未宣告背景定位，不承諾背景持續追蹤。 |
| 通知 | Firebase Messaging 與本機通知為不同來源；須驗證授權、token、前背景狀態與重複提示。 |
| 外部連結 | 分享使用 Web 名片 URL；目前設定不足以宣稱 HTTPS Universal Links 或 Android App Links 已完整完成。 |
| 網路 | 一般 API connect／receive timeout 各十秒，錯誤提供重試與合適提示；網路不通不等同帳號無效。 |
| 可用性 | loading、empty、error 分開呈現；小螢幕、鍵盤、橫向及大字體不可使主要操作無法觸及。 |
| 動態效果 | 啟動及完成度動畫尊重減少動畫設定；不以大幅垂直位移干擾操作。 |
| 安全 | 正式建置依專案規則指定 HTTPS GCP API，不交付金鑰、密碼或管理憑證於文件與客戶端。程式另有不安全測試豁免旗標，不代表正式可用。 |
| 環境 | 除使用者明確切回測試環境外，後端、API、DB 使用正式 GCP；本文件不要求建立本機替代服務。 |

尚未設定明確效能 SLO、同時在線容量、可用率與資料恢復目標。不能把 UI 輪詢秒數寫成端到端同步延遲保證。

來源：[平台 Manifest](/Users/frank/FlutterProjects/coscircle/android/app/src/main/AndroidManifest.xml:1)、[iOS 用途設定](/Users/frank/FlutterProjects/coscircle/ios/Runner/Info.plist:57)、[API 客戶端](/Users/frank/FlutterProjects/coscircle/lib/core/api/api_client.dart:13)。

## 11. 驗收案例索引

下表為後續測試清單。標記的紀錄是截至基準日期的局部證據，不代表案例所有平台與例外均已跑完。

| 案例 | 關聯功能 | 操作與預期 | 現有證據狀態 |
| --- | --- | --- | --- |
| AC-01 | AUTH、ONB | 冷啟動先等待，已登入且 OOBE 完成直接回主頁。 | Android 重開有局部實測。 |
| AC-02 | AUTH | 新裝置登入同帳號不重跑 OOBE；舊 session 失效。 | 帳號完成與單 session 有程式依據，多裝置完整流程待測。 |
| AC-03 | AUTH | LINE 取消不註冊，明確綁定保留原 user ID，不自動合併 Email。 | 真實原生授權待測。 |
| AC-04 | AUTH | 信箱連結 GET 不驗證，明確送出才消耗；過期與重播拒絕。 | 有服務測試與部署紀錄，真實收信流程待驗收。 |
| AC-05 | AUTH | 密碼重設後舊登入與待用連結作廢，不自動登入。 | 程式與隔離測試依據，不操作真實帳號驗收。 |
| AC-06 | ONB | 未勾選不能繼續，成功後重開仍同意，錯誤版本拒絕。 | 法律 hotfix 已有正式 QA。 |
| AC-07 | PROF | 複選身份、暱稱及編輯儲存重開保留，QR 無溢出。 | 360dp Android 有局部實測。 |
| AC-08 | PROF | 8/9 變 9/9 恭喜一次並隱藏，已滿儲存不重播。 | 完整裝置情境待測。 |
| AC-09 | EVT、BKG | 三日只選 D2，其他日不被加入；日期篩選只出該日。 | API 分日實測及部分 UI 證據。 |
| AC-10 | BKG | 重存不重複，取消 D2 保留 D1，過去日唯讀。 | API 與舊活動 UI 有局部實測。 |
| AC-11 | BKG | 新增或修改上傳照片成功，重新讀取 URL 可載入。 | Android 修改預定與正式 API 已有一次成功。 |
| AC-12 | SHARE | 產出真實 PNG，長名字完整可辨識並能開分享。 | 分享選單已測，AF05 名字截斷未修。 |
| AC-13 | FOLLOW、FRIEND | 接受好友不自動關注，清單保留介紹與場次。 | 兩 QA 帳號 API 與 UI 有實測。 |
| AC-14 | FRIEND | 忽略不向邀請者洩漏，重送不重置，交叉邀請不自動同意。 | 程式與既有隔離測試依據，雙方 UI 情境待測。 |
| AC-15 | CIRCLE | 鍵盤開啟可建立，重複加入不增員，非圈主不能管理。 | 收鍵盤後建立與 API 入圈已測，AF04 未修。 |
| AC-16 | SAME | 名片雷達、兩個作品範圍、先作品後人員、計數、搜尋、分頁與封鎖排除符合 6.11。 | 10/30 正式 API QA 及 Android 模擬器探索至名片通過；搜尋、分頁、封鎖與工作階段有隔離回歸測試，實體手機與 iOS 未驗收。 |
| AC-17 | LOC | 分享面板可按確認、拒絕權限可恢復。 | AF03 阻塞，目前不能宣稱 UI 通過。 |
| AC-18 | LOC | 更新不延長到期，停止後其他人看不到，好友不能越權讀位置。 | 座標更新及停止 API 有實測，完整可見性組合待測。 |
| AC-19 | MEET、REC | 非建立者不能改集合，認親到期、冷卻、回覆權限正確。 | 完整裝置情境待驗收。 |
| AC-20 | SET | 主題重開保留，通知拒絕不假啟用，回饋不附憑證。 | 主題與開關局部實測，背景推播待測。 |
| AC-21 | ADMIN、SYNC | 非管理員拒絕；來源分開顯示、去重、錯誤保留舊資料。 | 有程式與歷史部署／隔離測試，正式排程現況未於本文重查。 |
| AC-22 | SAFE | 錯誤再驗證不刪帳號；成功撤銷關聯；檢舉隔離 session。 | 完整安全部署及驗收未完成。 |

## 12. 例外與錯誤狀態

| 情境 | 功能處理規格 |
| --- | --- |
| 登入恢復遇網路失敗 | 顯示重新連線，不把暫時失聯直接當作登出。 |
| 401／403 | 區分無效工作階段、停權或權限不足；舊回應不得干擾新的登入。 |
| 400／409 | 呈現輸入錯誤、版本、已結束、重複或狀態衝突，不無條件重送。 |
| 429 | 尊重冷卻與 Retry-After，不透過自動密集重試放大流量。 |
| 沒有活動、預定、同坑或今日場次 | 空狀態提供合理下一步，不顯示成 API 載入失敗。 |
| 來源 403 或挑戰頁 | 同步來源失敗，保留舊資料與錯誤紀錄；不能把安全畫面當正常 HTML 匯入。 |
| 選圖取消或檔案錯誤 | 不顯示假上傳成功，不覆寫原預定；圖片與資料儲存分段失敗需保留可恢復狀態。 |
| 定位或通知未授權 | 說明狀態、提供必要設定入口，不在未授權時宣稱分享或通知已啟用。 |
| 操作中登出、換帳號 | 原工作階段的寫入或錯誤不得套用到新帳號，尤其名片、預定、刪除與檢舉。 |

此處包含功能應滿足的錯誤處理條件。一般 404 文案、檢舉工作階段隔離等仍有未完成項目，不能把表格當成現有全數合格證明。

## 13. 版本狀態、已知問題與待確認事項

### 13.1 截至基準日期的狀態

| 項目 | 可確認範圍 | 不能推論的事項 |
| --- | --- | --- |
| 核心名片、活動、預定與關注戳友 | 10/30 專用 QA 有指定 Android 操作及正式 API 重讀紀錄。 | 不是所有裝置、身份、封鎖與失敗情境均已通過。 |
| Email 驗證及復原 | 10/13 正式啟用紀錄；舊 LINE 文件「尚未實作信箱驗證」敘述已過時。 | 不代表本次重新測過真實收信與有效連結。 |
| LINE | 原生登入與明確綁定有程式及部署設定。 | 真實授權、回 App 與 iOS 完整驗收仍未完成。 |
| 法律同意 | 10/30 最小 hotfix 與 QA 已確認 GET／POST 及明確同意。 | 未啟用新版全面社群寫入限制，舊客戶端不能因此視為全部受管制。 |
| 自行刪除、檢舉與審核 | 工作目錄有實作及測試。 | 完整正式部署、安全審核與端到端驗收未完成。 |
| 同坑雷達與尋找夥伴 | 10/30 正式 API、Web 已部署；專用 QA 與 Android 模擬器已確認兩分頁、夥伴清單、名片提示及高亮。 | 雙向封鎖等組合有隔離查詢測試；實體手機、iOS 與所有組合的裝置流程未驗收。 |
| 集合點、認親、背景推播 | 可由程式確認相關功能及規則。 | 10/30 QA 未完整覆蓋，不標成實機通過。 |
| 自動同步 | 有 GCP、ZenRows 部署文件及每日工作程式。 | 本文未連線確認當前環境旗標、額度與當日工作是否成功。 |
| 上架版本 | 目前有 debug 測試與相關驗證紀錄。 | 不等於商店簽章版、Android release 及 iOS 已可發布。 |

### 13.2 已記錄缺陷

| 編號 | 等級 | 問題及影響 | 關聯規格 |
| --- | --- | --- | --- |
| AF02 | 待依排程修正 | 一般 404 錯誤提示易被當成網路問題，可能誤導排查。 | 第 12 節。 |
| AF03 | P1 | 360dp 模擬器位置分享設定溢出 169px，確認鈕看不到且無法滑出，阻塞 UI 分享。 | LOC、AC-17。 |
| AF04 | P2 | 新增小圈圈鍵盤展開後溢出 13px，按鈕受遮。 | CIRCLE、AC-15。 |
| AF05 | P2 | 生成的分享 PNG 截斷長暱稱，影響辨認。 | SHARE、AC-12。 |

另有位置隱私提示被省略、選圖後顯示內部 cache 路徑等改善項目。本文件不修正這些缺陷。完整截圖與測試界線見 [10/30 續測報告](/Users/frank/FlutterProjects/coscircle/docs/product/android-qa-continuation-2026-10-30.md)。

### 13.3 待產品或營運確認

- 是否保留單一有效 session，或另設多裝置 session 管理；與 OOBE 完成狀態是不同需求。
- 是否提供 LINE-only 新增 Email、解除綁定及兩個既有帳號合併。
- 是否明確接受公開名片可匿名閱讀，封鎖不能撤回公開連結的現況。
- 是否將 OOBE 與法律檢查改為所有受保護路由一致適用，以及位置 GET 是否須統一限制今日、approved 活動與無期限舊列。
- 年齡、自介、網址及角色欄位需採何種正式輸入限制；不能把 DB 長度當作產品驗證。
- 同作品深坑與淺坑雙選的 UI 規則，以及活動「同好訊號」是否納入戳友計數。
- 同坑、集合點、好友忽略、可見性組合、背景通知及各平台原生功能的最終驗收人與裝置。
- COSMOS 未來屆次自動發現、來源歸屬歷史與舊錯誤合併資料是否需要專案修復。
- 完整帳號安全發布時間、檢舉營運人力、正式營運者資訊、備份及歷史照片保存清理期限。
- release 簽章、商店申報及隱私告知內容與實際資料流一致性。本文不是上架核准或法律意見。

## 14. 技術附錄與追溯索引

前端採 Flutter、Material 3、Riverpod、GoRouter、Dio，後端為 Node.js ESM、Express 與 MySQL；爬取解析使用 Node 與 Python transport。主要 API 與資料表規則以實際檔案為準，本文不記錄任何憑證值。

| 區域 | 主要來源 |
| --- | --- |
| 路由與主頁 | [App router](/Users/frank/FlutterProjects/coscircle/lib/core/router/app_router.dart:23)、[HomeShell](/Users/frank/FlutterProjects/coscircle/lib/features/home/presentation/home_shell_page.dart:23)。 |
| 登入與信箱 | [Auth repository](/Users/frank/FlutterProjects/coscircle/lib/core/repositories/auth_repository.dart:13)、[LINE service](/Users/frank/FlutterProjects/coscircle/lib/core/services/line_login_service.dart:7)、[信箱正式啟用](/Users/frank/FlutterProjects/coscircle/docs/deployment/email-account-flows.md)。 |
| 名片與引導 | [Profile page](/Users/frank/FlutterProjects/coscircle/lib/features/profile/presentation/profile_page.dart:113)、[Onboarding](/Users/frank/FlutterProjects/coscircle/lib/features/profile/presentation/onboarding_profile_page.dart:53)。 |
| 活動與分享 | [Event list](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/event_list_page.dart:169)、[Event detail](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/event_detail_page.dart:73)、[Booking share](/Users/frank/FlutterProjects/coscircle/lib/features/events/presentation/event_booking_share_page.dart:471)。 |
| 社交 | [Friendships](/Users/frank/FlutterProjects/coscircle/backend/src/friendships.js:24)、[Social page](/Users/frank/FlutterProjects/coscircle/lib/features/social/presentation/social_page.dart:43)、[Same works](/Users/frank/FlutterProjects/coscircle/backend/src/same-works.js:1)。 |
| 現場 | [Current event](/Users/frank/FlutterProjects/coscircle/lib/features/current_event/presentation/current_event_page.dart:55)、[Location queries](/Users/frank/FlutterProjects/coscircle/backend/src/location-queries.js:45)。 |
| 後台與同步 | [Dashboard](/Users/frank/FlutterProjects/coscircle/lib/features/admin/presentation/admin_dashboard_page.dart:84)、[Sync service](/Users/frank/FlutterProjects/coscircle/backend/src/event-sync-service.js:18)、[Source scraper](/Users/frank/FlutterProjects/coscircle/backend/scripts/scrape-events.js:28)。 |
| 法律與安全 | [Legal consent](/Users/frank/FlutterProjects/coscircle/backend/src/legal-consent.js:1)、[Deletion](/Users/frank/FlutterProjects/coscircle/backend/src/account-deletion.js:210)、[Reports](/Users/frank/FlutterProjects/coscircle/backend/src/content-reports.js:143)、[最小 hotfix 範圍](/Users/frank/FlutterProjects/coscircle/docs/deployment/legal-endpoint-hotfix.md)。 |
| 資料與平台 | [MySQL schema](/Users/frank/FlutterProjects/coscircle/backend/db/schema.sql:1)、[依賴](/Users/frank/FlutterProjects/coscircle/pubspec.yaml:21)、[Android Manifest](/Users/frank/FlutterProjects/coscircle/android/app/src/main/AndroidManifest.xml:1)。 |
| 視覺與驗收 | [撞色插畫 UI](/Users/frank/FlutterProjects/coscircle/docs/design/playful-ui-refresh.md)、[Android 完整測試紀錄](/Users/frank/FlutterProjects/coscircle/docs/product/android-full-qa-2026-10-30.md)、[Android 續測](/Users/frank/FlutterProjects/coscircle/docs/product/android-qa-continuation-2026-10-30.md)。 |

主要公開與功能路由包含 `/login`、`/forgot-password`、`/verify-email`、`/reset-password`、`/privacy`、`/terms`、`/onboarding`、`/events/:id`、`/current/:id`、`/profiles/:code`、`/scan-profile`、`/scan-circle`、`/delete-account`、`/admin`。部分設定、分享、審核頁使用頁面堆疊導覽，不能因沒有獨立 URL 就視為缺功能。

文件依三個唯讀盤點切片整合，並以獨立一致性檢查核對高風險規則。此次為文件工作，不重跑完整測試、不重新確認正式服務現況，也不宣告產品發布通過。

檢核注意事項：審查沿用同一模型，由獨立代理執行，不是跨模型或安全核准。已依審查更正信箱資料表名稱，補明匿名名片、路由檢查順序及位置讀取邊界。仍未確認的部署、平台驗收及產品決策保留於第 13 節。
