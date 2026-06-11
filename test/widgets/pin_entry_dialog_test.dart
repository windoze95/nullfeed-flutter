import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nullfeed/widgets/pin_entry_dialog.dart';

void main() {
  Future<void> pumpDialogHost(
    WidgetTester tester, {
    required Future<String?> Function(String pin) onSubmit,
    required void Function(String? result) onClosed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await showDialog<String>(
                    context: context,
                    builder: (_) => PinEntryDialog(
                      title: 'Enter PIN',
                      subtitle: 'Enter the PIN for Bob',
                      onSubmit: onSubmit,
                    ),
                  );
                  onClosed(result);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('rejects a too-short PIN before calling onSubmit', (
    tester,
  ) async {
    var submitCalls = 0;
    await pumpDialogHost(
      tester,
      onSubmit: (_) async {
        submitCalls++;
        return null;
      },
      onClosed: (_) {},
    );

    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a 4-8 digit PIN'), findsOneWidget);
    expect(submitCalls, 0);
    expect(find.byType(PinEntryDialog), findsOneWidget);
  });

  testWidgets('shows the onSubmit error inline and stays open for retries', (
    tester,
  ) async {
    String? closedWith = 'sentinel';
    await pumpDialogHost(
      tester,
      onSubmit: (pin) async => pin == '1234' ? null : 'Incorrect PIN',
      onClosed: (result) => closedWith = result,
    );

    await tester.enterText(find.byType(TextField), '9999');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect PIN'), findsOneWidget);
    expect(find.byType(PinEntryDialog), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty, reason: 'field clears for retry');

    // Retrying with the right PIN succeeds and pops with the PIN.
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.byType(PinEntryDialog), findsNothing);
    expect(closedWith, '1234');
  });

  testWidgets('pops with the PIN when onSubmit succeeds', (tester) async {
    String? closedWith;
    await pumpDialogHost(
      tester,
      onSubmit: (_) async => null,
      onClosed: (result) => closedWith = result,
    );

    await tester.enterText(find.byType(TextField), '4321');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.byType(PinEntryDialog), findsNothing);
    expect(closedWith, '4321');
  });

  testWidgets('cancel pops without a result', (tester) async {
    String? closedWith = 'sentinel';
    await pumpDialogHost(
      tester,
      onSubmit: (_) async => null,
      onClosed: (result) => closedWith = result,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(PinEntryDialog), findsNothing);
    expect(closedWith, isNull);
  });
}
