# App Store 正式上架準備與送審紀錄

CosCircle 1.0.1（10）已於 2026-11-26 上午 9:48（台灣時間）提交正式 App Review，當時確認為「等待審查」。商店資料與兩組截圖已完成，隱私申報已發布。維持手動發佈；通過審查不會自動上架。本文於 2026-11-27 整理，不代表重新查詢當天審查狀態。

## 已在 App Store Connect 完成

| 項目 | 結果 |
| --- | --- |
| App | CosCircle｜同坑認親・場次預定，Apple ID 6838630547 |
| 套件 | com.hikakineame.coscircle |
| 正式版本 | 1.0.1，選用 build 10 |
| 本地化 | 繁體中文，名稱、副標題、宣傳文字、描述與關鍵字已填入 |
| 描述內容 | 名片、預定、分享圖、動態牆、同坑雷達、戳友、小圈圈、現場與安全功能 |
| 分類 | 主要類別「社交」，次要留空 |
| 版權 | 2026 Wu CHENGKANG |
| 內容權利 | 使用者確認活動來源、圖示及希希素材均有使用權；已設定有第三方內容及必要權利 |
| 售價 | 免費；定價基準台灣 TWD 0.00 |
| 供應地區 | 僅台灣、香港、澳門；介面顯示 3 地「於 App 發佈時供應」，其他 172 地未供應 |
| 發佈方式 | 手動發佈此版本 |
| 審查帳號 | 沿用獨立 Apple 審查帳號，帳密已在私有審查欄位保存，不寫入本文件 |
| 聯絡資訊 | 沿用開發者已確認的姓名、電話與 Email，不新增聯絡人 |
| 審查備註 | 英文登入步驟、隔離資料說明、動態操作、權限與安全入口 |
| 隱私申報 | 18 項資料類型完成用途、身分關聯及不追蹤設定；依使用者明確確認已發布 |
| 年齡分級 | 新版全球 13+；OS 26 前全球 12+，各地可能依 Apple 規則不同 |

商店文案保存在 [app-store-metadata.zh-Hant.md](app-store-metadata.zh-Hant.md)。正式版本已送審，尚未執行公開發佈。

## 隱私申報依據

來源包括正式安裝包內六個 SDK bundle 的 PrivacyInfo.xcprivacy、後端 schema、公開隱私政策，以及以下第一方說明：

- [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Google Maps iOS privacy](https://developers.google.com/maps/documentation/ios-sdk/apple-privacy-policy)
- [Firebase iOS data collection](https://firebase.google.com/docs/ios/app-store-data-collection)

本機 SDK 證據：`output/app-store/2026-11-25/sdk-privacy-evidence.json`，不含任何憑證。

| 資料類型 | 用途 | 與身分關聯 | 依據 |
| --- | --- | --- | --- |
| 姓名 | App 功能 | 是 | CN／顯示名稱 |
| 電子郵件地址 | App 功能 | 是 | Email 與 Apple 登入、驗證信 |
| 其他使用者聯絡資訊 | App 功能 | 是 | 自填外部社群連結 |
| 精確位置 | App 功能 | 是 | 主動分享位置與集合 |
| 粗略位置 | App 功能、產品個人化 | 是 | 自填常跑／遠征地區、約略位置 |
| 聯絡人 | App 功能 | 是 | 關注、戳友與小圈圈社交圖譜；不代表讀取裝置通訊錄 |
| 電子郵件或訊息 | App 功能 | 是 | 戳友邀請介紹與認親互動訊息；不代表讀取信箱 |
| 照片或影片 | App 功能 | 是 | 頭像、名片、預定、貼文照片；目前未提供影片上傳 |
| 客戶支援 | App 功能 | 是 | 檢舉及意見回饋 |
| 其他使用者內容 | App 功能、產品個人化 | 是 | 自介、坑單、貼文、留言與作品標記 |
| 搜尋記錄 | App 功能 | 是 | 送至伺服器的搜尋請求與維運紀錄；未宣稱建立搜尋推薦分析 |
| 使用者識別碼 | App 功能、產品個人化、分析 | 是 | 帳號、LINE／Apple sub、同坑匹配、SDK manifest |
| 裝置識別碼 | App 功能、分析 | 是 | 推播 token、Google Maps manifest；不代表使用 IDFA |
| 產品互動 | App 功能、產品個人化、分析 | 是 | 追蹤／按讚／出席與 SDK manifest |
| 當機資料 | 分析 | 否 | Google Maps manifest |
| 效能資料 | 分析 | 否 | Google Maps manifest |
| 其他診斷資料 | App 功能、分析 | 是 | 後端錯誤紀錄及 Firebase manifest；以帳號關聯處理保守申報 |
| 其他資料類型 | App 功能、產品個人化、分析 | 是 | 年齡、性別與設定，以及 Google Maps／FCM manifest |

所有類型均回答不作追蹤用途；未申報廣告目的。SDK 的分析資料仍須申報，即使 App 未安裝 Firebase Analytics 或 Crashlytics。

## 年齡分級答案

具備使用者生成內容、社群媒體、傳訊互動及位置分享；沒有家長控制、Declared Age Range API 年齡確認、對未滿 13 歲停用社群媒體的技術控制、任意網頁瀏覽器或付費廣告。分級為 13+ 不代表程式已落實身分或年齡驗證。

考慮 Cosplay 與開放貼文可能出現的題材，以偶爾申報粗話／低俗幽默、恐怖、酒精／菸草／毒品提及、成人暗示、幻想暴力及道具武器。色情／裸露、露骨色情、現實暴力、露骨虐待、醫療、賭博、轉蛋、競賽及約會交往功能回答無。適用年齡 URL 為兒童安全專頁。

## 公開網址

- 官網：https://coscircle.app/
- 支援：https://forms.gle/WGFe57Y1AFW1LQda8
- 隱私：https://coscircle.app/privacy.html
- 資料權利：https://coscircle.app/privacy.html#contact
- 條款：https://coscircle.app/terms.html
- 兒童安全：https://coscircle.app/child-safety.html
- 刪除帳號：https://coscircle.app/delete-account.html

上述官網、支援表單及四個政策／帳號頁已從公開 HTTPS 逐一確認 HTTP 200。

## 原生截圖與建置驗證

已使用 Xcode 27.2 的 Device Hub 恢復 iPhone 18 Pro 與專用 13 吋 iPad 模擬器，安裝 1.0.1（10）並擷取實際 App 執行畫面。沒有用 Web 或 Android 畫面代替。

| 組別 | 尺寸 | 張數 | 儲存驗證 |
| --- | --- | --- | --- |
| 配備動態島的 iPhone，中型顯示器 | 1206 × 2622 | 6 | 2026-11-26 重新載入後仍顯示 6 張 |
| iPad 13 吋顯示器 | 2064 × 2752 | 6 | 2026-11-26 重新載入後仍顯示 6 張 |

兩組內容均為動態牆、個人名片、活動月曆、小圈圈、尋找夥伴與現場地圖。使用隔離審查示範資料，檢查無載入骨架、帳密或私人邀請碼，未開啟實際位置分享。

原始素材位於本機 `output/app-store/2026-11-25/{iphone,ipad}/01-feed.png` 至 `06-map.png`；每組另附尺寸／SHA-256 清單及縮圖總覽。產圖及 build/private 設定不納入 Git。原生選檔完成上傳，未開啟瀏覽器擴充功能的全域本機檔案權限。

模擬器未簽章建置曾遇 Keychain -34018；改用 Xcode 的 arm64、CODE_SIGNING_ALLOWED=YES、CODE_SIGN_IDENTITY=- 建置後可正常登入。此調整只用於模擬器，未修改已驗證的正式 IPA 或 archive。

## 正式 App Review 提交結果

Apple 的「新增以供審查」必填檢查已通過，提交內容為 iOS App 1.0.1（10）。依使用者指示完成「提交以供審查」，Apple 顯示「已提交 1 個項目」，審查詳情確認為「等待審查」。

- 提交時間：2026-11-26 上午 9:48，台灣時間。
- 提交 ID：`3ffdba57-873c-4910-8a71-457245ed6a7a`。
- [App Store Connect 審查詳情](https://appstoreconnect.apple.com/apps/6838630547/distribution/reviewsubmissions/details/3ffdba57-873c-4910-8a71-457245ed6a7a)。
- 發佈方式：手動發佈，通過審查後仍需另外操作。

必填檢查通過與送審成功，不代表 Apple 已核准功能或政策符合性。

## 審查資料工具

審查資料建立工具為 `tools/review/prepare-apple-review.mjs`，僅允許在正式 GCP VM 以 root 明確指定 `--prepare` 執行，使用既有受限環境設定。密碼與邀請碼於執行時隨機產生，保存在 VM 的 root-only 設定檔；錯誤不輸出資料庫內容、session 或密碼雜湊。

`tools/ios/show_apple_review_access.py` 僅在本人互動式終端機顯示主審查帳密，不包含寫死的憑證。審查用帳密不得放入公開商店文案或 Git。先前經授權建立的本機暫存帳密檔已刪除。

## 後續驗證項目

在 TestFlight 實機確認 Apple／LINE 真實授權、通知送達、相機／相簿及帳號刪除。模擬器已確認地圖圖磚與登入後主要頁面可顯示，但不能代替所有實機端到端操作。尚未完成的項目不應記為已通過；本次文件整理未執行這些操作。
