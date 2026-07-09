import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nullfeed/config/theme.dart';
import 'package:nullfeed/widgets/skip_control.dart';

void main() {
  Future<void> pumpControl(
    WidgetTester tester, {
    bool forward = true,
    String? holdLabel,
    VoidCallback? onTap,
    VoidCallback? onHoldStart,
    VoidCallback? onHoldEnd,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NullFeedTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: SkipControl(
              forward: forward,
              seconds: 10,
              holdLabel: holdLabel,
              onTap: onTap ?? () {},
              onHoldStart: onHoldStart ?? () {},
              onHoldEnd: onHoldEnd ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('tap fires onTap once', (tester) async {
    var taps = 0;
    await pumpControl(tester, onTap: () => taps++);

    await tester.tap(find.byType(SkipControl));
    // Let the one-shot sweep animation run out.
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('press-and-hold fires onHoldStart, release fires onHoldEnd', (
    tester,
  ) async {
    var starts = 0;
    var ends = 0;
    await pumpControl(
      tester,
      onHoldStart: () => starts++,
      onHoldEnd: () => ends++,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SkipControl)),
    );
    // Past the long-press threshold.
    await tester.pump(const Duration(milliseconds: 700));
    expect(starts, 1);
    expect(ends, 0);

    await gesture.up();
    await tester.pump();
    expect(ends, 1);
  });

  testWidgets('idle control hides the skip size; holdLabel appears on hold', (
    tester,
  ) async {
    await pumpControl(tester);
    expect(find.text('10s'), findsNothing);

    await pumpControl(tester, holdLabel: '+45s');
    expect(find.text('+45s'), findsOneWidget);
    expect(find.text('10s'), findsNothing);

    // Back to idle (hold released) — the repeating sweep must stop so the
    // test's ticker assertions (and the widget) settle.
    await pumpControl(tester);
    expect(find.text('10s'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('exposes a button with a hold hint to assistive tech', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpControl(tester);

    expect(
      find.bySemanticsLabel(
        'Skip forward 10 seconds. Press and hold to fast-forward.',
      ),
      findsOneWidget,
    );

    handle.dispose();
  });
}
