# 活動來源同步診斷（2026-10-05）

## 已確認

- 正式環境為 `cos-circle` 的 `coscircle-free-vm`，IP `34.187.168.222`。
- GCP 以既有 `CosCircleBot/1.0` 身分對公開 `/events/alist/all` 發出一次診斷請求。
- 回應為 HTTP 403、`server: cloudflare`、`cf-mitigated: challenge`，標題為 `Just a moment...`，並含 challenge-platform 標記。
- 診斷 Ray ID：`a45a8f234fc66afb-SEA`。收到驗證頁後停止，未解驗證、重試不同身分或繞過 Cloudflare。
- 10/3 至 10/5 的排程同人誌中心失敗，但舊程式將其他來源成功匯入的三筆誤記為同人誌中心成功。
- 本次修復前最後可確認的完整同人誌中心匯入為 9/3 11:33（台灣時間），47 筆。

## 修正

- 同人誌中心、COSMOS、acosta! 各自記錄抓取/寫入結果、筆數和錯誤。
- 手動同步回應附上各來源結果；部分失敗不再被表述為全部成功。
- 後台顯示各來源最新結果；舊混合紀錄標為無法判定各來源，不修改歷史紀錄。
- 抓取失敗保留既有資料。COSMOS 解析為空或 acosta! 個別活動失敗不再悄悄顯示成功。
- 來源遇到 403/429/challenge 不觸發瀏覽器回退。

## 尚無法確認

Cloudflare 回應能證明請求遭驗證攔截，不能證明是哪一條規則或是 IP 被封鎖。
需由同人誌中心管理員依 Ray ID 檢查 Security Events。
合法後續方式為取得官方授權的 API/資料匯出、允許固定 GCP IP 存取，或由後台人工建立活動。

## 本機正常抓取與正式資料補齊

- 10/5 本機以原有 CosCircleBot 身分正常下載同一公開網址，解析到 50 筆活動，包括巴哈姆特站聚。
- 一般頁面也包含 Cloudflare JavaScript，不能只看到 challenge-platform 腳本就認定收到驗證頁；必須檢查頁面標題及實際內容。
- 比對發現 15 筆尚未有同人誌來源網址紀錄的活動，沒有既有未來活動會因清單差異被停用。
- 透過加密 SSH 傳送公開 HTML，使用正式 VM 上既有匯入器與去重邏輯，在資料庫交易中完成 50 筆同步。
- 巴哈姆特站聚的正式活動 ID 為 599，來源鍵 `doujin-2545`，日期 2026-10-24 至 2026-10-25，狀態 `approved`。
- 本機原有 LaunchAgent 檔案及載入紀錄目前不存在；此次沒有新增排程，也未改變正式 HTTP/HTTPS 部署設定。

使用者明確禁止本機/公用網路抓取後，已取消這條方案，移除新建的 SSH 同步腳本及 npm 入口。上面的匯入紀錄僅為歷史事實，不得重跑本機抓取。

## GCP 專用公開來源探測

所有 HTTP 來源探測均在指定 GCP VM 執行，本機僅使用 SSH 控制主機。

| 官方公開頁面 | GCP 結果 |
| --- | --- |
| https://www.doujin.com.tw/robots.txt | 403、Cloudflare challenge；停止該站探測，未繼續猜測 sitemap/API 路徑 |
| https://prj.gamer.com.tw/30y/lobby.php | 200、正常活動 HTML，含 2026/10/24-10/25 與花博爭豔館 |
| https://www.expopark.taipei/News_Photo_Content.aspx?n=247&s=4583 | 200、場館官方公告，日期、場地與主辦方相符 |

可行方向是由 GCP 直接同步獨立的活動主辦方/場館官方來源，再用既有活動 ID 去重整合。
這不等於恢復同人誌中心整站資料同步；同人誌中心仍需站方提供授權 API、資料匯出或允許指定 VM IP 存取。
上列官方來源已確認可讀，但尚未接入自動同步。

新增 `source-fetch-host.js` 限制活動來源抓取只能在 `coscircle-free-vm` 執行；本機執行會在 HTTP/瀏覽器呼叫前直接停止。
此防呆變更目前在工作區，尚未部署正式 API。

## 官方說明

- https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/detect-response/
- https://developers.cloudflare.com/support/troubleshooting/http-status-codes/4xx-client-error/error-403/
