# 社區救生圈公網聊天室設定

社區救生圈的 Nuxt 提供原生 WebSocket relay `/ws/light` 和查碼 API `/api/lightmesh`。每個光網有一組存於 MySQL 的六位數字碼，前置零會保留。部署相同系統的其他光網，可在同一目錄登記各自的 relay。任一邊有一部手機接通兩邊後，預設公開房間即可雙向互傳。手機中斷互連後，該部手機會停止轉送。

## 在 aaPanel 部署

進入伺服器的 `lifebuoy/` 目錄，沿用原有 `.env` 的 `NUXT_DATABASE_URL`。以下假設站點使用 `lifebuoy.aieco.hk`，Node 監聽 `127.0.0.1:3002`。

```bash
npm ci --include=dev
npm run migrate
npm run lightmesh:register -- wss://lifebuoy.aieco.hk/ws/light
npm run build
node --env-file=.env .output/server/index.mjs
```

如已由 aaPanel 的 Node 專案管理程序，建置後在 aaPanel 重啟。登記指令會回傳 `code` 與 `relay`。相同的 relay URL 再執行會回傳原碼。備份正式資料庫時包含 `lightmesh_networks` 表。聊天訊息只經 WebSocket 轉送，資料庫保存連接碼與 relay 地址。

在現有 Nginx HTTPS `server` 區塊加入以下路徑，將埠號改成 Node 實際監聽值。原有 Nuxt HTTP 代理會處理 `/api/lightmesh/`。

```nginx
location = /ws/light {
    proxy_pass http://127.0.0.1:3002;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 3600s;
    proxy_buffering off;
}
```

執行 `nginx -t`，通過後從 aaPanel 重載。每個 relay 使用單一 Node 程序，因為廣播訂閱儲存在各程序自己的記憶體。

XAMPP 或 Apache 可在 HTTPS VirtualHost 啟用 `proxy`、`proxy_http`、`proxy_wstunnel`，把規則放在通用代理前。Node 仍需獨立啟動。

```apache
ProxyPass        "/ws/light" "ws://127.0.0.1:3002/ws/light"
ProxyPassReverse "/ws/light" "ws://127.0.0.1:3002/ws/light"
ProxyPass        "/api/lightmesh/" "http://127.0.0.1:3002/api/lightmesh/"
ProxyPassReverse "/api/lightmesh/" "http://127.0.0.1:3002/api/lightmesh/"
```

## 查碼與互連

```powershell
$directory = 'https://lifebuoy.aieco.hk/api/lightmesh'
$relay = 'wss://lifebuoy.aieco.hk/ws/light'
Invoke-RestMethod "$directory/health"
$registration = Invoke-RestMethod "$directory/networks?relay=$([Uri]::EscapeDataString($relay))"
Invoke-RestMethod "$directory/networks/$($registration.code)"
```

### 接通兩個既有 App

社區救生圈使用 `https://lifebuoy.aieco.hk/api/lightmesh`，本網絡連接碼是 `952678`。傳播光使用 `https://www.aieco.hk/api/lightmesh`，本網絡連接碼是 `582193`。兩個 App 各自會到自己的目錄查對方的碼。

在 aaPanel 的社區救生圈 `lifebuoy/` 目錄，使用下列指令將傳播光既有的碼匯入社區救生圈目錄：

```bash
npm run lightmesh:register -- wss://www.aieco.hk/ws/light --existing-code 582193
curl -fsS https://lifebuoy.aieco.hk/api/lightmesh/networks/582193
```

此指令沿用原有資料表。相同的碼與地址重跑會回傳原登記，遇到不同配對會報錯。查碼成功後，在社區救生圈輸入 `582193`，傳播光的手機加入線上公開房間。接入的手機保持在線，兩邊就可雙向收發。

若也要讓傳播光主動輸入 `952678`，在 `www.aieco.hk` 的 Nginx HTTPS 站點代理查碼到同一目錄，並讓 CDN 放行 `/api/lightmesh/`。例如兩個站點的 Node 在同一主機且社區救生圈使用埠 3002：

```nginx
location ^~ /api/lightmesh/ {
    proxy_pass http://127.0.0.1:3002;
    proxy_http_version 1.1;
    proxy_set_header Host lifebuoy.aieco.hk;
    proxy_cache off;
}
```

執行 `nginx -t` 並重載後，驗證 `https://www.aieco.hk/api/lightmesh/networks/952678` 回傳 HTTP 200。

手機開啟「光網聊天」並加入公開房間。按「連接另一個光網 APP」便可查看和複製本網絡的六位碼。對方輸入此碼即可接入，兩個光網必須登記在同一查碼目錄。用兩部手機分別從兩邊發送訊息，核對每則只收到一次。六位碼是公開網絡代號，請沿用 App 原有帳戶登入處理帳戶功能。

App 預設使用上述正式地址，會從目錄讀取本網絡的碼。部署到其他地址時，在 Flutter 建置傳入以下參數。目錄 URL 填到 `/api/lightmesh`，App 會加上 `/networks`。

```powershell
flutter build apk --release `
  --dart-define=LIFEBUOY_RELAY_URL=wss://YOUR_HOST/ws/light `
  --dart-define=AIECO_NETWORK_DIRECTORY_URL=https://YOUR_HOST/api/lightmesh
```

本機驗證可使用 `ws://127.0.0.1:3002/ws/light` 和 `http://127.0.0.1:3002/api/lightmesh`。從 Android 模擬器連主機時改用 `10.0.2.2`，並用 App 所用的完整 relay URL 登記。WebSocket 對外代理以 [Nitro 2 WebSocket 文件](https://v2.nitro.build/guide/websocket)和 [Nginx WebSocket 文件](https://nginx.org/en/docs/http/websocket.html)的設定為基礎。
