import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

import '../../auth/application/current_profile_provider.dart';
import '../../establishments/application/establishments_controller.dart';
import '../../media/application/media_controller.dart';
import '../../playlists/application/playlists_controller.dart';
import '../../playlists/presentation/assign_playlist_dialog.dart';
import '../application/devices_controller.dart';
import 'claim_pairing_dialog.dart';

class DevicesListScreen extends ConsumerWidget {
  const DevicesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(devicesListProvider);
    final isAdmin = ref.watch(isAdminProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appareils'),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: _LiveBadge(),
          ),
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
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/devices/new'),
              icon: const Icon(Icons.add),
              label: const Text('Nouvel appareil'),
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Aucun appareil.'));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisExtent: 220,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) => _DeviceCard(device: list[i]),
          );
        },
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.green.shade400,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'live',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _DeviceCard extends ConsumerWidget {
  const _DeviceCard({required this.device});
  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final establishmentsAsync = ref.watch(establishmentsListProvider);
    final mediaAsync = ref.watch(mediaListProvider);

    final establishmentName = establishmentsAsync.maybeWhen(
      data: (list) {
        for (final e in list) {
          if (e.id == device.establishmentId) return e.name;
        }
        return null;
      },
      orElse: () => null,
    );

    Media? currentMedia;
    if (device.currentMediaId != null) {
      currentMedia = mediaAsync.maybeWhen(
        data: (list) {
          for (final m in list) {
            if (m.id == device.currentMediaId) return m;
          }
          return null;
        },
        orElse: () => null,
      );
    }

    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/devices/${device.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    device.orientation.dbValue == 'portrait'
                        ? Icons.stay_current_portrait
                        : Icons.tv_outlined,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      device.name,
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _StatusDot(lastSeenAt: device.lastSeenAt),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                establishmentName ?? '—',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                device.lastSeenAt != null
                    ? _relSince(device.lastSeenAt!)
                    : 'jamais vu',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (device.syncProgress != null && device.syncProgress! < 100)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: device.syncProgress! / 100,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'sync ${device.syncProgress}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              if (currentMedia != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '▶ ${currentMedia.originalFilename}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const Spacer(),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.queue_music_outlined),
                    tooltip: 'Assigner une playlist',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => AssignPlaylistDialog(device: device),
                    ),
                  ),
                  const Spacer(),
                  _DeviceActionsMenu(device: device),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceActionsMenu extends ConsumerWidget {
  const _DeviceActionsMenu({required this.device});
  final Device device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      onSelected: (value) {
        runDeviceAction(context, ref, device, value);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'details', child: Text('Voir détails')),
        if (isAdmin)
          const PopupMenuItem(
              value: 'unassign', child: Text('Détacher playlist')),
        const PopupMenuItem(value: 'revoke', child: Text('Révoquer')),
        if (isAdmin)
          const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
      ],
    );
  }
}

/// Centralised handler for the device action menu, reused by the cards grid
/// and the detail screen AppBar.
Future<void> runDeviceAction(
  BuildContext context,
  WidgetRef ref,
  Device device,
  String action,
) async {
  switch (action) {
    case 'details':
      context.go('/devices/${device.id}');
      return;
    case 'unassign':
      await _confirmUnassign(context, ref, device);
      return;
    case 'revoke':
      await _confirmRevoke(context, ref, device);
      return;
    case 'delete':
      await _confirmDelete(context, ref, device);
      return;
  }
}

Future<void> _confirmUnassign(
  BuildContext context,
  WidgetRef ref,
  Device device,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Détacher la playlist ?'),
      content: const Text(
        "L'appareil affichera l'écran d'attente jusqu'à ce qu'une nouvelle "
        "playlist soit assignée.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Détacher'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(devicePlaylistsRepositoryProvider).unassign(device.id);
    ref.invalidate(devicesListProvider);
  } on AppException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${e.message} — ${e.cause}')),
    );
  }
}

Future<void> _confirmRevoke(
  BuildContext context,
  WidgetRef ref,
  Device device,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Révoquer cet appareil ?'),
      content: const Text(
        'Il devra être ré-appairé pour fonctionner à nouveau.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Révoquer'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(devicesRepositoryProvider).revoke(device.id);
    ref.invalidate(devicesListProvider);
  } on AppException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${e.message} — ${e.cause}')),
    );
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  Device device,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Supprimer cet appareil ?'),
      content: const Text(
        'Cette action est irréversible. L\'appareil sera retiré '
        'définitivement.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Supprimer définitivement'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(devicesRepositoryProvider).delete(device.id);
    ref.invalidate(devicesListProvider);
  } on AppException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${e.message} — ${e.cause}')),
    );
  }
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
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOnline ? Colors.green.shade400 : Colors.grey.shade600,
      ),
    );
  }
}
