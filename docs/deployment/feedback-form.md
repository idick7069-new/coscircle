# 意見回饋表單

- 設定頁「活動與支援」以 `FEEDBACK_FORM_URL` 建置參數控制意見回饋入口。
- 使用 Google 表單的 HTTPS 填寫連結：`forms.gle/...` 或 `docs.google.com/forms/.../viewform`，不可使用編輯連結。
- 預設填寫連結為 https://forms.gle/WGFe57Y1AFW1LQda8，可透過建置參數覆蓋；明確設為空字串時不顯示入口。
- Android、iOS 與 Web 均透過外部瀏覽器開啟，支援 Google 登入與表單附件。
- 不會自動附加使用者 ID、Email、登入憑證或裝置資訊。

一般 Flutter 建置需加入 `--dart-define=FEEDBACK_FORM_URL="$FEEDBACK_FORM_URL"`。
使用 `deploy/gcp/deploy-vm.sh` 時設定同名環境變數，腳本會傳入使用者 Web App 建置。
手機 App 也需要帶入此參數重新建置，不會由後端自動更新連結。

部署前以未登入 Google 的瀏覽器確認表單已發布且目標使用者可填寫。不要測試送出正式回應，除非管理者允許。
