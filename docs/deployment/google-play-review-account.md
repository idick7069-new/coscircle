# Google Play 審查專用帳號（2026-11-19）

已在正式 GCP `cos-circle`／`coscircle-free-vm`／`us-west1-b` 建立並驗證審查專用普通帳號。這些是持續保留的審查資料，不是部署 QA 後會清除的臨時帳號；未授予管理員權限，未修改現有使用者，也未對真實帳號建立關注或發出邀請／通知。

## 帳號與密碼保管

- 主審查帳號：`google-play-review@coscircle.app`，user ID 28。
- 備用／刪除測試帳號：`google-play-review-backup@coscircle.app`，user ID 29。
- 示範 Coser／攝影：user IDs 30、31，只與本批示範帳號互動，不提供其密碼給審查人員。
- VM 密碼保管：`/etc/coscircle/google-play-review-accounts.json`，root-only 0600。
- 本機交付：`build/private/google-play-review-access.txt`，目錄 0700、檔案 0600，已由 `/build/` 排除 Git。
- 英文審查說明：`build/private/google-play-review-instructions.txt`。
- 帳密為 App 的 Email／密碼登入識別，不是 Gmail／LINE 帳號。沒有為這些 Email 配置收件信箱，未假造 email verified 狀態；普通 Email 登入不要求 OTP 或信箱驗證，已實測通過。
- 不在本文件、Git 或官網公開密碼。若更新審查密碼，也要同步 Play Console；測試刪除帳號優先用備用帳號，避免主審查帳號被刪後中斷審查。

## 示範資料

- 活動 ID 631：`[審查示範] Google Play Demo — 非真實活動`，期間 **2026-11-19 至 2026-12-18，台北時間**。這是標示清楚的 approved 示意活動，會列於活動清單；不代表真實活動或實體集合。
- 每個示範帳號各 30 筆逐日預定，預定可見範圍為小圈圈，頭像／服裝圖使用希希素材，未使用真實個人照片。
- 小圈圈 ID 5：`[審查示範] Google Play Demo Circle`，包含四個示範帳號；主審查帳號為圈主。
- 每個審查帳號各有一位已接受好友、一筆待確認戳友邀請與關注資料；附有示範自我介紹與場次資訊。
- 共同坑單使用既有作品「我英」「re0」，示範攝影有其中一個共同作品；未修改既有作品或真實使用者資料。
- 活動期間每天提供一個小圈圈可見的示意集合點（台北地圖參考點），文字明確標示非真實集合。沒有為審查人員開啟 GPS，也沒有偽造即時位置分享；審查者可以自行決定是否授予定位權限及分享位置。
- 活動期間後，帳密仍可登入並查看歷史預定；現場頁依正常活動日期規則啟用，若延後審查，需要另行補充新日期示範資料。本次未設定每日排程或永久覆蓋活動日期。

## 建立與驗證

- DB 備份：`/var/backups/coscircle/google-play-review-xrsHJ0zA/coscircle.sql.gz`，root-only。
- 建立工具：`tools/review/prepare-google-play-review.mjs`，只在 VM 使用受限 API env 執行，需 root 與明確 `--prepare`。密碼隨機產生並保存在 VM 受限檔案；既有同名 Email 若 public code 不符，拒絕修改。交易提交後保留資料；重跑不更換密碼或重置審查者操作。
- HTTPS 驗證工具：`tools/review/verify-google-play-review.py`；從 VM 安全讀取審查帳密，經 `https://coscircle.app/api` 驗證，不輸出 session token。
- 本機驗證紀錄：`build/private/google-play-review-verification.json`。

兩組帳號皆實際重複登入成功，返回相同 user ID；確認非管理員、OOBE 已完成、基本資料／身份／坑單存在、現行條款已完成初始化，登入方式僅 Email。驗證 30 筆預定、四人小圈圈、好友／待確認邀請、同坑名單、當日集合點及 `/admin/stats` 拒絕 403。

額外以備用帳號暫時離開示範小圈圈，確認活動參與者 API 只返回自己的預定，其他示範預定被隱藏；測試後已重新加入並保留示範資料。驗證 session 已登出，不會留下維護用登入 token。

本輪是資料建立與正式 HTTPS API 驗證，未登入 Google Play Console、未實際提交審查，亦未以這兩組帳號進行 Play 發送版本的 UI 操作；不以 API 驗證宣稱完整 Play 實機流程通過。

## Play Console 填寫

在「登入詳細資料」選「是」，新增主審查帳號詳細資訊，說明名稱填 `CosCircle review account`，Email／密碼填受限交付檔的 main 區段，其他操作說明貼入英文交付檔。

可再新增 `CosCircle backup / account deletion test`，使用 backup 區段帳密，讓審查人員用備用帳號測試刪除帳號。兩組帳號都不需要 LINE 授權；不能要求審查者自行註冊或提供其個人 LINE 帳號。
