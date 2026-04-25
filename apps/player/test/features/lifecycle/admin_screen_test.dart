import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/features/lifecycle/data/battery_optim_checker.dart';
import 'package:player/features/lifecycle/presentation/admin_screen.dart';
import 'package:shared/shared.dart';

class _MockChecker extends Mock implements BatteryOptimChecker {}

void main() {
  testWidgets('renders diagnostic fields and battery exclusion button',
      (tester) async {
    final checker = _MockChecker();
    when(() => checker.isExcluded()).thenAnswer((_) async => false);
    when(() => checker.openExclusionSettings()).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          batteryOptimCheckerProvider.overrideWithValue(checker),
          adminDiagnosticProvider.overrideWith((ref) async {
            return const AdminDiagnostic(
              appVersion: '0.1.0+1',
              deviceId: 'd-abc',
              foregroundServiceRunning: true,
              batteryOptimExcluded: false,
            );
          }),
        ],
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0.1.0+1'), findsOneWidget);
    expect(find.text('d-abc'), findsOneWidget);
    expect(find.textContaining('Demander'), findsOneWidget);

    await tester.tap(find.textContaining('Demander'));
    await tester.pump();
    verify(() => checker.openExclusionSettings()).called(1);
  });
}
