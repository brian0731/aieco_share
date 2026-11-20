import 'package:aieco_share/lifebuoy_illustration.dart';
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
      '時間帳': 'time',
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
      expect(banner, findsOneWidget);
      expect(tester.widget<LifebuoyIllustration>(banner).scene, value);
      expect(tester.getSize(banner).width, greaterThan(250));
      final asset = await tester.runAsync(
        () => rootBundle.load('assets/images/lifebuoy/$value.webp'),
      );
      expect(asset?.lengthInBytes, greaterThan(10000));
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
