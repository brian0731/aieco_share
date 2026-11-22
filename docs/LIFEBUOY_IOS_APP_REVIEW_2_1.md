# 社區救生圈 iOS App Review 2.1 補件

到 **社區救生圈 → Distribution → iOS 版本 → App Review Information → Notes**。完成實機測試後，把下方英文草稿的方括號換成實際資料。把持續有效的示範會員帳密填入同頁 **Sign-in information**，並另用一個臨時帳戶錄製刪除流程。若錄影以上傳連結提供，先用無痕視窗確認 Apple 審核員可以直接播放。這份錄影供 App Review 使用。[App Store Connect](https://appstoreconnect.apple.com/apps/6837667547/distribution/ios/version/inflight) · [Apple 補件說明](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/)

## 英文 Notes 草稿

```text
Hello App Review,

1. Physical-device recording
[Insert the recording link or the attachment filename.] The recording starts at the iPhone Home Screen and shows the app launch, registration, sign-in, the main tabs, and account deletion. Tested devices and OS versions: [insert verified iPhone and iPad models and OS versions]. Build: [insert the build number shown in TestFlight for the recording].

2. Purpose and audience
Community Lifebuoy (社區救生圈) helps residents of Hong Kong's 18 districts find and offer practical neighbourhood help, track time spent helping one another, and exchange everyday items. The Time Bank records service minutes. The minutes have no cash value and cannot be purchased or redeemed for money. The app has no in-app purchases, subscriptions or paid features.

3. How to review the main features
• Community Help (社區互助) opens at launch. Visitors can browse and search public help posts and item listings.
• Tap the profile icon in the upper right, then Create Account (建立帳號). Enter a display name, select a Hong Kong district, enter a username and a password of at least 12 characters, and confirm the password. Use Sign In (登入) for an existing account. A demo member account is provided in Sign-in Information. No administrator credentials are needed for the mobile app.
• After sign-in, use Publish (刊登) on Community Help to offer or request help. Tap Time Bank (時間銀行) and Transaction History (收支明細) to see the starting allowance and service entries. Tap Exchange (交換) to browse or list items for barter. To test a two-person exchange or settlement, use a second test member in the same district.
• Tap Light Network Chat (光網聊天) to open the public room. A network connection code is only needed to connect a separate Light Network. In the updated build, use the three-dot menu beside a message, help post or item listing to report it or block its author on the device. Sign in as a member to submit a report. Use the shield button to manage blocked users and find the support email. [Verify these paths in the submitted build and add recording timestamps.]
• To test deletion, use a temporary account. Open the profile menu → User Settings (用戶設定) → Delete Account (刪除帳戶). Enter the current password and confirm. Deletion revokes access, erases listing text, ratings and linked chat, and cancels open transactions. Other parties retain the minutes and status of shared transactions. Listing text, meeting details and the deleted member's name are removed from these records. Legacy guest chat and copies held by other Light Network apps may remain.

4. Services used
The developer-operated HTTPS API at https://lifebuoy.aieco.hk provides member accounts, community listings, Time Bank records, and item exchanges. The developer-operated WebSocket relay at wss://lifebuoy.aieco.hk/ws/light delivers public chat, and the network directory at https://lifebuoy.aieco.hk/api/lightmesh resolves six-digit codes. Signup and sign-in use the developer's own username and password system. No payment processor, third-party sign-in or AI service is required for the app's core features.

5. Regional differences
The same app features are available regardless of the reviewer's physical location. Registration requires choosing one of Hong Kong's 18 districts. Signed-in listings are scoped to the selected district, so listings can differ by district. The same app build serves all supported locations.

6. Regulated services or protected third-party material
The app provides neighbourhood coordination and item barter. It does not provide financial, medical, or emergency dispatch services. [Confirm the rights for all bundled artwork, fonts, marks and linked third-party material. If applicable, name the material and identify the authorization attachment. If no authorization document applies, state that.]
```

## 實機錄影順序

1. 用 TestFlight 安裝準備送審的 build。在支援的 iPhone 和 iPad 使用最新版系統測試，記下型號、系統版本及 build number。用 iPhone 控制中心開始錄影，從主畫面點「社區救生圈」啟動。
2. 以訪客搜尋社區互助及瀏覽交換。點右上角 →「建立帳號」，展示選區、確認密碼及註冊。登出，再登入新帳戶。
3. 刊登一筆示範服務，開「時間銀行 → 收支明細」展示起始額度及已有紀錄，再開「交換」展示刊登與交換入口。需要另一位會員的流程可用同區第二個測試帳戶操作。
4. 進入「光網聊天」，用第二部裝置發出兩則示範訊息。透過其中一則訊息旁的選單舉報，再用另一則訊息的選單封鎖發送者，錄到訊息從清單消失。也展示互助貼文和物品刊登旁的舉報入口。
5. 在片尾用臨時帳戶開「用戶設定 → 刪除帳戶」，重新輸入密碼並確認，錄到返回訪客畫面。另以第二部裝置核對刪除後刊登已移除、光網訊息已清除，並測試舊密碼無法登入。保留 Apple 的示範登入帳戶。

[Apple 實機測試與 TestFlight](https://developer.apple.com/help/app-review/before-submitting-for-review/test-compatible-devices)

## 現有版本的送審缺口

- 新程式碼已加入互助貼文、交換刊登和公開聊天的舉報及封鎖。要在正式環境驗收，先套用 `012_content_reports` 遷移並部署新版 Nuxt，再用新版 App 測試內容過濾、舉報送達後台、封鎖和解除封鎖。確認管理員可在「內容舉報」查看與下架示範內容。[Apple Guideline 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content)
- `013_account_erasure` 會清除過去已刪帳會員留下的刊登原文、評分及相關資料。新版 App 可訪客閱讀光網訊息，發送則需登入，讓 Relay 能在刪帳後停止轉傳該會員的訊息，新版社區救生圈客戶端會同步移除已收到的訊息。歷史訪客訊息沒有會員關聯，其他光網 App 的獨立副本可能仍然存在。正式部署後需用待送審 build 實測刪除。[帳戶刪除程式](../lifebuoy/server/utils/account-erasure.ts) · [Apple 帳戶刪除要求](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion)
- 正式公開看板 API 已確認回應。示範帳密、刪除流程和裝置錄影仍須在待送審的實機 build 驗證。完成後在 Apple 版本頁儲存 Notes 並確認選取同一版 build。[Apple 重新送審步驟](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/manage-a-submission-with-unresolved-issues/)
