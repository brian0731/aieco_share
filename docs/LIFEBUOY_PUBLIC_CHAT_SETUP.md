# 社區救生圈公網聊天室設定

社區救生圈和傳播光各自連到自己的 WebSocket relay。兩個 App 使用相同的六位連接碼目錄。一部手機接通兩邊後，兩個 relay 上的用戶就能互傳預設「傳播頻道」訊息。

| 項目 | 傳播光 | 社區救生圈 |
| --- | --- | --- |
| 本網絡連接碼 | `582193` | 由目錄管理員分配，本文以 `704826` 為例 |
| WebSocket 地址 | 沿用 `582193` 現有登記 | 本文以 `wss://chat.example.com/ws/light` 為例 |
| 查碼目錄 | `https://www.aieco.hk/api/lightmesh` | 預設使用相同目錄 |

手機上，`582193` 填在社區救生圈的「對方的 6 位連接碼」。傳播光用戶若要主動接入社區救生圈，則輸入社區救生圈獲分配的碼。連接碼用於查找 relay。

## 1. 在 aaPanel 主機啟動 relay

以下用 Linux、Dart SDK 和 Nginx。準備獨立子域名並讓 DNS 指向 aaPanel 主機，在 aaPanel 為它啟用有效的 HTTPS 憑證。將下文的 `chat.example.com` 換成該域名。

SSH 或 aaPanel 終端進入伺服器上的 `aieco_share` 專案根目錄（含 `tool/`），執行下列指令。程式使用 Dart 標準程式庫。

```bash
dart tool/aieco_light_relay.dart --loopback --port 47892
```

另開終端確認 `curl -fsS http://127.0.0.1:47892/ws/light` 回應 `AIECO Light relay`。正式運作時可用 systemd 託管同一條命令，並將 Dart 執行檔、腳本及工作目錄改成伺服器實際的絕對路徑。

```ini
# /etc/systemd/system/lifebuoy-relay.service
[Unit]
Description=Lifebuoy WebSocket relay
After=network.target

[Service]
User=www
WorkingDirectory=/www/wwwroot/aieco_share
ExecStart=/opt/dart-sdk/bin/dart /www/wwwroot/aieco_share/tool/aieco_light_relay.dart --loopback --port 47892
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
```

結束前景測試程序後，執行 `sudo systemctl daemon-reload` 和 `sudo systemctl enable --now lifebuoy-relay`。用 `sudo journalctl -u lifebuoy-relay -n 40` 查看日誌。

在 **聊天室子域名** 的 Nginx HTTPS `server` 區塊加入以下設定，然後執行 `sudo nginx -t`，成功後從 aaPanel 重新載入 Nginx。

```nginx
location = /ws/light {
    proxy_pass http://127.0.0.1:47892;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 120s;
    proxy_buffering off;
}
```

對外連線使用 `wss://chat.example.com/ws/light`。手機 App 的帳戶、時間帳、交換和資料庫仍走原本的 Nuxt REST API。

## 2. 在共用目錄登記社區救生圈

要和現有傳播光 App 互連，請在它實際使用的目錄新增社區救生圈的六位碼及 WSS 地址。若目錄用 Nuxt 環境變數 `LIGHTMESH_NETWORKS_JSON` 管理，將新條目併入**現有 JSON**，保留 `582193` 及其餘登記。重新載入該服務後核對兩個碼。

```powershell
$directory = 'https://www.aieco.hk/api/lightmesh'
Invoke-RestMethod "$directory/networks/582193"
Invoke-RestMethod "$directory/networks/704826"
```

兩個回應都應包含各自的 `code` 和 `relay`，且 relay 地址各不相同。自設目錄可用 [Dart 查碼服務](CROSS_APP_CHAT.md#6-位碼配對服務部署)，兩個 App 必須以相同的 `AIECO_NETWORK_DIRECTORY_URL` 建置。設定網址時填目錄的 base URL，App 會加上 `/networks/<連接碼>`。

## 3. 建置及在手機驗證

在本機 PowerShell 進入 `aieco_share` 根目錄，先將 WSS 地址及示例碼換成目錄實際登記的設定。

```powershell
flutter pub get
flutter build apk --release `
  --dart-define=LIFEBUOY_RELAY_URL=wss://chat.example.com/ws/light `
  --dart-define=LIFEBUOY_NETWORK_CONNECTION_CODE=704826 `
  --dart-define=AIECO_NETWORK_DIRECTORY_URL=https://www.aieco.hk/api/lightmesh
```

以社區救生圈原有發佈金鑰簽署 APK，才可覆蓋已用同一金鑰簽署的版本。iOS 可將三個 `--dart-define` 一併傳給原有 Flutter 建置指令。

1. 傳播光選擇「線上」，打開「光之通道」的預設「傳播頻道」。
2. 社區救生圈開啟「光網聊天」，按「連接另一個光網 APP」。預填的對方碼是 `582193`，按「接通另一個 APP」。
3. 看到「兩個 APP 的聊天室已互通」後關閉對話框。在兩台手機各發一則新訊息，確認對方各收到一次。
4. 可反向驗證。在傳播光的互連頁輸入社區救生圈的碼。任一邊有一部手機維持互連即可。如接入者中斷互通、停止 App 或切回 LAN，這部手機的公網轉送會停止。

查不到碼時先核對共用目錄。查碼成功仍連不上時，檢查兩個 WSS 地址、Nginx WebSocket 升級和本網絡的連線狀態。
