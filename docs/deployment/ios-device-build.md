# iOS 實機建置

2026-11-09：iOS 27.2 模擬器啟動白屏的崩潰堆疊停在 `UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`。Runner 已在 `Info.plist` 宣告單一 UIKit scene，由目前 Flutter SDK 內建的 `FlutterSceneDelegate` 載入 Main storyboard。使用 Xcode 指定 Apple Silicon 模擬器與 `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` 完成 Debug 建置；通用模擬器打包遇到架構驗證錯誤時，可改用此方式。已覆蓋安裝至 iPhone 18 Pro／iOS 27.2 模擬器，實際確認登入頁渲染及正式 API URL。截圖位於 `build/ios-simulator-scene-fixed.png`。

2026-11-06 已使用 Xcode 27.2、CocoaPods 1.17.0 完成未簽章的 iOS release 實機編譯。產物為 `build/ios/iphoneos/Runner.app`，約 62.2MB，bundle ID 為 `com.coscircle.coscircle`；逐檔確認九個 64×64 米米素材與專案來源的 SHA-256 一致。建置記錄為 `build/ios-device-build.log`。

此產物尚未簽章，也尚未安裝至 iPhone。初次檢查沒有可用的 codesigning identity；實體裝置僅以 ECID 顯示，未出現在新版 Xcode 裝置清單。後續改用相容工具，已確認 iPhone 7／iOS 15.8.8 的 USB 連線及信任配對成功。使用者已選擇 Personal Team 並成功建立 Apple Development 憑證；目前卡在 Apple 開發裝置註冊與描述檔。

## 已完成的建置設定

- 目前 Firebase iOS 套件最低要求 iOS 15。Podfile、Runner 建置組態與 App.framework 最低版本統一為 15.0。
- Podfile 的 post-install 將低於 15.0 的 Pod target 提高到 15.0，保留套件較高的最低版本，符合目前 Xcode 的支援範圍。
- Debug／Release xcconfig 引用對應的 Pods 設定，工作區包含 Pods 專案，Podfile.lock 保存本次可編譯的相依版本。
- 原生外掛下載與編譯完成；Podfile 語法、plist 與 Xcode 專案格式檢查通過。

重建指令：

```sh
PATH="/opt/homebrew/bin:$PATH" FLUTTER_SUPPRESS_ANALYTICS=true \
  /Users/frank/FlutterProjects/flutter/bin/flutter build ios \
  --release --no-codesign --no-pub \
  --dart-define=API_BASE_URL=https://coscircle.app/api \
  --dart-define=PUBLIC_APP_URL=https://coscircle.app/app \
  --dart-define=ENABLE_LINE_LOGIN=true \
  --dart-define=ENABLE_ACCOUNT_SAFETY=false
```

## 安裝前需要完成

1. iPhone 正常開機、解鎖，以支援資料傳輸的線材連接 Mac。
2. 在 Finder 左側選 iPhone，按「信任」，再到 iPhone 的提示視窗點「信任」並輸入手機解鎖密碼。參考 [Apple 官方說明](https://support.apple.com/zh-tw/109054)。
3. 在 Xcode Settings 的 Accounts 登入 Apple ID，為 Runner 選擇實際的 Development Team，產生可用的開發憑證與裝置描述檔。帳密與驗證碼由使用者自行輸入。
4. 確認裝置出現在 Xcode 的可用裝置清單，再進行簽章建置、安裝與啟動檢查；若裝置要求開發者模式，依手機提示完成。

### iPhone 7 的裝置辨識

本次 `devicectl` 與 `xcdevice` 沒有正常列出 iPhone 7，但 Finder、USB 裝置樹與相容工具可讀取；不可僅憑新版裝置清單判定手機未信任。已安裝 `libimobiledevice` 1.4.0 與 `ios-deploy` 1.12.2，執行下列命令確認 iOS 15.8.8 及配對成功：

```sh
idevice_id -l
idevicepair validate
ideviceinfo -k ProductVersion
ios-deploy --detect --timeout 5
```

`ios-deploy` 適用 iOS 17 以前的裝置，仍需要合法的開發簽章；參考 [工具官方說明](https://github.com/ios-control/ios-deploy)。完成簽章後，使用指定手機的 UDID 安裝，保留既有資料：

```sh
ios-deploy --id <UDID> --no-wifi --bundle build/ios/iphoneos/Runner.app
```

初次 `security find-identity -v -p codesigning` 為零個有效簽章，Runner 沒有 `DEVELOPMENT_TEAM`。使用者完成 Team 設定後，已確認一個有效 Apple Development 憑證。再次以 `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` 建置，指定 iPhone UDID 時 Xcode 回報找不到目的地；改用 generic iOS 目的地則 Apple 回報 Team 沒有可用裝置，無法產生 `com.coscircle.coscircle` 的開發描述檔。

### Xcode 與裝置版本限制

依 [Apple 官方相容表](https://developer.apple.com/xcode/system-requirements/)，Xcode 27.2 支援建置最低 iOS 15 的 App，但直接裝置支援為 iOS 17 以上。Xcode 26.6 支援 iOS 15 裝置，官方支援的主機範圍則為 macOS 26.2–26.x；本機為 macOS 27.2，因此不能將安裝舊 Xcode 描述為此主機的官方支援解法。

使用者使用免費 Personal Team。Apple 官方允許用此帳號在自己的裝置測試（[帳號說明](https://developer.apple.com/help/account/basics/about-your-developer-account)），此案例不應將付費開發者資格描述為必要條件。可支援的下一步是使用 iOS 17 以上手機完成目前 Xcode 的裝置註冊，或在支援 Xcode 26.x 的 macOS 環境替 iPhone 7 完成免費簽章流程。目前未下載其他 Xcode、未修改系統版本，也未安裝未簽章 App。

目前只驗證編譯與資產封裝，尚未驗證 iOS 實機登入、LINE 授權、地圖、推播或權限操作。既有 `DefaultFirebaseOptions` 沒有 iOS 設定，AppDelegate 也尚未提供 Google Maps iOS API key；成功編譯不代表這兩項 iOS 原生服務已可使用。此輪沒有部署後端或變更正式資料庫。

## 待使用者選擇的 AltServer 替代流程

使用者目前只有 iPhone 7。已將成功編譯的未簽章 App 封裝為 `build/ios/ipa/CosCircle-1.0.0-unsigned.ipa`（23,923,273 bytes），確認 `Payload/Runner.app/Runner` 存在，且九個米米素材與來源 SHA-256 相同。這個 IPA 尚不能直接安裝，仍需簽章。

[AltServer 官方版本紀錄](https://faq.altstore.io/release-notes/altserver) 說明可直接側載 IPA，支援 iOS 9.3 以上，無需先安裝 AltStore；免費側載 App 每七天需重新安裝／更新簽章。使用者可在 Mac 選單列按住 Option 點 AltServer 圖示，選擇 Sideload .ipa。其 [macOS 安裝說明](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos) 要求 macOS 11 以上，並由使用者在工具內登入 Apple 帳號。

目前只完成 IPA 準備與官方流程查核，尚未下載、安裝或啟動 AltServer，也未確認 macOS 27 實際相容性。因為此替代流程會讓使用者在第三方工具內進行 Apple 帳號驗證，已詢問使用者是否採用；不得將此流程記錄為已安裝成功。帳密與驗證碼由使用者本人輸入。
