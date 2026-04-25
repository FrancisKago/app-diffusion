import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';

class FirstRunBatteryGate extends ConsumerStatefulWidget {
  const FirstRunBatteryGate({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<FirstRunBatteryGate> createState() =>
      _FirstRunBatteryGateState();
}

class _FirstRunBatteryGateState extends ConsumerState<FirstRunBatteryGate> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    if (_checked) return;
    _checked = true;
    final shown = await ref.read(firstRunBatteryShownProvider.future);
    if (shown) return;
    final excluded = await ref.read(isBatteryOptimExcludedProvider.future);
    if (excluded) {
      await ref.read(markFirstRunBatteryShownProvider)();
      return;
    }
    if (!mounted) return;
    final action = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Autoriser l'exécution permanente"),
        content: const Text(
          "Pour garantir la diffusion 24h/24, l'app doit être exclue "
          "de l'optimisation batterie d'Android. Autoriser maintenant ?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Autoriser'),
          ),
        ],
      ),
    );
    if (action == true) {
      await ref.read(batteryOptimCheckerProvider).openExclusionSettings();
    }
    await ref.read(markFirstRunBatteryShownProvider)();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
