# CosCircle（Cos小圈圈）

CosCircle 是一個 Flutter Android / iOS 專案，用於大型 Cosplay / 同人活動中快速找人、分享位置、管理活動預訂與小圈圈社交。

## 架構

- Flutter 前端：MVVM 取向、Riverpod 狀態管理、feature-based 頁面資料夾。
- API：`backend/` Express REST API。
- Database：MySQL，schema 在 `backend/db/schema.sql`。
- 資料來源：台灣同人誌中心活動列表，匯入腳本在 `backend/scripts/scrape-events.js`。

## 前端啟動

```sh
flutter pub get
flutter run
```

實體 Android / iOS 手機與開發電腦連同一個 Wi-Fi 時，App 會預設連到：

```text
http://192.168.5.198:8080/api
```

如果電腦的 Wi-Fi IP 改變，請更新 `lib/core/api/api_client.dart` 裡的 `devLanBaseUrl`。

Android Emulator 連本機後端時可改用：

```sh
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api
```

Google Map 需要在 Android / iOS 原生設定 API key 後才能正常顯示地圖。

正式版建置時必須指定 HTTPS API：

```sh
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com/api
```

Release build 不會使用預設開發 IP，也不允許 `http://` API。

Android release 簽章請建立 `android/key.properties`，並以 Gradle property 指定地圖 key：

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/absolute/path/upload-keystore.jks
```

```sh
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.example.com/api \
  -PGOOGLE_MAPS_API_KEY=your_google_maps_key
```

完整上線前檢查請參考 `docs/deployment/production-checklist.md`。
GCP 免費額度 VM 部署請參考 `docs/deployment/gcp-free-tier-vm.md`。

## 後端啟動

```sh
cd backend
npm install
cp .env.example .env
npm run dev
```

Production 請以 `backend/.env.production.example` 為範本，並設定：

- `NODE_ENV=production`：不會自動建立開發 admin。
- `CORS_ORIGINS=https://your-admin.example.com,https://your-web.example.com`：限制瀏覽器來源。
- MySQL 帳號密碼請改成正式憑證，不要使用 `.env.example` 的示範值。

建立資料庫後依序執行：

```sh
mysql -u coscircle -p coscircle < db/schema.sql
node scripts/scrape-events.js --import
```

既有資料庫請依實際狀態補上尚未執行的 migration。隱私與位置保護功能需要：

```sh
mysql -u coscircle -p coscircle < db/migrate_privacy_controls.sql
```

完整 migration 清單與驗證 SQL 請看：

```sh
docs/deployment/production-checklist.md
```

同人誌中心爬蟲會在 API server 執行期間，每天中午 12:00（預設 `Asia/Taipei`）自動匯入一次。可用環境變數調整：

- `EVENT_SCRAPER_ENABLED=false`：停用每日自動爬蟲。
- `EVENT_SCRAPER_TIME_ZONE=Asia/Taipei`：指定每日 12:00 使用的時區。

也可以手動執行：

```sh
cd backend
npm run scrape:events -- --import
```
