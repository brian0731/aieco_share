import 'package:aieco_share/lifebuoy_illustration.dart';
import 'package:aieco_share/lifebuoy_lightmesh_banner.dart';
import 'package:aieco_share/lightmesh.dart' show MeshMessage, MeshMessageBubble;
import 'package:aieco_share/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Each main tab displays its bundled art on a narrow phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LifebuoyApp());
    await tester.pumpAndSettle();

    const tabScenes = {
      '社區互助': 'community',
      '時間銀行': 'time',
      '交換': 'exchange',
      '光網聊天': 'chat',
    };
    for (final MapEntry(:key, :value) in tabScenes.entries) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(key),
        ),
      );
      await tester.pumpAndSettle();

      final banner = find.byType(LifebuoyIllustration);
      if (key != '光網聊天') {
        expect(banner, findsOneWidget);
        expect(tester.widget<LifebuoyIllustration>(banner).scene, value);
        expect(tester.getSize(banner).width, greaterThan(250));
      }
      final asset = await tester.runAsync(
        () => rootBundle.load('assets/images/lifebuoy/$value.webp'),
      );
      expect(asset?.lengthInBytes, greaterThan(10000));
      expect(
        find.byType(TextField).hitTestable(),
        findsNWidgets(key == '光網聊天' ? 2 : 1),
      );
      expect(
        find.byType(LifebuoyLightMeshBanner),
        key == '社區互助' ? findsOneWidget : findsNothing,
      );
      if (key == '光網聊天') {
        final connection = find.text('連接光網');
        final interconnect = tester.getRect(connection);
        expect(find.text('LAN 聊天'), findsNothing);
        expect(find.widgetWithText(FilledButton, '公開房間'), findsNothing);
        expect(interconnect.right, lessThanOrEqualTo(320));
        expect(find.text('傳播頻道'), findsOneWidget);
        expect(find.text('傳送到 傳播頻道'), findsOneWidget);
        expect(connection.hitTestable(), findsOneWidget);

        final composer = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.hintText == '傳送到 傳播頻道',
        );
        await tester.enterText(composer, '保留聊天室草稿');
        await tester.tap(find.text('交換').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(find.text('光網聊天').hitTestable());
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(composer).controller?.text, '保留聊天室草稿');
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'Chat bubbles align incoming and outgoing text on opposite sides',
    (tester) async {
      MeshMessage message(String id, {required bool isMine}) => MeshMessage(
        id: id,
        roomId: 'room:main',
        roomName: '傳播頻道',
        senderId: id,
        senderName: isMine ? '我' : List.filled(60, '傳播光').join(),
        text: '你好',
        sentAt: DateTime(2026, 11, 21),
        isMine: isMine,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 280,
                child: ListView(
                  children: [
                    MeshMessageBubble(
                      message: message('received', isMine: false),
                    ),
                    MeshMessageBubble(message: message('sent', isMine: true)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final received = find.byKey(
        const ValueKey('selectable-message-received'),
      );
      final sent = find.byKey(const ValueKey('selectable-message-sent'));
      expect(tester.getTopLeft(received).dx, lessThan(30));
      expect(tester.getTopRight(sent).dx, greaterThan(250));
      expect(tester.widget<SelectableText>(sent).style?.color, Colors.white);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Login art and account controls fit on a narrow phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LifebuoyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('登入或註冊'));
    await tester.pumpAndSettle();

    final banner = find.byWidgetPredicate(
      (widget) => widget is LifebuoyIllustration && widget.scene == 'login',
    );
    expect(tester.getSize(banner), const Size(272, 153));
    final asset = await tester.runAsync(
      () => rootBundle.load('assets/images/lifebuoy/login.webp'),
    );
    expect(asset?.lengthInBytes, greaterThan(10000));
    expect(find.byType(TextFormField).hitTestable(), findsNWidgets(2));
    expect(
      find.widgetWithText(FilledButton, '登入').hitTestable(),
      findsOneWidget,
    );

    await tester.tap(find.text('建立帳號'));
    await tester.pumpAndSettle();
    expect(banner, findsOneWidget);
    expect(find.text('香港地區（必選）'), findsOneWidget);
    final register = find.widgetWithText(FilledButton, '註冊');
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(4));
    expect(find.text('確認密碼'), findsOneWidget);
    await tester.ensureVisible(fields.at(2));
    await tester.enterText(fields.at(2), 'passphrase-one');
    await tester.ensureVisible(fields.at(3));
    await tester.enterText(fields.at(3), 'passphrase-two');
    await tester.ensureVisible(register);
    await tester.pumpAndSettle();
    expect(register.hitTestable(), findsOneWidget);
    await tester.tap(register);
    await tester.pumpAndSettle();
    expect(find.text('兩次輸入的密碼不一致'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  const storeUrls = {
    TargetPlatform.android:
        'https://play.google.com/store/apps/details?id=aieco.light.mesh',
    TargetPlatform.iOS:
        'https://apps.apple.com/us/app/%E5%82%B3%E6%92%AD%E5%85%89-lightmesh/id6781610489',
  };
  for (final MapEntry(key: platform, value: url) in storeUrls.entries) {
    testWidgets('LightMesh banner opens the store for ${platform.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      final phoneWidth = platform == TargetPlatform.android ? 320.0 : 430.0;
      tester.view.physicalSize = Size(phoneWidth, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final requests = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        requests.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: const Scaffold(body: LifebuoyLightMeshBanner()),
        ),
      );
      expect(find.text('下載傳播光 APP'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      final banner = tester.getRect(find.byType(LifebuoyLightMeshBanner));
      expect(banner.size, Size(phoneWidth, 120));
      final artwork = tester.widget<Image>(find.byType(Image));
      expect(artwork.fit, BoxFit.fitHeight);
      expect(artwork.alignment, Alignment.centerRight);
      final title = tester.getRect(find.text('下載傳播光 APP'));
      expect(title.right, lessThan(banner.left + banner.width * 0.56));
      await tester.tapAt(Offset(banner.right - 20, banner.bottom - 12));
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(requests.single.method, 'launch');
      expect(requests.single.arguments['url'], url);
      expect(requests.single.arguments['useWebView'], isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
