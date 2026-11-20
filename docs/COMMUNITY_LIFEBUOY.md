# 社區救生圈 v0.3 本機驗收

工作區為 `aieco_share`，Flutter 預設從 `lib/main.dart` 啟動。以下使用 PowerShell。資料庫使用獨立的原生 MySQL 8.4，XAMPP 的 MariaDB 及原有資料目錄可繼續運作。傳播光由相鄰的 `aieco_mesh` 專案獨立建置。

## 本機結果

- 帳號與訪客版已在 Android 模擬器驗收。訪客可開啟四個分頁，並在光網聊天室收到第二台測試 relay 的訊息。新帳戶可註冊、自動登入、登出及以密碼重新登入。MySQL migration 005 與八項整合測試通過。
- Android 的 `aieco.light.mesh` 與 `aieco.light.lifebuoy` 已在同一台驗收模擬器安裝。透過新 App 和兩個種子帳戶完成 30 分鐘服務。單方確認保留待確認狀態，帳本仍空白。雙方確認後各有一筆 −30／＋30 分錄，餘額皆為 30 分鐘。
- 原生 MySQL 8.4.13 成功套用四個 migration。Nuxt build 和七個整合測試通過，涵蓋並行確認、未使用首次回應後的重送、失敗回滾、餘額不足、交換保留競爭和評分可見性。
- Flutter 靜態分析通過。完整測試首跑 67 通過、1 失敗。原 App 的離線節點畫面測試單獨重跑通過。
- 兩個獨立 Dart relay 程序通過雙向、去重、非公開封包隔離以及名冊停用。Flutter 橋接測試另外覆蓋斷線重連。兩台實機的 LAN 斷網演練、其他光網 App 以及 iOS 仍待驗證。

## 原生 MySQL

下載 [MySQL Community Server 8.4 Windows ZIP](https://dev.mysql.com/downloads/mysql/8.4.html?os=3)，核對官方雜湊並解壓。設定 `$base` 為解壓後的絕對路徑。以下初始化僅需執行一次。驗收使用本機回環地址與獨立資料目錄，另開一個 PowerShell 視窗維持伺服器程序。

```powershell
$base = 'C:/local/mysql-8.4.13-winx64'
$data = 'C:/local/lifebuoy-mysql-data'
& "$base/bin/mysqld.exe" --no-defaults "--basedir=$base" "--datadir=$data" --initialize-insecure --console
& "$base/bin/mysqld.exe" --no-defaults "--basedir=$base" "--datadir=$data" --port=33484 --bind-address=127.0.0.1 --mysqlx=OFF --default-time-zone=+00:00 --console
```

另一個視窗執行下列指令。無密碼 root 僅用於此獨立、僅本機可連線的測試實例。實際試點應由營運環境提供專用帳號、權限及 TLS。API 的連線字串只透過私有環境變數提供。

```powershell
& "$base/bin/mysql.exe" --no-defaults -h 127.0.0.1 -P 33484 -u root -e "SELECT VERSION(); CREATE DATABASE IF NOT EXISTS lifebuoy_dev CHARACTER SET utf8mb4; CREATE DATABASE IF NOT EXISTS lifebuoy_test CHARACTER SET utf8mb4;"
Set-Location lifebuoy
npm ci
npm run build
$env:NUXT_DATABASE_URL = 'mysql://root@127.0.0.1:33484/lifebuoy_test'
npm run migrate
npm test
$env:NUXT_DATABASE_URL = 'mysql://root@127.0.0.1:33484/lifebuoy_dev'
npm run migrate
npm run seed:local
$env:NITRO_HOST = '127.0.0.1'
$env:NITRO_PORT = '3390'
node .output/server/index.mjs
```

Nuxt 4.6.4 建議使用 Node 24.15 以上的 24.x 或 Node 26。管理後台在 [127.0.0.1:3390](http://127.0.0.1:3390)，輸入測試種子所列的 `admin` 識別碼。重跑種子會重新簽發舊測試識別碼並維持帳務。測試資料庫會留下測試記錄。

App 可直接以訪客瀏覽互助、時間帳、交換和光網聊天。訪客看板顯示各區公開貼文與物品。刊登、交易及個人資料需要登入。點右上角帳號圖示，選「建立帳號」，填寫顯示名稱、使用者名稱與至少 12 個字元的密碼，並選擇香港十八區之一。註冊 API 要求 `community_id` 為所選區別，登入後的交易及看板按該區分隔。原有帳戶保留既有社區和歷史資料。新會員有 60 分鐘起始額度。密碼登入只保留在本次 App 執行期間，重開 App 後可重新登入。

## aaPanel 正式資料庫更新

先備份 `lifebuoy` 資料庫並暫停舊版後端。在 aaPanel 的終端進入部署的 `lifebuoy` 專案目錄，確認 `.env` 或環境變數中的 `NUXT_DATABASE_URL` 指向正式庫。資料庫支援 MySQL 8.0.16 以上的 8.0 系列、MySQL 8.4 或 MariaDB 10.4–11.x。遷移指令會先顯示連上的版本和庫名。

```bash
npm ci --include=dev
npm run migrate
npm run migrate:status
```

舊庫首次更新時，指令會校驗 `lifebuoy_migrations` 的紀錄，將已套用的版本登記到 `_prisma_migrations`，然後執行尚未套用的 `migration.sql`。空白庫使用同一套指令。狀態確認為最新後便可啟動 Nuxt。若舊庫曾中斷匯入，先修正報錯版本的資料表與遷移紀錄，再重試。

之後把資料庫更新放在 `lifebuoy/prisma/migrations/<版本>_<名稱>/migration.sql`，隨程式碼一起部署，再執行 `npm run migrate`。既有版本供 Prisma 核對歷史，結構或資料的後續調整應放進新版本。

## Flutter Android

App 預設使用 `https://lifebuoy.aieco.hk` 作為 Nuxt API 網址，並自動加上 `/api/v1/`。連接正式伺服器可直接執行 `flutter build apk --debug`。以下以本機 API 驗收，透過 `LIFEBUOY_API_URL` 覆寫預設網址。

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
flutter build apk --debug --no-pub --dart-define=LIFEBUOY_API_URL=http://127.0.0.1:3390
adb reverse tcp:3390 tcp:3390
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell pm list packages aieco.light
```

兩個 APK 的套件是 `aieco.light.mesh` 與 `aieco.light.lifebuoy`。使用兩個新註冊帳戶驗收登入和免費求助。若驗收 30 分鐘服務，使用已有至少 30 分鐘額度的專用測試帳戶作需求方。雙方同意時數後，只有一人確認完成時帳本仍空白。兩人確認後應出現 −30／＋30。實驗中可於送出後切斷網路，再回來更新或重試，入帳以 API 狀態為準。已登入時畫面保留上次回應與時間戳，刊登送出前寫入識別鍵及內容至本機，失敗後可重送原草稿；重開 App 後重新登入相同帳戶可取回草稿。

模擬器與 USB 偵錯裝置可用 `adb reverse`。正式簽署需為新 App 建立自己的發布設定。iOS 的 bundle ID 為 `aieco.light.lifebuoy`，圖示使用 `LifebuoyAppIcon`，仍需 macOS、Xcode 與相符的簽署資料驗證。

## 光網橋接與區域網路

在兩個終端分別啟動相容的測試 relay。

```powershell
dart run tool/aieco_light_relay.dart --loopback --port 47892
dart run tool/aieco_light_relay.dart --loopback --port 47893
```

以 `tool/lifebuoy_bridge.example.json` 為範本，將本機測試設定存到 Git 外。確認兩條 relay 與兩個房間映射均獲核准後，將頂層 `enabled` 設為 `true`，並執行 `dart run tool/lifebuoy_public_bridge.dart <roster.json>`。橋接每兩秒讀取設定，停用任一 relay 或全體會關閉對應連線；缺少或無法解析設定會停用橋接。配對碼僅由既有目錄查詢 relay 地址，核准與停用由橋接名冊控制。橋接只轉送相容的公開聊天即時封包。復線後從新訊息恢復，離線期間的訊息沒有保存保證。對接多個 relay 時，公開房間須有相同 `shared` 值；正式 App 名冊、管理者同意和各自行為驗收另行處理。

兩個 relay 客戶端各傳一則，對端應只看到一次。再測未核准房間、非聊天封包、斷線後復線、以及停用。上述行為也可執行 `flutter test test/lifebuoy_public_bridge_test.dart`。要讓新 App 連到核准 relay，建置時加上 `--dart-define=LIFEBUOY_RELAY_URL=wss://核准地址/ws/light`。兩台實機斷網演練需在同一個互通的 Wi-Fi 上安裝新 App，關閉外網與行動資料，從 App 列的聊天室選 LAN，雙向傳訊，復線後以時間銀行帳本核對重送。

本機 Android 驗收可用下列方式把訪客聊天室接到測試 relay A。

```powershell
flutter build apk --debug --no-pub --dart-define=LIFEBUOY_API_URL=http://127.0.0.1:3390 --dart-define=LIFEBUOY_RELAY_URL=ws://127.0.0.1:47892/ws/light
adb reverse tcp:3390 tcp:3390
adb reverse tcp:47892 tcp:47892
```

試點前需確認初始額度、帳戶下限及申訴時限。此原型採零透支、交換保留 48 小時（由參與人取消或管理員釋出逾期保留），管理後台採已簽發的成員識別碼。正式部署、驗證跨 App 名冊、備份還原、發布與上架另行安排。
