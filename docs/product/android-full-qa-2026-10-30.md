# Android 登入後功能驗證

最新進度：AF01 已於 2026-10-30 以法律端點最小修補部署正式 GCP 並完成模擬器重測。下方保留初輪失敗紀錄，修復結果見文末；其餘完整功能尚未全面驗收。

## 結論

完整功能驗收受阻，不能宣告全部正常。新版 App 要求法律文件同意狀態，但正式 GCP 的 `GET /api/me/legal` 回傳 HTTP 404。模擬器登入成功後停在條款確認頁，主要功能無法進入。未移除或繞過同意檢查。確切原因可能是部署版本或路由設定，尚未查驗主機配置。

本輪使用者明確授權建立專用 QA 帳號與測試資料。實際僅建立一個 QA 帳號，未繼續建立預定、活動、小圈圈或互動邀請，以免在 App 無法操作時留下更多資料。未部署、執行 migration、刪除帳號或送出檢舉。實體手機及真實使用者資料未操作。

## 阻斷問題

### AF01：正式法律同意端點回傳 404，阻斷主要功能

- 優先級 P1。影響目前新版 App 登入後的主要功能入口。
- 使用受限測試產物中的 QA 帳號登入正式 GCP，帳號註冊 HTTP 201，`GET /api/me` HTTP 200，且回傳身分與 QA 帳號相符。
- 相同工作階段呼叫 `/api/me/legal` 得到 HTTP 404，回應為 HTML 而非預期 JSON。
- `/api/health`、`/api/events`、`/api/following`、`/api/circles` 均 HTTP 200。故不能把這次問題解釋成整體網路中斷。
- 模擬器登入後顯示「無法確認同意狀態，請檢查連線後重試。」。「同意並繼續」停用。
- 按「重新確認」後仍受阻。重開 App 能恢復登入狀態，但仍停在同一個錯誤。
- 原始狀態摘要位於 `/Users/frank/FlutterProjects/coscircle/build/qa-android-20261030/production-probe.json`。
- 畫面證據為同目錄的 `29-legal-blocker.png`、`30-legal-retry.png`、`33-restored-qa-session.png`。
- 相關程式為 `/Users/frank/FlutterProjects/coscircle/lib/core/repositories/legal_repository.dart`、`/Users/frank/FlutterProjects/coscircle/lib/features/safety/presentation/legal_acceptance_page.dart`。
- 修復方向為完成安全功能的既有待辦與審查，再協調部署對應 schema、API 及 App。不能僅為了測試停用法律同意門檻。

### AF02：404 被描述為連線問題

優先級 P2。AF01 的實際 404 被 UI 顯示為檢查網路的提示，使用者無法靠重試自行解決。建議區分一般網路失敗與服務端點不可用。此項僅記錄，未修改程式。

## 裝置與正式 API 覆蓋

| 功能 | 本輪實際結果 |
| --- | --- |
| 專用 QA 註冊 | 正式 API HTTP 201，建立一個帳號。沒有用模擬器完成註冊表單送出。 |
| Email 登入 | 在 Android 模擬器填入 QA 帳密後成功進入條款確認頁。密碼未輸出。 |
| 已登入狀態恢復 | 強制停止 App 後重開，恢復到條款頁。未做逐影格錄影，因此不宣稱完全沒有畫面閃爍。 |
| 條款失敗與重試 | 裝置確認失敗提示、停用勾選及繼續按鈕、重試仍失敗。 |
| 刪除帳號頁 | 能從條款頁開啟，顯示 QA 帳號、警告、密碼、DELETE 確認、未勾選確認框與固定底部停用按鈕。未填完整證明，也未送出刪除。證據為 `31-delete-page-entry.png`、`32-delete-empty-proof.png`。 |
| 登出 | 從條款頁按登出後回到登入頁。證據為 `34-qa-logout.png`。未額外直接驗證服務端 token 撤銷。 |
| 活動讀取 | 只驗證正式 API `/events` HTTP 200，當時共 95 筆。未進入 App 活動頁，不等同搜尋、月曆、日期篩選或詳情驗收。 |
| 關注與小圈圈清單 | 只驗證正式 API HTTP 200，QA 帳號為空清單。未驗證 App 操作及互動。 |
| OOBE、名片、QR | 受 AF01 阻擋。 |
| 預定、上傳圖片、分享圖 | 受 AF01 阻擋。 |
| 戳友、封鎖、小圈圈互動與可見性 | 受 AF01 阻擋。沒有對真實使用者發送通知。 |
| 現場、GPS、集合、認親、推播 | 受 AF01 阻擋。 |
| 設定、帳號綁定、管理員頁 | 受 AF01 阻擋。未提升 QA 帳號權限。 |
| LINE、真實驗證信、檢舉送出、帳號刪除 | 尚未執行。需另行安排實際授權、可收信測試地址及一次性測試資料。 |

裝置仍為前一輪的 Android 9、API 28、360dp 模擬器。安裝的是目前工作目錄的 debug APK，不是 release 驗收。

## 自動化檢查

以下是目前程式的隔離測試，不是上述受阻流程的正式端到端通過證明。

| 檢查 | 實際結果 |
| --- | --- |
| `flutter analyze --no-pub` | No issues found，退出碼 0。 |
| `flutter test --no-pub --reporter expanded` | 395 項全部通過，退出碼 0。 |
| `env -i PATH="$PATH" NODE_ENV=test node --test src/*.test.js`，工作目錄為 backend | 175 項通過，失敗 0、取消 0、跳過 0，退出碼 0。委派檢查後由主流程重跑確認。 |

後端測試使用記憶體 SQLite 與注入的假連線池、郵件、LINE、推播及檔案系統。Flutter 測試使用測試替身。未啟動本機正式服務或持久化測試資料庫。

三項檢查已再次執行並保存原始輸出。目錄為 `/Users/frank/FlutterProjects/coscircle/build/qa-android-20261030`，檔案為 `backend-tests.log`、`flutter-tests.log`、`flutter-analyze.log` 及記錄退出碼的 `verification-summary.json`。重跑不是新增的測試數量。

## 測試資料與後續

測試帳號的暱稱以「QA模擬器」開頭，Email 使用不可投遞的 `example.invalid` 網域，不屬於任何真實收件者。註冊可能觸發既有驗證信寄送嘗試，但未驗證郵件投遞。沒有建立其他測試活動或互動資料。此帳號仍保留，未刪除。

憑證位於 Git 忽略的 `/Users/frank/FlutterProjects/coscircle/build/qa-android-20261030/qa-account.private.json`，檔案權限為 600。不要提交或分享該檔案。檔內註冊時取得的 token 已經歷 App 登入與登出，不應當作目前有效 token。

修復 AF01 並經授權部署後，需重新登入並逐項完成上述受阻項目，不能用本輪 395 加 175 項測試數字宣稱產品已完成驗收。既有檢舉 UI 工作階段隔離與獨立安全審查待辦仍未在本輪解決。

## 紀錄檢核

獨立唯讀檢核代理指出原因敘述超出證據、測試執行證據指向報告本身，以及 QA 腳本重跑時的帳號建立敘述可能誤導。已將原因改為待查、補存原始測試輸出，並讓腳本只記錄當次實際建立的資料及另存每次結果。首輪原始 `production-probe.json` 保持原樣。

決策紀錄位於 `/Users/frank/FlutterProjects/coscircle/.audit/android-full-2026-10-30.tsv`。本次檢核沿用預設模型，並非跨模型審查，也不是產品安全審查通過。仍需注意正式 404 的確切原因及受阻流程未完成驗收。

## AF01 正式修復驗證

修復前已確認正式 release `20261028095204` 沒有法律同意模組、路由及資料表，原因為正式版尚未部署這部分功能。本次在精確正式版副本中只加入法律路由、模組、啟動時資料表檢查，並套用單一同意資料表。沒有部署未完成的刪除帳號、檢舉與社群寫入限制，也沒有修改 nginx、網站、設定或爬蟲。

- 新 API release 為 `/opt/coscircle/api/releases/legal-igJDhIwJ`，原版保留可回復。
- DB、照片與設定備份為 VM 上 root 專屬 `/var/backups/coscircle/legal-nWDT0Gd5`，目錄權限 700，gzip 完整性檢查通過，未下載備份內容。
- 修補包 SHA256 為 `3f8a12ac545583c51dbc8ec3f13e717d52002f1e0c8a29e0abbb24a1577a64aa`。
- 法律模組與最終部署分別經獨立檢查，僅對最小修補範圍通過。聚焦法律測試 12 項、修補測試 17 項、封裝與回復模擬測試 5 項全部通過。

| 正式操作 | 結果 |
| --- | --- |
| QA 登入後 GET `/api/me/legal` | 200、版本 `2026-10-28`、`accepted:false`、`Cache-Control: no-store`。 |
| POST `accepted:false` | 400，`invalid_legal_acceptance`。 |
| POST 錯誤版本 | 409，`legal_version_mismatch`。 |
| 錯誤 POST 後 GET | 仍為 false，沒有自動同意。 |
| 模擬器明確勾選並繼續 | 按鈕由停用變成可用，送出後進入 OOBE。 |
| OOBE 1 至 4 步 | 為 QA 帳號選取 Coser、攝影，按開始使用後進入活動主頁。未驗證全部選填欄位。 |
| 以目前模擬器 QA 工作階段 GET | 200、`accepted:true`、`no-store`，沒有藉由再次登入取代目前工作階段。 |
| App 停止後重開 | 直接回活動主頁，不再要求同意或 OOBE。 |
| 正式 health 與服務 | HTTPS 回傳 `{"ok":true,"name":"CosCircle API"}`，服務 active。 |

證據位於 `/Users/frank/FlutterProjects/coscircle/build/qa-android-20261030` 的 `legal-before-consent.json`、`legal-after-consent.json`、`38-hotfix-login-retry.png`、`39-explicit-consent-checked.png`、`40-consent-completed.png`、`44-main-after-consent.png`、`45-main-after-relaunch.png`。修補後的 error 級 Flutter 與 AndroidRuntime 紀錄未觀察到錯誤。

重測一度因自動輸入時焦點未穩定，Email 漏一字而登入失敗。比對欄位長度 39、預期 40 後重新輸入即成功，未列為 App 缺陷。

AF01 已解除。AF02 的一般 404 提示文字尚未修改。活動操作、預定、社交、圖片、GPS、推播與 LINE 的完整驗收仍待接續；不能因進入主頁就宣稱全功能正常。本次後端修補不需要重新安裝 App。

## 後續驗證紀錄

上述帳號與受阻項目描述屬當時快照。法律修復後已接續實測，新增專用 QA B、測試活動 627 與小圈圈 2。最新結果見 [Android 功能續測](android-qa-continuation-2026-10-30.md)。預定上傳、好友與關注已有裝置證據，另發現位置分享面板及小圈圈對話框跑版，完整驗收仍未通過。
