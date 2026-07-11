import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/config/theme.dart';
import 'package:nullfeed/models/ai_providers.dart';
import 'package:nullfeed/services/api_service.dart';
import 'package:nullfeed/widgets/ai_providers_section.dart';

import '../helpers/test_helpers.dart';

AiProvidersStatus _status({
  Map<String, dynamic>? geminiKey,
  String rankProvider = '',
  Map<String, dynamic>? rankEffective,
}) => AiProvidersStatus.fromJson({
  'keys': {
    'anthropic': {'configured': false, 'source': null, 'last4': null},
    'gemini': geminiKey ?? {'configured': false, 'source': null, 'last4': null},
    'openai': {'configured': false, 'source': null, 'last4': null},
  },
  'embed': {
    'provider': '',
    'model': '',
    'source': 'env',
    'effective': null,
    'options': ['gemini', 'openai'],
  },
  'rank': {
    'provider': rankProvider,
    'model': '',
    'source': rankProvider.isEmpty ? 'env' : 'runtime',
    'effective': rankEffective,
    'options': ['anthropic', 'gemini', 'openai'],
  },
  'availability': {
    'anthropic': false,
    'gemini': geminiKey?['configured'] == true,
    'openai': false,
  },
});

void main() {
  late MockApiService api;

  setUp(() {
    api = MockApiService();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiServiceProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: NullFeedTheme.darkTheme,
          home: const Scaffold(
            body: SingleChildScrollView(child: AiProvidersSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders a key card per provider and the selection cards', (
    tester,
  ) async {
    when(() => api.getAiProviders()).thenAnswer((_) async => _status());
    await pump(tester);

    expect(find.text('Anthropic'), findsOneWidget);
    expect(find.text('Google Gemini'), findsOneWidget);
    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('Embedding provider'), findsOneWidget);
    expect(find.text('Ranking provider'), findsOneWidget);
    // No provider available yet.
    expect(find.textContaining('None available'), findsWidgets);
  });

  testWidgets('shows the masked key badge and effective provider', (
    tester,
  ) async {
    when(() => api.getAiProviders()).thenAnswer(
      (_) async => _status(
        geminiKey: {'configured': true, 'source': 'runtime', 'last4': 'wxyz'},
        rankProvider: 'gemini',
        rankEffective: {'provider': 'gemini', 'model': 'gemini-3.5-flash'},
      ),
    );
    await pump(tester);

    expect(find.text('••wxyz'), findsOneWidget);
    expect(find.textContaining('Using gemini'), findsWidgets);
  });

  testWidgets('saving a key calls setAiKey and clears the field', (
    tester,
  ) async {
    when(() => api.getAiProviders()).thenAnswer((_) async => _status());
    when(
      () => api.setAiKey('openai', 'sk-test'),
    ).thenAnswer((_) async => _status());
    await pump(tester);

    final field = find.widgetWithText(TextField, 'API key').last;
    await tester.enterText(field, 'sk-test');
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await tester.pumpAndSettle();

    verify(() => api.setAiKey('openai', 'sk-test')).called(1);
  });
}
