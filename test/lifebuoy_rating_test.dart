import 'package:aieco_share/lifebuoy_rating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Five stars fit on a narrow phone and require confirmation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<int>(
                context: context,
                builder: (_) => const LifebuoyRatingDialog(),
              );
            },
            child: const Text('評分'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('評分'));
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, '送出評分');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    final firstStar = find.byTooltip('1 星');
    final fifthStar = find.byTooltip('5 星');
    expect(tester.getCenter(firstStar).dy, tester.getCenter(fifthStar).dy);
    await tester.tap(find.byTooltip('3 星'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));
    expect(result, isNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(result, 3);
  });
}
