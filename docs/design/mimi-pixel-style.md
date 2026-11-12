# CosCircle 希希像素風

CosCircle 標誌以原先核可的 C 形剪影為來源，保留行事曆掛環、摺角、雙手交握與指縫的位置。標誌以 64×64 像素網格輸出為 128×128 透明素材，並套用薄荷綠、淡紫與奶油白。各平台圖示使用午夜藍底，尺寸足夠時以整數倍輸出，小尺寸採最近鄰縮放。

重建標誌與各平台圖示：

```sh
python3 tools/build_pixel_brand.py
flutter test --no-pub --dart-define=EXPORT_BRAND_ICONS=true test/export_brand_icons_test.dart
```

新版 App 採深色像素介面，主要角色是希希。前端沿用既有登入、活動、名片、社交、位置與分享流程，視覺由共用主題、元件及素材統一處理。本次不是後端部署，正式資料仍取自 GCP HTTPS API。

## 希希設定

希希（CC）的名字來自 CosCircle 的兩個 C。她是約 16 歲、會陪你一起出角的朋友，也是「你的馬內」：幫你打理場次準備、整理預定與活動資料，並在現場協助找路。她有粉色短髮、瀏海、兩枚髮夾、圓框眼鏡與藍灰色眼睛。她穿白襯衫、深藍背心與淺藍條紋蝴蝶結。互動語氣像熟悉的出角夥伴，親切、俐落，以當下需要的協助為主。

角色表現可愛、好奇、友善，服裝與情境適齡。她是陪伴使用者探索場次的吉祥物，不代替使用者的個人身份或真人照片。

## 視覺系統

| 項目 | 設定 |
| --- | --- |
| 背景 | 午夜藍 `#0B1020` |
| 面板 | `#151D32`、`#1D2943` |
| 邊框 | `#405071`，清楚的 2px 外框 |
| 主色 | 薄荷 `#6DE3CE` |
| 輔色 | 淡紫 `#B3A5FF`、奶油白 `#F4EEDA`、粉紅 `#F49BB5` |
| 形狀 | 0／2／4／6 邏輯像素方角，硬邊位移陰影 |
| 字型 | Fusion Pixel 12px proportional，繁體中文版本，缺字沿用平台 fallback |
| 圖示 | 常用導航與共用圖示使用低解析像素圖形，其他功能保留可辨識的標準符號 |
| 插圖 | 抽象化希希，所有 App 希希素材均為原生 64×64，nearest-neighbor 顯示，不做平滑插值 |

「午夜像素」使用午夜藍底、薄荷主色與淡紫輔色；「冷調微光」使用較亮冷藍底、淡紫主色與冰藍 `#A8D8FF` 輔色。主題預覽色票直接取自各自 ThemeData，切換時背景、按鈕與選取狀態一起換色。

另提供「白晝像素」：純白背景、淺灰面板、深藍灰文字、深青綠主色與紫色輔色。輸入框、按鈕、導覽列、對話框及載入畫面沿用同一組淺色語意色；現場地圖使用預設亮色樣式。

預設主題是「午夜像素」。既有安裝首次進入本視覺版本也改用深色；之後使用者選擇的「午夜像素／冷調微光／白晝像素」會保存於 `coscircle_pixel_theme_mode_v1`。真人照片、QRCode 白底與地圖資料保留其用途，不做破壞內容的像素化。

同好頁四個分頁維持等寬，切到「尋找夥伴」時仍保留頁首與統計卡。展開小圈圈時，邀請碼上方維持 16px 間距。

吉祥物只用在能說明狀態或動作的位置。同好主頁與空清單移除無功能的角色裝飾，保留各功能圖示、操作與提示。所有尺寸與場景最多呈現半身，包含大型介紹、登入等待、錯誤備用圖與動畫；不使用全身構圖。

OOBE 的三頁功能介紹依序使用整理資料、看地圖與半身打招呼素材，搭配希希的簡短說明；建檔頁以半身希希提示暱稱、複選身份及常跑地區，並顯示讀取／儲存狀態。角色提示放在可捲動內容中，底部的上一步與開始使用持續可操作。

## 場景與素材

| 場景 | 使用處 | 素材 |
| --- | --- | --- |
| 馬內整理資料 | 還原登入狀態、首次確認同意狀態的等待畫面 | [reading.gif](../../assets/mimi/cute-v1/reading.gif) |
| 整理活動資料 | 半身瀏覽平板，活動清單、詳情與活動圖片下載中 | [reading.gif](../../assets/mimi/cute-v1/reading.gif) |
| 看地圖找路 | 半身持地圖，現場資料載入中及無當前活動提示 | [map.gif](../../assets/mimi/cute-v1/map.gif) |
| 打招呼 | 所有顯示尺寸統一使用半身構圖 | [portrait.png](../../assets/mimi/cute-v1/portrait.png) |
| 灰色輪廓 | 未設定頭像、頭像資料無效或圖片讀取失敗 | [avatar-placeholder.png](../../assets/mimi/cute-v1/avatar-placeholder.png) |

希希的半身圖、灰色預設頭像、兩支 GIF 與兩張靜態備用圖均以 64×64 輸出。本版使用已確認的可愛大頭比例、亮眼與腮紅，粉色短髮、圓眼鏡與蝴蝶結是小尺寸下的主要辨識特徵。匯出採最近鄰縮放、最多 20 個不透明色（動畫共用 16 色調色盤）與二值透明度。

兩支 GIF 都是真正四格循環動畫，單次循環 1000ms，四格停留時間依序為 360、180、180、280ms。各自的 `*-still.png` 與 GIF 首格一致，用於停止動畫與重複縮圖。

所有圖片與動畫內禁止文字、字母、數字、浮水印與假文字。平板僅有色塊，地圖僅有路線與色點。載入狀態文字由圖片外的 Flutter 元件與語意標籤提供。

大型 loading 顯示一個主要角色動畫。活動圖片下載中的縮圖可共用 reading GIF；沒有圖片或下載失敗時改顯示靜態角色。圖片、動畫和頭像都從 App 本地資產讀取，不呼叫生成服務。

系統減少動態、輔助操作偏好、隱藏分頁或 App 離開前景時使用靜態圖。主分頁由 `TickerMode` 標示可見性。狀態仍以文字與語意標籤提供；動畫不控制網路請求、同意判斷或定位權限，也不刻意延長等待時間。

## 工程入口

- `lib/shared/widgets/mimi_mascot.dart` 提供 `MimiMascot`、`MimiLoading`、`MimiAvatar`，場景由 `MimiScene` 列舉。
- `lib/shared/widgets/pixel_icon.dart` 提供共用像素圖示。
- `lib/core/theme/app_theme.dart` 與 `lib/shared/widgets/cos_ui.dart` 提供顏色、字型、邊角及面板規則。
- `docs/design/assets/cc/cute-v1/*-64-source.png` 保存可愛版希希的生成來源，動畫場景為 2×2 逐格圖；舊版全身與火箭來源僅作歷史設計保存，不封裝至 App。原角色米米的來源保存在 `docs/design/assets/mimi/`。
- `tools/build_mimi_animation.py` 使用 Pillow 將來源匯出為 64×64 PNG 或 GIF 與首格 PNG，使用共用最多 16 色調色盤，驗證格數及無限循環設定。這是開發工具，App 執行時不需要 Python。
- 共用元件以 64px 解碼，顯示尺寸依所在版面調整。標準 loading 與預設主圖仍顯示 128 邏輯像素，相當於放大兩倍；所有尺寸均為半身構圖。

重新產生動畫的範例：

```sh
python3 tools/build_mimi_animation.py docs/design/assets/cc/cute-v1/reading-64-source.png reading
python3 tools/build_mimi_animation.py docs/design/assets/cc/cute-v1/map-64-source.png map
python3 tools/build_mimi_animation.py docs/design/assets/cc/cute-v1/portrait-64-source.png portrait
python3 tools/build_mimi_animation.py docs/design/assets/cc/cute-v1/avatar-placeholder-64-source.png avatar-placeholder
```

像素字型來自 [Fusion Pixel Font 2026.10.25](https://github.com/TakWolf/fusion-pixel-font/releases/tag/2026.10.25)，採 SIL Open Font License 1.1；授權副本為 [LICENSE-FusionPixel.txt](../../assets/fonts/LICENSE-FusionPixel.txt)，與字型一同封裝。

## 圖片生成紀錄

以使用者提供的角色圖作為外觀參考，使用內建 imagegen 工具重製希希。共用條件為粉色短髮、雙髮夾、圓框眼鏡、白襯衫、深藍背心、淺藍條紋蝴蝶結、透明背景及 64×64 像素構圖。舊火箭與全身主圖已停用；目前直接沿用已確認的半身素材，平板以點按呈現，地圖以視線和眨眼呈現。灰色頭像保留短髮及圓眼鏡輪廓。

可愛版由已核准的 64×64 揮手圖作為身份參考，使用內建 imagegen 工具分別製作四格平板整理、四格持地圖與灰色預設頭像。提示詞共用條件：大頭小身、粉色短髮、雙髮夾、圓眼鏡、腮紅、白襯衫、深藍背心及淺藍蝴蝶結；最多半身、透明背景、圖片內無任何文字。逐格圖以既有工具輸出原生 64×64 GIF 與首格 PNG。App 素材改用 `assets/mimi/cute-v1/`，官網改用 `assets/xixi-cute-v1/`，避免沿用舊素材的長期快取。

## 驗證範圍

`test/mimi_pixel_test.dart` 直接解碼兩支 GIF，確認每格 64×64、四格、無限循環與不同畫格，並確認四張 PNG 原生 64×64、透明度僅有 0／255；也檢查所有尺寸使用半身圖、動畫暫停、恢復、頭像失敗 fallback、短畫面、主題保存及還原期間切換主題。同好頁測試確認不再出現裝飾插圖，並維持四分頁比例與操作。

前版 256px 素材於 2026-11-06 執行完整 Flutter 測試及畫面輸出，共 433 項通過；`flutter analyze --no-pub` 無問題。來源與視覺均經獨立檢查。活動封面佔位角色原本被徽章遮住，已改成媒體區及獨立徽章列。

前版已將連正式 GCP HTTPS API 的 debug APK 覆蓋安裝至 Pixel 9a，保留原有資料並確認 App 啟動；實體手機畫面確認午夜藍底、像素字型與底部導航。另比對 APK 內兩支 GIF、灰色頭像及字型與專案檔案的 SHA-256，確認資產確實封裝。該次手機安裝不代表本版 128px 素材已安裝。

證據在 `build/pixel-mimi-20261106/`，頁面渲染在 `build/ui-preview/`。本輪未部署 GCP Web、未執行 iOS 或商店 release 簽章包驗收，也不代表既有完整 QA 報告中的其他問題已修復。

128px 版本於 2026-11-06 通過 74 項相關測試，涵蓋米米素材、動畫、登入等待、條款等待、共用 UI 及活動回歸；`flutter analyze --no-pub` 無問題。另檢視三個 loading 的實際 Flutter 渲染與全部逐格圖，確認圖片內無文字。已建置使用正式 GCP HTTPS API 的 debug APK，逐檔比對八個素材的 SHA-256，確認與來源一致；尚未進行本版手機安裝。驗證記錄與放大動畫預覽位於 `build/mimi-128/`。

64px 版本於 2026-11-06 完成素材替換與同好頁裝飾移除，全套 435 項 Flutter 測試通過，`flutter analyze --no-pub` 無問題。確認九個資產原生尺寸、最多 16 色與二值透明度；三支 GIF 都有四個不同畫格、1000ms 無限循環，靜態備用圖與首格一致。已檢視同好頁及三種 loading 的 Flutter 渲染、全部逐格圖，並比對新版正式 API debug APK 內九個資產的 SHA-256。分享圖回歸測試也修正底色定位方式，避免把畫布底色誤算為圓角標籤底色。此版本尚未安裝手機；原生地圖整頁不在 widget 渲染驗證範圍。驗證紀錄在 `build/mimi-64/`。
