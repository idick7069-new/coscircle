# Web 原 PO 標示與官網動態介紹

日期：2026-11-25。Web App 與 Android 同為 1.0.1（10）。

## 內容

- Web 留言與回覆：貼文作者的名稱旁顯示圖示與「原 PO」，依貼文作者身分判斷，其他讀者亦看得到。
- 官網導覽新增第六步「把話題，接著聊下去」，介紹分享場次預定、文字照片貼文、同坑作品、按讚與留言回覆，以及公開／戳友／指定小圈圈的可見範圍。
- 官網使用明確標示的範例貼文與留言回覆，不讀取正式使用者內容。
- 官網示範角色統一稱為「希希」，動態介紹以按讚、留言與回覆為主。
- 保留原五個步驟、主題切換及現場地圖示意；手機六步驟以兩欄排列。新增樣式網址版本，避免舊樣式快取。

## 發布

- 官網發布：`/var/www/coscircle/releases/official-ZoVCYzmM`。
- Web 發布：`/var/www/coscircle/releases/user-web-6xfqJzCQ`。
- 官網文案精簡後的最終發布：`/var/www/coscircle/releases/official-Bgvspwtu`，保留上述 Web 版本。
- 前一版本保留，可用既有發布流程回復。
- 使用既有正式 GCP 主機 coscircle-free-vm、cos-circle；本輪只更新靜態網站與使用者 Web。

## 驗證

- Web release 建置通過，沿用正式 HTTPS API 與正式登入設定。
- 官網封裝測試通過，HTML 結構、六組 tab/panel 對應、唯一 ID、標籤關聯及本機圖片／樣式資源檢查通過；site.js 語法檢查通過。
- 部署前確認測試加入頁與法務頁內容與正式站一致。
- 原 PO Flutter 操作與排版測試已於本次程式修改時通過，包含其他讀者視角、作者留言／回覆及兩倍文字。此次沒有另做瀏覽器畫面操作驗證。
- 公開網址內容與版本核對結果存於忽略的 `build/private/author-badge-web-20261125/public-verification.json`。

入口：官網 https://coscircle.app/；Web https://coscircle.app/app/。
