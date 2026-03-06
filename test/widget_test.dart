import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nullfeed/app.dart';
import 'package:nullfeed/config/constants.dart';

void main() {
  setUp(() async {
    Hive.init('/tmp/hive_test');
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.sessionBox);
    await Hive.openBox(AppConstants.offlineBox);
  });

  tearDown(() async {
    await Hive.close();
  });

  testWidgets('NullFeedApp renders without errors', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: NullFeedApp()));

    // Verify the app renders (will show profile picker or server setup)
    expect(find.byType(NullFeedApp), findsOneWidget);
  });
}
