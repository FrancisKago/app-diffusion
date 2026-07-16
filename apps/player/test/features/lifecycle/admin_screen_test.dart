import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:player/features/lifecycle/application/cache_readiness.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/features/lifecycle/data/battery_optim_checker.dart';
import 'package:player/features/lifecycle/presentation/admin_screen.dart';
import 'package:shared/shared.dart';

class _MockChecker extends Mock implements BatteryOptimChecker {}

void main() {
  testWidgets('renders diagnostic fields and battery exclusion button',
      (tester) async {
    // Tall viewport so the whole (now longer) diagnostic ListView renders —
    // off-screen ListView children aren't built and can't be found/tapped.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
          playerDiagnosticsProvider.overrideWith((ref) async {
            return PlayerDiagnostics(
              playlistName: 'Playlist test',
              playlistVersion: 3,
              itemCount: 2,
              readiness: computeCacheReadiness(
                const [MediaRef(filename: 'a.mp4', localPath: '/m/a.mp4')],
                (_) => true,
              ),
              cacheBytes: 2048,
            );
          }),
        ],
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0.1.0+1'), findsOneWidget);
    expect(find.text('d-abc'), findsOneWidget);
    expect(find.text('Playlist test'), findsOneWidget);
    expect(find.textContaining('1/1'), findsOneWidget); // médias prêts
    expect(find.textContaining('Demander'), findsOneWidget);

    await tester.tap(find.textContaining('Demander'));
    await tester.pump();
    verify(() => checker.openExclusionSettings()).called(1);
  });
}
