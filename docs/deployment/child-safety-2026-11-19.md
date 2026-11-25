# 兒童安全政策與檢舉流程驗證

日期：2026-11-19。環境：正式 GCP project `cos-circle`，VM `coscircle-free-vm`，zone `us-west1-b`；account `idick7069@gmail.com`。

## 公開網址與 Play Console

- 安全標準網址：https://coscircle.app/child-safety.html
- 指定安全窗口：CosCircle 營運團隊／兒童安全負責人，idick7069@gmail.com。
- Play Console 可選開發人員帳號的聯絡 Email（需持續有人查收），兩項聲明對應 App 內檢舉及人工依法通報流程；營運者須持續執行。

政策含完整商店名稱、未滿 18 歲定義、禁止 CSAE／CSAM／誘騙／勒索、三種 App 檢舉路徑、無法登入時的 Email 管道、人工審核及移除、依法向地區主管機關通報、安全窗口與日期。不需登入或 JavaScript，並由隱私、使用條款及刪除帳號頁導覽連入。

現有 App 沒有獨立兒童安全原因；政策以現行「色情或不當裸露」及「其他」搭配「兒童安全」補充文字為實際操作指引。未新增原因 enum、DB 欄位、API 版本或 App 版本，因此這次不用重建 AAB。不得宣稱自動偵測、全天候監看或自動向主管機關通報。

## 正式驗證

`tools/review/verify-child-safety-on-vm.mjs --run-production-qa` 透過正式 API 驗證，只建立本輪一次性 reporter、target、admin 及純文字測試活動／小圈圈／預定。通過：

- 未登入檢舉 401、非管理員讀後台 403。
- 使用者、預定、小圈圈檢舉 201，重複檢舉 409。
- 後台可讀到補充文字與相關快照。
- 待處理 → 審核中 → 結案，保留兩筆審核歷史。
- 舊版本審核 409，不能覆蓋新狀態。
- 實際移除本輪預定與小圈圈，停權本輪帳號並撤銷 session；舊 token 401。
- finally 清理本輪檢舉、活動、小圈圈與帳號；未操作真實使用者內容，未向任何外部機關送出測試通報。

本機 `node --test backend/src/content-reports.test.js`：28 通過。
`flutter test test/reporting_test.dart`：9 通過，含必填驗證、防重送、錯誤處理與管理員破壞性操作的二次確認。
官網真正打包流程的 `official-site-packaging.test.py` 通過，包含新政策的根目錄與 official 副本，未呼叫正式部署 transport。相關 shell 語法檢查及差異空白檢查通過。

## 部署

沿用法律頁專用原子部署與失敗復原。正式部署前保存舊版與 Nginx 設定；新政策使用精確 Nginx 路由，缺檔 404，不回傳官網首頁，Cache-Control no-cache。

- 新 web release：`/var/www/coscircle/releases/public-legal-wA6NIi2H`。
- 前 web release：`/var/www/coscircle/releases/public-legal-Oc7a7CJd`。
- 設定備份：`/var/backups/coscircle/public-legal-NzWq4mSR`。
- `nginx -t` 通過，逐檔來源／origin HTTP 內容比對通過。
- 官網首頁、App 與後台 main.dart.js 位元組未變，API release 未切換，API health 正常。

公開真實 Chrome 驗證 `tools/review/verify-child-safety-page.mjs` 通過：手機 390×844、桌面 1280×900，禁用網頁 JavaScript，不登入即可讀取；200／正確 HTML MIME／標題／完整 HTML SHA-256 一致；CSS、圖片與版面無水平 overflow；三個既有法律頁連結及來源 HTML、CSS、刪除頁 JS 逐一比對通過。畫面截圖與報告位於 `build/child-safety-20261119/`。

## 人工營運責任

詳見 `docs/operations/child-safety-response.md`。窗口需持續查閱信箱、表單、後台佇列，優先分流兒少安全事件並完成合法通報／必要記錄。停權不會自動移除全部頭像、上傳檔案或快取；需要維運者核對並另行清除。既有檢舉證據 90 天到期／帳號刪除會清除，不能當成永久法律保全。測試只能驗證系統處理，不代表任何真實事件已被審核或通報。
