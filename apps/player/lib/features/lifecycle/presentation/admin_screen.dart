import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/providers.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  static String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} Mo';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} Go';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagAsync = ref.watch(adminDiagnosticProvider);
    final playerDiagAsync = ref.watch(playerDiagnosticsProvider);
    final lastSyncError = ref.watch(lastSyncErrorProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Player'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir le diagnostic',
            onPressed: () {
              ref.invalidate(adminDiagnosticProvider);
              ref.invalidate(playerDiagnosticsProvider);
            },
          ),
        ],
      ),
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

            // Diffusion diagnostics — the fields that explain "stuck on
            // standby / black screen": playlist state + cache readiness.
            Text('Diffusion', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (lastSyncError != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                color: Colors.red.withValues(alpha: 0.15),
                child: Text(
                  'Dernière sync en erreur : $lastSyncError',
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            playerDiagAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
              error: (e, _) => Text('Erreur cache: $e'),
              data: (p) {
                final r = p.readiness;
                return Column(
                  children: [
                    _kv('Playlist active',
                        p.playlistName ?? 'aucune (écran d\'attente)'),
                    _kv('Version playlist', p.playlistVersion.toString()),
                    _kv('Éléments', p.itemCount.toString()),
                    _kv(
                      'Médias prêts',
                      '${r.downloaded}/${r.total}'
                          '${r.isReady ? ' ✓' : ''}',
                    ),
                    _kv('Cache disque', _humanSize(p.cacheBytes)),
                    if (r.missing.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(8),
                        color: Colors.orange.withValues(alpha: 0.15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Médias non téléchargés (${r.missing.length}) — '
                              'diffusion bloquée tant qu\'ils manquent :',
                              style:
                                  const TextStyle(color: Colors.orangeAccent),
                            ),
                            const SizedBox(height: 4),
                            ...r.missing.take(10).map(
                                  (f) => Text('• $f',
                                      style: const TextStyle(fontSize: 12)),
                                ),
                            if (r.missing.length > 10)
                              Text('… +${r.missing.length - 10} autres',
                                  style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                );
              },
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
              onPressed: () {
                ref.read(forceSyncRequestProvider.notifier).state++;
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sync demandée')),
                  );
                }
              },
              child: const Text('Forcer une sync maintenant'),
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
