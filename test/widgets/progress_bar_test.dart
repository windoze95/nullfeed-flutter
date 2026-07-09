import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nullfeed/widgets/progress_bar.dart';

/// Regression tests for the seek-on-release behavior: issuing a native seek
/// on every drag tick storms the player's seek pipeline and wedges it, so a
/// drag must produce exactly one onSeek — on release — with previews flowing
/// through onSeekPreview instead.
void main() {
  const barWidth = 200.0;

  Future<void> pumpBar(
    WidgetTester tester, {
    required List<double> seeks,
    List<double>? previews,
    void Function()? onStart,
    void Function()? onEnd,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: barWidth,
              child: NullFeedProgressBar(
                progress: 0.25,
                onSeek: seeks.add,
                onSeekPreview: previews?.add,
                onSeekStart: onStart,
                onSeekEnd: onEnd,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('drag previews continuously but seeks once, on release', (
    tester,
  ) async {
    final seeks = <double>[];
    final previews = <double>[];
    var started = 0;
    var ended = 0;
    await pumpBar(
      tester,
      seeks: seeks,
      previews: previews,
      onStart: () => started++,
      onEnd: () => ended++,
    );

    final barFinder = find.byType(NullFeedProgressBar);
    final topLeft = tester.getTopLeft(barFinder);
    final center = tester.getCenter(barFinder);

    final gesture = await tester.startGesture(
      Offset(topLeft.dx + barWidth * 0.2, center.dy),
    );
    await tester.pump();
    // Move well past the drag slop, in several ticks.
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
    }
    expect(seeks, isEmpty, reason: 'no seek may fire while still dragging');
    expect(started, 1);
    expect(previews, isNotEmpty);

    await gesture.up();
    await tester.pump();

    expect(seeks, hasLength(1), reason: 'exactly one seek, on release');
    expect(ended, 1);
    // Released at ~0.2 + 120/200 of the width.
    expect(seeks.single, closeTo(0.8, 0.1));
    // The final preview matches where the seek landed.
    expect(previews.last, closeTo(seeks.single, 0.01));
  });

  testWidgets('tap seeks once to the tapped fraction', (tester) async {
    final seeks = <double>[];
    await pumpBar(tester, seeks: seeks);

    final barFinder = find.byType(NullFeedProgressBar);
    final topLeft = tester.getTopLeft(barFinder);
    final center = tester.getCenter(barFinder);

    await tester.tapAt(Offset(topLeft.dx + barWidth * 0.75, center.dy));
    await tester.pump();

    expect(seeks, hasLength(1));
    expect(seeks.single, closeTo(0.75, 0.05));
  });

  testWidgets('system-cancelled drag ends the scrub with a single commit', (
    tester,
  ) async {
    // Once a horizontal drag is accepted, Flutter routes a pointer cancel to
    // drag END (drag-cancel only fires pre-acceptance), so an interrupted
    // scrub behaves like a release: the scrub ends and exactly one seek — to
    // the last previewed spot — is committed. Never a storm, never a leaked
    // scrub state.
    final seeks = <double>[];
    var started = 0;
    var ended = 0;
    await pumpBar(
      tester,
      seeks: seeks,
      onStart: () => started++,
      onEnd: () => ended++,
    );

    final barFinder = find.byType(NullFeedProgressBar);
    final topLeft = tester.getTopLeft(barFinder);
    final center = tester.getCenter(barFinder);

    final gesture = await tester.startGesture(
      Offset(topLeft.dx + barWidth * 0.2, center.dy),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();

    expect(started, 1);
    expect(ended, 1);
    expect(seeks, hasLength(1));
    expect(seeks.single, closeTo(0.4, 0.05));
  });
}
