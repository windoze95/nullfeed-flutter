import 'package:flutter_test/flutter_test.dart';
import 'package:nullfeed/screens/video_player_screen.dart';

void main() {
  group('playback timeline duration', () {
    test('uses metadata when the native stream duration is unknown', () {
      final duration = effectivePlaybackDuration(
        Duration.zero,
        const Duration(minutes: 10),
      );

      expect(duration, const Duration(minutes: 10));
      expect(
        playbackProgressFraction(
          const Duration(minutes: 2, seconds: 30),
          duration,
        ),
        0.25,
      );
    });

    test('prefers a valid native duration over stale metadata', () {
      final duration = effectivePlaybackDuration(
        const Duration(minutes: 8),
        const Duration(minutes: 10),
      );

      expect(duration, const Duration(minutes: 8));
    });

    test('unknown duration produces an empty fill', () {
      expect(
        effectivePlaybackDuration(Duration.zero, Duration.zero),
        Duration.zero,
      );
      expect(
        playbackProgressFraction(const Duration(seconds: 30), Duration.zero),
        0,
      );
    });
  });
}
