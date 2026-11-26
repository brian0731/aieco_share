import 'dart:io';

import 'package:aieco_share/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final failures in [1, 2]) {
    testWidgets('iPad-sized launch recovers from $failures network failures', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(820, 1180);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LifebuoyHome(
            fetchPublicBoard: () async {
              if (++attempts <= failures) {
                throw const SocketException('Network unavailable');
              }
              return {'posts': <Json>[], 'items': <Json>[]};
            },
          ),
        ),
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pump(const Duration(milliseconds: 501));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      if (failures == 2) {
        expect(find.text('暫時未能載入社區內容'), findsOneWidget);
        expect(find.text('目前沒有這類貼文'), findsNothing);
        await tester.tap(find.text('重試'));
        await tester.pumpAndSettle();
        expect(attempts, 3);
      }
      expect(find.text('暫時未能載入社區內容'), findsNothing);
      expect(find.text('目前沒有這類貼文'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
