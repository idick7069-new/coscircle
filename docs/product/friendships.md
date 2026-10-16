# 戳友

## 關係與操作

- 關注維持單向，不因戳友邀請或確認而新增／刪除。
- 掃描個人 QR 後，名片提供原有關注與獨立的戳友入口。
- 戳友邀請需要 1 至 200 字的簡短介紹，可選認識的場次及單日。
- 明確選定的當前活動日期才會從掃碼帶入；沒有可靠上下文時不猜場次。
- 收件者在同好頁「戳友」分頁或對方名片確認／忽略邀請。
- 確認後雙方成為戳友。原始介紹、活動名稱、日期、D1／D2／D3 為邀請快照，確認時間不會覆蓋認識日期。
- 清單標明介紹是自己或對方留下的；非活動場合可保留「未指定場次」。
- 已加入好友可解除，不影響關注與小圈圈。封鎖會移除雙向好友／邀請。

## 忽略與隱私

- 內部 `ignored` 不對發送者公開；清單與重送回應仍顯示等待確認，不發拒絕通知。
- 同一邀請重送不覆寫介紹、場次或重新進入收件匣。
- 雙方同時邀請不自動同意，也不建立重複關係，仍由原收件者明確確認。
- 忽略後收件者可以主動邀請原發送者，視為新的邀請。
- 只有關係雙方能讀到當時介紹，不附加到公開名片 API。
- 活動及現場加入戳友篩選；只有 `accepted` 計入。
- 原有出席、位置的圈內限制及同日參加規則維持不變。戳友不等於取得私人位置權限。
- 邀請／接受／封鎖以同一組使用者鎖排序保護；只允許收件者回覆，停權與互相封鎖檢查在交易內。

## API / DB

- `GET /api/friends`：自己已確認、收到、送出的邀請；不輸出忽略狀態。
- `POST /api/friend-invites/:userId`：`introduction`, 可選 `eventId` + `dayIndex`。
- `POST /api/friend-requests/:requestId/respond`：`action=accept|ignore`。
- `DELETE /api/friends/:userId`：解除已確認關係。
- 新表 `friendships`，每一對排序後的使用者 ID 唯一。
- `backend/db/migrate_friendships.sql` 是 additive migration，API 啟動時建立尚不存在的表。
- 活動清單增加 `hasFriends` / `friendDayIndexes`，現場位置增加 `isFriend`。

## 驗證與部署

2026-10-12 已備份並部署正式 GCP，Pixel 9a 已以保留資料方式更新 Android 測試版。

- Node：邀請狀態、無拒絕洩漏、重複／交叉邀請、收件者權限、封鎖、停權、單日與隱私 SQL。
- Flutter：邀請入口、必填介紹、D2 上下文、失敗重試、確認／忽略及窄螢幕長文。
- 正式 GCP 部署前先備份 DB；不得對正式使用者自動送邀請或接受好友來測試。
- Android 需要更新 App，才能顯示新入口及篩選；iOS 實機建置與授權驗證另行處理。

### 正式部署紀錄

- VM：`coscircle-free-vm`，`us-west1-b`，GCP project `cos-circle`。
- API 與 Web release：`20261012114258`。
- App：`https://34.187.168.222/app/`；API、App、Admin 的 HTTPS 檢查皆為 200。
- 備份：`/var/backups/coscircle/20261012T034210Z-friends-GWRGeb/coscircle.sql.gz`，已驗證壓縮檔完整性。
- 備份 SHA-256：`0a144256444522870a1f511848d9f141473204aceacb7469df86eefa1bca62e8`。
- 帳號、登入來源、關注、小圈圈成員及預定資料，部署前後 dump 校驗值一致。
- `friendships` 已建立；驗證時共 0 筆，沒有新增任何測試好友。
- GCP 以原有工作階段唯讀驗證好友清單、活動旗標、位置查詢；未登入、對自己邀請及無效回覆均被拒絕。
- GCP MySQL CTE fixtures 驗證單日好友旗標、封鎖及活動列去重，不更動正式資料。
- Android Pixel 9a 安裝成功、冷啟動正常；實機確認「同好 → 戳友」及三個清單區塊載入。
- 本次未操作真實使用者之邀請、確認或忽略；雙方實際互動仍由使用者自行執行。
- 部署後 API 與憑證續期 timer 為 active，npm audit 為 0 個漏洞。
