import 'package:flutter_test/flutter_test.dart';
import 'package:nullfeed/screens/video_player_screen.dart';

void main() {
  group('sponsorSkipDecision', () {
    const startSponsor = (start: 0.0, end: 30.0);

    test('seeks to the segment end on first entry', () {
      final d = sponsorSkipDecision(0.0, const [startSponsor], null);
      expect(d.seekToMs, 30000);
      expect(d.inFlightEnd, 30.0);
    });

    test('does not re-issue the seek while the same skip is in flight', () {
      // Playhead still stuck inside the segment (the seek is still buffering) —
      // the guard must return null so the caller does not storm seekTo.
      final d = sponsorSkipDecision(0.2, const [startSponsor], 30.0);
      expect(d.seekToMs, isNull);
      expect(d.inFlightEnd, 30.0);
    });

    test('a stuck playhead yields exactly one seek over many ticks (no storm)', () {
      // This is the regression guard: a start sponsor whose seek can't land yet
      // (unbuffered instant/preview source) must not fire seekTo every tick.
      double? inFlight;
      var seeks = 0;
      for (var tick = 0; tick < 100; tick++) {
        final d = sponsorSkipDecision(0.1, const [startSponsor], inFlight);
        inFlight = d.inFlightEnd;
        if (d.seekToMs != null) seeks++;
      }
      expect(seeks, 1);
    });

    test('clears the guard once the playhead lands past the segment', () {
      final d = sponsorSkipDecision(30.0, const [startSponsor], 30.0);
      expect(d.seekToMs, isNull);
      expect(d.inFlightEnd, isNull);
    });

    test('skips a later segment after passing an earlier one', () {
      const segs = [(start: 0.0, end: 30.0), (start: 60.0, end: 75.0)];
      // Landed past the first segment: the guard clears and nothing new seeks.
      final past = sponsorSkipDecision(30.0, segs, 30.0);
      expect(past.seekToMs, isNull);
      expect(past.inFlightEnd, isNull);
      // Entering the second segment skips it.
      final second = sponsorSkipDecision(60.0, segs, past.inFlightEnd);
      expect(second.seekToMs, 75000);
      expect(second.inFlightEnd, 75.0);
    });

    test('chains directly into an adjacent segment', () {
      const segs = [(start: 0.0, end: 30.0), (start: 30.0, end: 45.0)];
      // The first skip lands at 30.0, which is the start of the next segment;
      // the same tick must skip straight into it.
      final d = sponsorSkipDecision(30.0, segs, 30.0);
      expect(d.seekToMs, 45000);
      expect(d.inFlightEnd, 45.0);
    });

    test('no seek when the playhead is outside every segment', () {
      final d = sponsorSkipDecision(45.0, const [startSponsor], null);
      expect(d.seekToMs, isNull);
      expect(d.inFlightEnd, isNull);
    });

    test('respects the 0.5s tail margin near the segment end', () {
      // Inside the last 0.5s of the segment — let it play out, no seek.
      final d = sponsorSkipDecision(29.6, const [startSponsor], null);
      expect(d.seekToMs, isNull);
    });

    test('no segments means no decision', () {
      final d = sponsorSkipDecision(
        10.0,
        const <({double start, double end})>[],
        null,
      );
      expect(d.seekToMs, isNull);
      expect(d.inFlightEnd, isNull);
    });
  });
}
