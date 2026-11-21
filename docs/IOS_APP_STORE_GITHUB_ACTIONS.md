# 社區救生圈 iOS 上傳與金鑰設定

GitHub Actions 會在 macOS runner 建置 Flutter iOS App、簽署 IPA、保留下載檔，並上傳到 App Store Connect。Bundle ID 固定為 `aieco.light.lifebuoy`，對應 App Store Connect 的「社區救生圈」。上傳完成後，可在 Apple 後台選擇 build、送審和安排發布。[社區救生圈 App Store Connect](https://appstoreconnect.apple.com/apps/6837667547/distribution/ios/version/inflight) · [Apple 上傳說明](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)

## 1. 建立 App Store Connect API 金鑰

1. 登入 App Store Connect 並選擇擁有「社區救生圈」的團隊，進入 **Users and Access → Integrations → App Store Connect API → Team Keys**。
2. 首次啟用 API 時，由 Account Holder 按 **Request Access**。啟用後，由 Account Holder 或 Admin 按 **Generate API Key** 或 `+`。
3. 名稱可填 `Lifebuoy GitHub Actions`，角色選 **Developer**，足以執行 build 上傳。Team Key 的角色權限適用於這個 Apple 團隊的所有 App。
4. 記下 **Issuer ID** 和剛建立的 **Key ID**。下載 `AuthKey_<Key ID>.p8` 並保存在私人位置，Apple 只提供一次下載。

[Apple Team Key 設定](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)

## 2. 準備 iOS 簽署檔

1. 使用同一 Apple Developer 團隊有效的 **Apple Distribution** 簽署身分。在有該憑證及私鑰的 Mac 開啟 **Xcode → Settings → Accounts → 選團隊 → Manage Certificates**，對憑證按右鍵選 **Export Certificate**，存為 `distribution.p12` 並設定匯出密碼。若團隊已提供可用的 `.p12`，可直接沿用。
2. 到 **Apple Developer → Certificates, Identifiers & Profiles → Profiles → +**，在 Distribution 選 **App Store Connect**，選明確的 App ID `aieco.light.lifebuoy`，再選同一張 Apple Distribution 憑證。產生並下載，存作 `Lifebuoy_AppStore.mobileprovision`。

[Apple 簽署憑證匯出](https://developer.apple.com/documentation/xcode/sharing-your-teams-signing-certificates) · [Apple 發行描述檔](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/)

### Apple 顯示 Upload a Certificate Signing Request 時

在 Mac 開啟 **Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority**。填 Apple Developer 帳戶電郵及 Common Name（例如 `Lifebuoy Distribution`），CA Email Address 留空。選 **Saved to disk** 並按 **Continue**，然後把儲存的 `.certSigningRequest` 上傳至 Apple Developer。下載簽發的 `.cer` 後，在建立 CSR 的同一部 Mac 匯入，再按上方步驟匯出 `.p12`。[Apple CSR 步驟](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request/)

在 Windows 也可以用 OpenSSL 產生 CSR。在 Git 專案外開一個新的私人資料夾，從 PowerShell 進入該資料夾。把 `developer@example.com` 改為你的 Apple Developer 電郵，然後輸入並記下 OpenSSL 要求設定的私鑰密碼。

```powershell
openssl req -new -newkey rsa:2048 -sha256 -keyout lifebuoy-distribution.key.pem -out Lifebuoy.certSigningRequest -subj '/CN=Lifebuoy Distribution/emailAddress=developer@example.com'
openssl req -in Lifebuoy.certSigningRequest -verify -noout
```

在 Apple Developer 的 **Apple Distribution → Upload a Certificate Signing Request → Choose File** 選 `Lifebuoy.certSigningRequest`，然後按 **Continue**。`lifebuoy-distribution.key.pem` 是配對私鑰，保留在私人資料夾。

Apple 簽發憑證後，把下載的 `.cer` 以 `distribution.cer` 存到同一資料夾。先轉成 PEM，再與原來的私鑰匯出成 `.p12`。OpenSSL 會先要求原本的私鑰密碼，再讓你設定 `.p12` 的匯出密碼。第 3 節的 `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` 使用 `.p12` 的匯出密碼。[OpenSSL CSR](https://docs.openssl.org/3.6/man1/openssl-req/) · [OpenSSL PKCS#12](https://docs.openssl.org/3.6/man1/openssl-pkcs12/)

```powershell
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export -inkey lifebuoy-distribution.key.pem -in distribution.pem -out distribution.p12
```

## 3. 將六個 Secrets 加到 GitHub

在 `brian0731/aieco_share` 開啟 **Settings → Environments → apple**。如 `apple` 尚未建立，按 **New environment** 建立，再逐項按 **Add environment secret**。秘密也可統一放到 **Settings → Secrets and variables → Actions → Repository secrets**。若兩處都有同名 Secret，執行時會使用 `apple` 環境的值。[GitHub Environments](https://github.com/brian0731/aieco_share/settings/environments) · [GitHub Secrets 說明](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)

| Secret 名稱 | 貼入內容 |
| --- | --- |
| `APP_STORE_CONNECT_API_KEY_ID` | Apple Team Keys 的 **Key ID** |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Apple Team Keys 頁面的 **Issuer ID** |
| `APP_STORE_CONNECT_API_KEY_BASE64` | `AuthKey_<Key ID>.p8` 的 Base64 |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | `distribution.p12` 的 Base64 |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | 匯出 `.p12` 時設定的密碼 |
| `IOS_PROVISIONING_PROFILE_BASE64` | `Lifebuoy_AppStore.mobileprovision` 的 Base64 |

在 Windows PowerShell 進入存放檔案的私人資料夾，把範例檔名換成你的實際檔名。**逐行執行，每次執行後立刻貼入對應 Secret**。

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath '.\AuthKey_你的KEYID.p8').Path)) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath '.\distribution.p12').Path)) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath '.\Lifebuoy_AppStore.mobileprovision').Path)) | Set-Clipboard
```

把 `.p8`、`.p12`、密碼及 Base64 值留在私人儲存與 GitHub Secrets。Base64 可以還原成原始檔。

## 4. 執行 iOS 上傳

1. 將更新後的 workflow 和要發布的 App 程式碼推到 GitHub。手動執行的 workflow 需存在於預設分支 `main`。
2. 開啟 **Actions → iOS App Store Release → Run workflow**，選要建置的分支。
3. `build_name` 填 Apple 後台對應的版本。若「社區救生圈」草稿仍是 `1.0`，填 `1.0`。`build_number` 填比該 iOS 版本已上傳 build 更高的整數。兩欄留空時，版本取自 `pubspec.yaml`，build number 為 `pubspec.yaml` 的 build number 加上 GitHub run number。重新上傳已用過的 build number 時，請另開一次 **Run workflow** 並填新號碼。
4. 確認 **Upload to App Store Connect** 成功。Apple 完成處理後，到版本頁的「构建版本」選取。IPA 也可從該次 Actions 執行的 **Artifacts → ios-app-store-ipa** 下載。

現有的 `v*` 和 `ios-v*` Git Tag 也會觸發上傳，並使用上述預設版本規則。[GitHub Actions 執行頁](https://github.com/brian0731/aieco_share/actions/workflows/ios-app-store.yml) · [GitHub 手動執行說明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)

## 正式連線設定

以下公開值已有預設。需要更換時，可在 `apple` 環境的 **Environment variables** 設同名變數。

| 變數 | 預設值 |
| --- | --- |
| `LIFEBUOY_API_URL` | `https://lifebuoy.aieco.hk` |
| `LIFEBUOY_RELAY_URL` | `wss://lifebuoy.aieco.hk/ws/light` |
| `LIFEBUOY_NETWORK_CONNECTION_CODE` | `952678` |
| `AIECO_NETWORK_DIRECTORY_URL` | `https://lifebuoy.aieco.hk/api/lightmesh` |

## 常見上傳錯誤

| Actions 提示 | 核對項目 |
| --- | --- |
| Secret is not configured | 到 `aieco_share` 的 `apple` 環境或 Repository secrets 核對名稱與內容。 |
| Profile bundle ID 不符 | 重建 `aieco.light.lifebuoy` 專用的 App Store Connect 描述檔。 |
| 找不到簽署身分 | `.p12` 應有私鑰，且必須是建立 `.mobileprovision` 時選的有效 Apple Distribution 憑證。 |
| altool 認證失敗 | 確認 `.p8`、Key ID、Issuer ID 出自同一 Apple 團隊，且 Team Key 仍有效。 |
| Build number 已使用 | 手動執行 workflow 並輸入更高的 `build_number`。 |
