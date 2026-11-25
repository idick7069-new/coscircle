# 使用規則勾選無法操作修正

目標版本：1.0.1（8）。日期：2026-11-24。

## 問題及原因

使用者在「我已閱讀並同意本版本使用條款及隱私政策」無法勾選。`LegalAcceptanceGate._bootstrap` 仍讀取 SharedPreferences 的 `auth_token`，再與 ApiClient 還原的憑證比對。安全儲存遷移完成後該舊欄位為空；Web 則使用 Cookie 工作階段，兩者都會被誤判為登入帳號已變更。Gate 因此進入失敗狀態、沒有原工作階段，Checkbox 的 onChanged 為 null。

舊測試預先放入舊偏好憑證，因此沒有覆蓋真實更新後的狀態。新增測試先證實：只使用安全儲存、含已還原快取的兩個案例皆會使勾選框停用。

## 修正

- 使用 `ApiClient.restoreSession()` 原子還原並取得工作階段，不再由使用規則頁讀取舊儲存欄位。
- 已還原的登入立即擷取工作階段；首次還原則確認版本變更確實來自原登入還原，避免等待期間登入另一個帳號後誤綁。
- 移除無呼叫者的 `AuthRepository.tokenKey`，舊欄位僅保留於遷移／清理的底層程式。
- 保留使用者自行勾選、送出及伺服器確認後才能進入內容的流程。
- 沒有修改法律文件版本或寫入任何使用者同意紀錄，正式後端不需變更。

## 驗證

重現與回歸入口：`flutter test test/legal_acceptance_test.dart`。

涵蓋安全儲存初次還原、已快取工作階段、模擬已還原 Web Cookie 工作階段、還原途中切換帳號、等待同意狀態只顯示 loading、明確勾選後 POST 同意，以及舊回應不得授權新帳號。

修正後使用規則／登入／安全儲存共 33 項聚焦測試通過；完整 Flutter 測試 466 項通過、1 項既有略過，靜態分析無問題。正式使用者與管理 Web 已發布至 `/var/www/coscircle/releases/social-feed-Fl3qN7zi`，公開網址的 JS 雜湊已核對一致。Android 正式簽章 APK 為 `build/releases/CosCircle-1.0.1-8.apk`。
