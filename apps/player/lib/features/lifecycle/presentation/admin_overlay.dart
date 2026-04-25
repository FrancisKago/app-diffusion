import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/features/lifecycle/presentation/admin_screen.dart';

class AdminOverlay extends ConsumerWidget {
  const AdminOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final excludedAsync = ref.watch(isBatteryOptimExcludedProvider);
    final excluded = excludedAsync.valueOrNull ?? true;
    if (excluded) return const SizedBox.shrink();
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        color: Colors.transparent,
        child: IconButton(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.orangeAccent,
            size: 28,
          ),
          tooltip: "Optimisation batterie active — toucher pour ouvrir l'admin",
          onPressed: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const AdminScreen()),
            );
          },
        ),
      ),
    );
  }
}
