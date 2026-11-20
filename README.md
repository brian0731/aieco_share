# 社區救生圈

社區互助 Flutter App，提供免費求助、時間銀行、物物交換及聊天室。Android 套件 ID 為 `aieco.light.lifebuoy`。

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

Flutter 正式版預設使用 `https://lifebuoy.aieco.hk`。本機 Android 測試及 API 網址覆寫方式見下方驗收文件。

- [本機啟動、建置與驗收](docs/COMMUNITY_LIFEBUOY.md)
- [專案規格 v0.3](output/pdf/community-lifebuoy-project-brief.pdf)
