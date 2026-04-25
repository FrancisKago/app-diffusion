import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/features/lifecycle/presentation/admin_overlay.dart';

void main() {
  testWidgets('shows nothing when battery optim is excluded',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isBatteryOptimExcludedProvider.overrideWith((ref) async => true),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(children: [AdminOverlay()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('shows orange warning icon when battery optim is NOT excluded',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isBatteryOptimExcludedProvider.overrideWith((ref) async => false),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(children: [AdminOverlay()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
