import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/providers.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagAsync = ref.watch(adminDiagnosticProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Player')),
      body: diagAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur diag: $e')),
        data: (d) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _kv('Version', d.appVersion),
            _kv('Device id', d.deviceId),
            _kv('Établissement', d.establishmentName ?? '—'),
            _kv('Dernière sync OK', d.lastSyncOk?.toIso8601String() ?? 'jamais'),
            _kv(
              'Service foreground',
              d.foregroundServiceRunning ? 'actif' : 'arrêté',
            ),
            _kv(
              'Battery optimization exclue',
              d.batteryOptimExcluded ? 'oui' : 'non',
            ),
            const Divider(height: 32),
            if (!d.batteryOptimExcluded)
              FilledButton(
                onPressed: () =>
                    ref.read(batteryOptimCheckerProvider).openExclusionSettings(),
                child: const Text("Demander l'exclusion batterie"),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                await ref.read(secureStorageProvider).clear();
                ref.invalidate(credentialsProvider);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Re-appairer (efface les credentials)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 220,
              child: Text(k, style: const TextStyle(color: Colors.white70)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
