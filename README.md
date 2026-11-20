# 社區救生圈 Lifebuoy

<img src="assets/icons/lifebuoy-app-icon.png" alt="社區救生圈 App 圖示" width="112">

社區救生圈是面向香港十八區的街坊互助 App。居民可找支援、提供協助、用時間帳記錄互助時數、交換物品，以及在光網聊天室聯絡附近街坊。

[Nuxt 後端安裝](#本機安裝-nuxt-後端) · [Android 本機建置](#android-本機建置)

![香港舊區街坊互助插畫](assets/images/lifebuoy/community.webp)

## App 內功能

| 分頁 | 功能 |
| --- | --- |
| **社區互助** | 瀏覽「找支援」、「我能幫忙」及「免費求助」，按服務名稱、地區或發佈者搜尋。 |
| **時間帳** | 新會員有 60 分鐘起始額度。雙方確認服務完成後，協助者增加時數，受助者扣除時數。登入後可查看服務和收支明細。 |
| **交換** | 刊登物品、填寫想換的物品，提出交換並確認交收。 |
| **光網聊天** | 在互通的區域網絡加入 LAN 聊天，或連接已設定的光網公開房間。可搜尋訊息內容或發送者。 |

## 使用流程

1. 以訪客身份開啟 App，可瀏覽公開服務和交換物品。
2. 要刊登或參與交易，在右上角選「建立帳號」，填寫顯示名稱、使用者名稱和至少 12 個字元的密碼，並選擇香港十八區之一。
3. 登入後可在所屬社區發帖或配對。服務雙方先同意時數，完成後再各自確認，入帳結果可在「時間帳」查看。

光網聊天室使用 `LIFEBUOY_RELAY_URL` 指定線上 relay。區域網絡聊天可在互通的 LAN 上使用。橋接及 relay 設定見[光網聊天室驗收步驟](docs/COMMUNITY_LIFEBUOY.md#光網橋接與區域網路)。

## 專案結構

| 路徑 | 用途 |
| --- | --- |
| `lib/`、`android/`、`ios/` | Flutter 手機 App，入口為 `lib/main.dart`。 |
| `lifebuoy/` | Nuxt 4 後端，同時提供網頁管理後台和 `/api/v1/` REST API。App 透過 API 讀寫會員、互助服務、時間帳和交換資料。 |
| `lifebuoy/prisma/migrations/` | 建立及更新 MySQL／MariaDB 資料庫的 Prisma SQL 遷移。 |

## 本機安裝 Nuxt 後端

需要 Git、Node.js 24.15 以上的 24.x 版本及 npm。資料庫可使用原生 MySQL 8.0.16 起的 8.0 系列、MySQL 8.4，或 MariaDB 10.4–11.x。以下使用 PowerShell 和現有的本機資料庫服務。

1. 用 MySQL 用戶端或管理介面建立開發資料庫。

   ```sql
   CREATE DATABASE IF NOT EXISTS lifebuoy_dev CHARACTER SET utf8mb4;
   ```

2. 下載專案並安裝後端套件。

   ```powershell
   git clone https://github.com/brian0731/aieco_share.git
   Set-Location aieco_share/lifebuoy
   npm ci --include=dev
   ```

3. 在 `lifebuoy/.env` 設定資料庫連線。把帳號、密碼和埠號換成你的設定。如果密碼含有 `@`、`#` 或 `%` 等 URL 保留字元，請先做百分比編碼。`.env` 應保存在本機或伺服器。

   ```dotenv
   NUXT_DATABASE_URL="mysql://DB_USER:DB_PASSWORD@127.0.0.1:3306/lifebuoy_dev"
   ```

4. 套用 Prisma 遷移，確認出現 `Database schema is up to date!`，再啟動 Nuxt。

   ```powershell
   npm run migrate
   npm run migrate:status
   npm run dev -- --host 127.0.0.1 --port 3390
   ```

開啟 [本機管理後台](http://127.0.0.1:3390/) 或 [公開看板 API](http://127.0.0.1:3390/api/v1/board)。新建的資料庫在尚未刊登貼文或物品時會回傳空清單。

管理後台使用管理員登入識別碼。若本機用的是回環地址 `127.0.0.1` 上的 MySQL 8.4 和專用 `lifebuoy_dev`，可另開 PowerShell，在 `lifebuoy/` 執行以下指令，使用輸出中 `id` 為 `admin` 的 `token` 登入本機後台。重跑會重新簽發本機測試識別碼。

```powershell
node --env-file=.env scripts/seed.mjs
```

## aaPanel 正式部署

把專案部署到伺服器，在 aaPanel 終端進入部署後的 `lifebuoy/`。先備份既有資料庫，並設定私有 `.env` 的 `NUXT_DATABASE_URL` 指向正式庫（例如 `lifebuoy`）。

```bash
npm ci --include=dev
npm run migrate
npm run migrate:status
npm run build
```

既有庫使用 `npm run migrate` 時會先核對舊版 `lifebuoy_migrations` 紀錄，再套用尚未執行的版本。

在 aaPanel 的 Node.js 專案設定中，工作目錄設為 `lifebuoy/`，啟動命令設為 `node --env-file=.env .output/server/index.mjs`。可在 `.env` 設定 `NITRO_HOST=127.0.0.1` 和 `NITRO_PORT=3002`，並將網域的 HTTPS 反向代理指向相同埠號。

## Android 本機建置

先安裝 Flutter SDK 和 Android SDK，啟動 Android 模擬器或連接已啟用 USB 偵錯的手機。確認本機 Nuxt 已在 `3390` 啟動，再回到 `aieco_share/` 根目錄執行。

```powershell
flutter pub get
flutter build apk --debug --dart-define=LIFEBUOY_API_URL=http://127.0.0.1:3390
adb reverse tcp:3390 tcp:3390
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Android 套件 ID 為 `aieco.light.lifebuoy`。省略 `LIFEBUOY_API_URL` 時，App 預設連接 `https://lifebuoy.aieco.hk`。正式 APK 發布需使用社區救生圈的 Android 發布金鑰簽署。

## 文件

- [本機啟動、建置與驗收](docs/COMMUNITY_LIFEBUOY.md)
- [專案規格 v0.3](output/pdf/community-lifebuoy-project-brief.pdf)
- [傳播光 LightMesh](https://github.com/brian0731/aieco_mesh)
