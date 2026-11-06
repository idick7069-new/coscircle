# 同坑雷達與尋找夥伴發布紀錄

2026-10-30 已更新正式 [App Web](https://coscircle.app/app/) 與 API。功能入口為「同好 → 尋找夥伴」，提供「與我同坑」、「看看大家坑什麼」，點作品可查看夥伴及公開名片。名片的共同作品使用特別顏色與雷達圖示，並顯示共同作品提醒。

## 正式版本與備份

| 項目 | 實際值 |
| --- | --- |
| VM | `coscircle-free-vm`，`us-west1-b`，project `cos-circle` |
| 正式 API | `/opt/coscircle/api/releases/partner-XnNVruDQ` |
| 正式 Web | `/var/www/coscircle/releases/partner-ui-jxfctqMf` |
| 發布前 API | `/opt/coscircle/api/releases/legal-igJDhIwJ` |
| 發布前 Web | `/var/www/coscircle/releases/20261028095204` |
| 第一版探索 Web，保留作回復 | `/var/www/coscircle/releases/partner-m4JWqyIo` |
| DB、設定與初次發布證據 | `/var/backups/coscircle/partner-pAv2Coxg`，root-only |
| 清單版面修正證據 | `/var/backups/coscircle/partner-ui-MGyoo3RY`，root-only |

先完整備份正式 InnoDB 資料庫與服務設定，再複製實際運行版本。API 僅覆蓋 `src/same-works.js` 與 `src/partner-discovery.js`；Web 僅替換 `app/`，保留官網與管理後台。既有 server、爬蟲、環境設定、依賴與資料表不變，不執行 migration 或 npm 升級。

版面修正只複製上一版 Web、替換 `app/`，不重啟 API。進入探索時收起同好頁大標題與統計卡，切回其他分頁恢復，避免短螢幕只能看到被截斷的作品卡。

正式 release 使用 `API_BASE_URL=https://coscircle.app/api`、`PUBLIC_APP_URL=https://coscircle.app/app`、`ENABLE_LINE_LOGIN=true`、`ENABLE_ACCOUNT_SAFETY=false`。後者維持與本次部署前正式環境一致的功能範圍，不代表刪除帳號與檢舉後端已在本次上線。

## 發布檔核對

| 檔案 | SHA-256 |
| --- | --- |
| 初次 API 功能壓縮檔 | `086bbdcd82bf4f8e4dc68ecf8be75617a2aa47c498bbb1cbadb109054aae71fd` |
| 最終 Web 壓縮檔 | `0f929b6ab23a110c6706ee07d4f1141c36b9662d3ab7a753b0e48bde798867c7` |
| 最終 `main.dart.js` | `5316cffc85b3d02671c214f7dac8648db97c4a455aa2013bc8a1eb5029287d53` |

VM 透過本機 HTTPS nginx 取得的 Web 雜湊符合發布檔。另從公開 `https://coscircle.app/app/main.dart.js` 下載比對，與上述最終雜湊相同。正式 API health 通過，服務 active。

## 執行驗證

| 檢查 | 結果與範圍 |
| --- | --- |
| `flutter analyze --no-pub` | 最終程式無問題。 |
| 完整 Flutter 測試 | 415 項通過，涵蓋雷達及公開名片帳號切換隔離。 |
| 最後清單空間修正 | 另執行 `test/partner_discovery_test.dart`，12 項通過，包含 600px 高度、底部保留導覽的整合版面。 |
| 完整 backend `src/*.test.js` | 192 項通過；新探索與舊同坑集中測試 22 項通過。查詢測試使用記憶體測試資料，不啟動本機後端或持久 DB。 |
| 部署腳本測試 | 9 項通過，含 19 種切換與回復情境；Web 修正腳本另經獨立檢查、5 種壓縮檔案例及成功／4 種失敗回復模擬。 |
| 正式 MySQL | 切換前以唯讀 transaction 執行候選查詢，驗證與備份為同一 DB server，涵蓋 mine、all、字面搜尋與人員共同作品 join。 |
| 正式 QA API | 專用 user17、18，8 個驗證請求通過，另驗證匿名 401；兩部作品可找到 QA18，顯示兩部共同作品；無 Email／座標欄位，探索回應 `private, no-store`，非法 scope 400。 |
| Android 模擬器 | 最終 debug APK 已安裝 `emulator-5554`，保留 QA 登入；兩個探索分頁、作品到夥伴、開名片、兩部共同作品提醒、深淺坑黃色高亮與雷達圖示均有畫面證據。 |

完整 Flutter 測試後又修正清單空間，已針對受影響功能重跑 12 項測試與靜態檢查，未把它誤記為完整套件重跑。功能與部署均經獨立複查後發布。

正式 QA 僅調整既有專用測試帳號坑單，調整前保存受限備份。未新增真實使用者資料、未操作第三方活動來源、未向使用者發送訊息。雙向封鎖的組合排除由隔離查詢測試覆蓋，未用真實帳號作封鎖實驗。

## 操作與回復

初次發布工具為 `deploy/gcp/deploy-partner-discovery-on-vm.sh`；Web 版面修正工具為 `deploy/gcp/deploy-partner-discovery-web-on-vm.sh`。兩者釘住各自當時的 active release，不可當成未來發布的通用腳本重跑。

初次工具會在切換失敗時恢復 API 與 Web symlink、重啟服務，並核對舊 health、service active、舊 Web 實際內容及兩個 symlink。Web 專用工具失敗時恢復舊 Web，核對提供的內容雜湊。回復失敗明確輸出 `RECOVERY FAILED`，需檢查服務與 symlink。舊 release 與 root-only 備份均保留。

本輪不更新實體手機，不產生商店簽章包。已安裝舊原生 App 的使用者需要更新 App 才會看到新 UI；GCP Web 可直接使用新版。iOS、實體手機及全部社交組合的完整裝置驗收未執行。其他既有 QA 缺陷仍依原功能規格追蹤，不因本功能發布而視為修復。

本機證據位於 `build/partner-radar-20261030/`，包括發布日誌、QA JSON、測試輸出、最終 Web 雜湊及模擬器截圖。憑證與 QA 私密備份不寫入本文。
