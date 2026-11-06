# Android 模擬器免登入測試

本輪操作實際 Android App，不以元件測試代替裝置驗證。使用者指定先完成免登入測試，因此未建立帳號、輸入真實帳密或完成 LINE 授權。

## 測試環境

- 裝置為 `emulator-5554`，Android 9，API 28，1080 x 1920，480 dpi，邏輯寬度 360dp。
- 以目前未提交工作目錄建置 debug APK，啟用 LINE 功能旗標。
- API 設定為 `https://coscircle.app/api`。啟動紀錄確認相同網址，但本輪未登入，不代表已驗證受保護 API。
- APK 為 `/Users/frank/FlutterProjects/coscircle/build/app/outputs/flutter-apk/app-debug.apk`。
- APK SHA256 為 `69fb0afda59da5acae1c3cc6684734b18f7a67a3d6cbfd1fb5faeb01c88aee77`。
- 截圖位於 `/Users/frank/FlutterProjects/coscircle/build/qa-android-20261030`。
- 未操作實體手機、啟動本機後端、存取活動來源網站或部署 GCP。

## 實際結果

| 操作 | 結果與證據 |
| --- | --- |
| 首次啟動與重新啟動 | 能進入未登入畫面。`01-launch.png`、`25-relaunch.png`。未驗證已有登入憑證時是否閃出登入頁。 |
| 空欄位按登入 | 顯示 Email 與密碼檢查提示。`02-empty-login.png`。 |
| Email 鍵盤與下一步 | 可輸入文字，下一步能切換至密碼。密碼遮蔽。`03-login-keyboard.png`、`04-invalid-fields.png`。 |
| 格式錯誤與短密碼 | 再次按登入仍保留檢查提示，沒有進入主頁。`04-invalid-fields.png`。 |
| 切換註冊 | 顯示暱稱欄位及建立帳號按鈕。格式錯誤資料仍被擋下。未送出有效註冊。`07-register.png`、`08-register-invalid.png`。 |
| 忘記密碼 | 帶入登入頁輸入的 Email。格式錯誤時顯示欄位錯誤，未寄信。`05-forgot-password.png`、`06-forgot-invalid.png`。 |
| 隱私政策 | 未登入可開啟、閱讀版本及滑到底部。`10-privacy.png`、`12-privacy-footer.png`。 |
| 聯絡營運團隊 | 開啟外部瀏覽器並載入 CosCircle Google 意見表單。未填寫或送出。可返回政策頁。`14-contact-result.png`、`16-return-from-contact.png`。 |
| 服務條款 | 未登入可開啟並閱讀版本及內容。`17-terms.png`。未逐段驗證所有條款。 |
| 150% 字體 | 條款及已檢查的註冊欄位可閱讀，錯誤文字換行。`18-terms-font150.png`、`19-register-font150.png`。 |
| 200% 字體 | 表單、錯誤提示及底部按鈕仍完整，品牌標題出現不佳斷行。`21-launch-font200.png`、`22-register-font200.png`。 |
| 執行紀錄 | 本輪讀取的 Flutter 與 AndroidRuntime error 紀錄沒有錯誤。這不代表未測流程無錯誤。 |

## 待改善

| 編號 | 觀察與影響 | 重現與位置 |
| --- | --- | --- |
| EM01 | 未登入的登入表單顯示「已登錄」，容易被誤認為登入狀態。建議改為「已有帳號」或移除標章。 | 全新啟動，往下滑到登入卡片。`02-empty-login.png`。`/Users/frank/FlutterProjects/coscircle/lib/features/auth/presentation/login_page.dart` 的 `_LoginAccessCard`。 |
| EM02 | 360dp 小螢幕的首屏看不到登入欄位或 LINE 按鈕，需先捲動。這是操作體驗問題，並非無法登入。 | `01-launch.png`。同檔案 `_LoginStageHero` 位於表單之前。 |
| EM03 | 200% 字體將品牌拆成「CosCirc」與「le」，雖未看到溢位警示，辨識與版面仍不理想。 | 調整系統字體後重回頁首。`21-launch-font200.png`。同檔案 `_LoginStageHero`。 |
| EM04 | 現有管理員 integration smoke test 使用已不存在的 Google 登入、舊入口及舊導覽標籤，不能當作現行 App 的驗收依據。 | 程式檢查，並非本輪裝置執行結果。`/Users/frank/FlutterProjects/coscircle/integration_test/admin_smoke_test.dart`。 |

以上均僅記錄，未修改產品程式。

## 未驗證

LINE 按鈕顯示正常，但啟動授權流程被執行環境的安全審核阻擋，因使用者限定免登入測試。未嘗試繞過或以其他方式啟動。後續需另行授權才測試該流程。

尚未驗證成功登入、既有憑證恢復、OOBE、活動、預定、名片、關注、戳友、小圈圈、QR 掃描、位置、推播、分享、刪除帳號或檢舉。也未驗證離線、橫向、多版本 Android 或 release 簽章版本。

目前專案部署文件記載新版法律同意、刪除帳號與檢舉後端尚未部署。本輪沒有登入或查驗正式部署版本，因此不能用本輪結果確認前後端相容。

模擬器字體由測試用 150%、200% 恢復為 100%。App 最後停在未登入首頁。本輪沒有確認完整產品可上架。

全工作目錄的 `git diff --check` 回報既有 `backend/db/schema.sql` 第 291、312、320 行有尾端空白。本輪未修改該檔案，也未順手整理其他未提交變更。
