import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

import '../../playlists/presentation/assign_playlist_dialog.dart';
import '../application/devices_controller.dart';
import 'claim_pairing_dialog.dart';

class DevicesListScreen extends ConsumerWidget {
  const DevicesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(devicesListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appareils'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(devicesListProvider),
          ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Appairer par code',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const ClaimPairingDialog(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/devices/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouvel appareil'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Aucun appareil.'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = list[i];
              return ListTile(
                leading: SizedBox(
                  width: 56,
                  child: Row(
                    children: [
                      _StatusDot(lastSeenAt: d.lastSeenAt),
                      const SizedBox(width: 8),
                      Icon(
                        d.orientation.dbValue == 'portrait'
                            ? Icons.stay_current_portrait
                            : Icons.tv_outlined,
                      ),
                    ],
                  ),
                ),
                title: Text(d.name),
                subtitle: Text(_subtitleFor(d)),
                trailing: IconButton(
                  icon: const Icon(Icons.queue_music_outlined),
                  tooltip: 'Assigner une playlist',
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AssignPlaylistDialog(device: d),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

String _subtitleFor(Device d) {
  final parts = <String>[
    d.orientation.dbValue,
    '${d.id.substring(0, 8)}…',
  ];
  if (d.syncProgress != null && d.syncProgress! < 100) {
    parts.add('sync ${d.syncProgress}%');
  }
  if (d.lastSeenAt != null) {
    parts.add(_relSince(d.lastSeenAt!));
  } else {
    parts.add('jamais vu');
  }
  return parts.join(' · ');
}

String _relSince(DateTime when) {
  final diff = DateTime.now().toUtc().difference(when.toUtc());
  if (diff.inMinutes < 1) return 'à l\'instant';
  if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
  if (diff.inDays < 1) return 'il y a ${diff.inHours} h';
  return 'il y a ${diff.inDays} j';
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({this.lastSeenAt});
  final DateTime? lastSeenAt;

  @override
  Widget build(BuildContext context) {
    final isOnline = lastSeenAt != null &&
        DateTime.now().toUtc().difference(lastSeenAt!.toUtc()).inMinutes < 10;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOnline ? Colors.green.shade400 : Colors.grey.shade600,
      ),
    );
  }
}
