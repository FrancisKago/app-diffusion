import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/features/lifecycle/data/battery_optim_checker.dart';
import 'package:player/features/lifecycle/presentation/first_run_battery_dialog.dart';

class _MockChecker extends Mock implements BatteryOptimChecker {}

void main() {
  testWidgets('does NOT show dialog when already shown previously',
      (tester) async {
    var openCount = 0;
    final checker = _MockChecker();
    when(() => checker.openExclusionSettings()).thenAnswer((_) async {
      openCount++;
    });
    var markedShown = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          batteryOptimCheckerProvider.overrideWithValue(checker),
          firstRunBatteryShownProvider.overrideWith((ref) async => true),
          markFirstRunBatteryShownProvider.overrideWithValue(() async {
            markedShown = true;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FirstRunBatteryGate(child: SizedBox.shrink())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Autoriser l'exécution permanente"), findsNothing);
    expect(openCount, 0);
    expect(markedShown, isFalse);
  });

  testWidgets('shows dialog and tapping OK calls openExclusionSettings + marks shown',
      (tester) async {
    var openCount = 0;
    final checker = _MockChecker();
    when(() => checker.openExclusionSettings()).thenAnswer((_) async {
      openCount++;
    });
    var markedShown = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          batteryOptimCheckerProvider.overrideWithValue(checker),
          firstRunBatteryShownProvider.overrideWith((ref) async => false),
          isBatteryOptimExcludedProvider.overrideWith((ref) async => false),
          markFirstRunBatteryShownProvider.overrideWithValue(() async {
            markedShown = true;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FirstRunBatteryGate(child: SizedBox.shrink())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Autoriser l'exécution permanente"), findsOneWidget);
    await tester.tap(find.text('Autoriser'));
    await tester.pumpAndSettle();
    expect(openCount, 1);
    expect(markedShown, isTrue);
  });
}
