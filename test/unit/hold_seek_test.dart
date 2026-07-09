import 'package:flutter_test/flutter_test.dart';
import 'package:nullfeed/config/constants.dart';
import 'package:nullfeed/screens/video_player_screen.dart';

void main() {
  group('holdSeekRateAt', () {
    test('starts at the initial rate', () {
      expect(holdSeekRateAt(0), AppConstants.holdSeekInitialRate);
    });

    test('ramps linearly with hold time', () {
      expect(
        holdSeekRateAt(1),
        AppConstants.holdSeekInitialRate + AppConstants.holdSeekRampPerSecond,
      );
      expect(
        holdSeekRateAt(3),
        AppConstants.holdSeekInitialRate +
            3 * AppConstants.holdSeekRampPerSecond,
      );
    });

    test('caps at the max rate', () {
      expect(holdSeekRateAt(600), AppConstants.holdSeekMaxRate);
      // The cap is a ceiling, not a cliff: just before the cap the ramp is
      // still linear.
      const capAt =
          (AppConstants.holdSeekMaxRate - AppConstants.holdSeekInitialRate) /
          AppConstants.holdSeekRampPerSecond;
      expect(holdSeekRateAt(capAt), AppConstants.holdSeekMaxRate);
      expect(
        holdSeekRateAt(capAt - 0.5),
        lessThan(AppConstants.holdSeekMaxRate),
      );
    });

    test('never decreases as the hold gets longer', () {
      var previous = holdSeekRateAt(0);
      for (var t = 0.5; t <= 20; t += 0.5) {
        final rate = holdSeekRateAt(t);
        expect(rate, greaterThanOrEqualTo(previous));
        previous = rate;
      }
    });
  });
}
