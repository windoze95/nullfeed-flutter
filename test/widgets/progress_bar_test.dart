import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
    double progress = 0.25,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: barWidth,
              child: NullFeedProgressBar(
                progress: progress,
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

  testWidgets('fill reflects progress updates', (tester) async {
    final seeks = <double>[];
    await pumpBar(tester, seeks: seeks, progress: 0.25);

    LinearProgressIndicator indicator() => tester.widget(
      find.descendant(
        of: find.byType(NullFeedProgressBar),
        matching: find.byType(LinearProgressIndicator),
      ),
    );

    expect(indicator().value, 0.25);

    await pumpBar(tester, seeks: seeks, progress: 0.7);
    expect(indicator().value, 0.7);
  });

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

    await tester.tapAt(Offset(topLeft.dx + barWidth * 0.75, center.dy));
    await tester.pump();

    expect(seeks, hasLength(1));
    expect(seeks.single, closeTo(0.75, 0.05));
    expect(started, 1);
    expect(ended, 1);
  });

  testWidgets('seek interaction starts on pointer down before recognition', (
    tester,
  ) async {
    final seeks = <double>[];
    var started = 0;
    var ended = 0;
    await pumpBar(
      tester,
      seeks: seeks,
      onStart: () => started++,
      onEnd: () => ended++,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(NullFeedProgressBar)),
    );
    expect(started, 1);
    expect(ended, 0);

    // A slow press stays active until the actual pointer release.
    await tester.pump(const Duration(seconds: 4));
    expect(started, 1);
    expect(ended, 0);

    await gesture.up();
    await tester.pump();
    expect(ended, 1);
  });

  testWidgets('full touch-sized height can start taps and drags', (
    tester,
  ) async {
    final seeks = <double>[];
    await pumpBar(tester, seeks: seeks);

    final barFinder = find.byType(NullFeedProgressBar);
    final rect = tester.getRect(barFinder);
    expect(rect.height, greaterThanOrEqualTo(44));

    // Both points are well outside the painted 4dp track.
    await tester.tapAt(Offset(rect.left + barWidth * 0.6, rect.top + 2));
    await tester.pump();
    expect(seeks.single, closeTo(0.6, 0.05));

    seeks.clear();
    final gesture = await tester.startGesture(
      Offset(rect.left + barWidth * 0.2, rect.bottom - 2),
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(seeks.single, closeTo(0.6, 0.08));
  });

  testWidgets('mouse can drag from outside the painted track', (tester) async {
    final seeks = <double>[];
    await pumpBar(tester, seeks: seeks);

    final rect = tester.getRect(find.byType(NullFeedProgressBar));
    final gesture = await tester.startGesture(
      Offset(rect.left + barWidth * 0.25, rect.top + 2),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(seeks.single, closeTo(0.75, 0.08));
  });

  testWidgets('passive bar keeps its configured compact height', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NullFeedProgressBar(progress: 0.5, height: 4)),
      ),
    );

    expect(tester.getSize(find.byType(NullFeedProgressBar)).height, 4);
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
