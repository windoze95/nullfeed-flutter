import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nullfeed/app.dart';

void main() {
  testWidgets('NullFeedApp renders without errors', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: NullFeedApp(),
      ),
    );

    // Verify the app renders (will show profile picker or server setup)
    expect(find.byType(NullFeedApp), findsOneWidget);
  });
}
