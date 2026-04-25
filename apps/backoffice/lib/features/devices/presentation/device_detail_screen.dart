import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

import '../../establishments/application/establishments_controller.dart';
import '../../media/application/media_controller.dart';
import '../application/devices_controller.dart';
import '../data/device_detail_repository.dart';

class DeviceDetailScreen extends ConsumerStatefulWidget {
  const DeviceDetailScreen({required this.deviceId, super.key});
  final String deviceId;

  @override
  ConsumerState<DeviceDetailScreen> createState() =>
      _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(devicesListProvider);
      ref.invalidate(deviceHeartbeatsProvider(widget.deviceId));
      ref.invalidate(devicePlaybackLogsProvider(widget.deviceId));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(devicesListProvider);
    final heartbeatsAsync = ref.watch(deviceHeartbeatsProvider(widget.deviceId));
    final logsAsync = ref.watch(devicePlaybackLogsProvider(widget.deviceId));
    final establishmentsAsync = ref.watch(establishmentsListProvider);
    final mediaAsync = ref.watch(mediaListProvider);

    final device = devicesAsync.maybeWhen(
      data: (list) {
        for (final d in list) {
          if (d.id == widget.deviceId) return d;
        }
        return null;
      },
      orElse: () => null,
    );

    final establishmentName = device == null
        ? null
        : establishmentsAsync.maybeWhen(
            data: (list) {
              for (final e in list) {
                if (e.id == device.establishmentId) return e.name;
              }
              return null;
            },
            orElse: () => null,
          );

    Media? currentMedia;
    if (device?.currentMediaId != null) {
      currentMedia = mediaAsync.maybeWhen(
        data: (list) {
          for (final m in list) {
            if (m.id == device!.currentMediaId) return m;
          }
          return null;
        },
        orElse: () => null,
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/devices'),
        ),
        title: Text(device?.name ?? 'Appareil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(devicesListProvider);
              ref.invalidate(deviceHeartbeatsProvider(widget.deviceId));
              ref.invalidate(devicePlaybackLogsProvider(widget.deviceId));
            },
          ),
        ],
      ),
      body: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (_) {
          if (device == null) {
            return const Center(child: Text('Appareil introuvable.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusSection(
                device: device,
                establishmentName: establishmentName,
                currentMedia: currentMedia,
              ),
              const SizedBox(height: 24),
              Text(
                'Heartbeats récents',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _HeartbeatsList(async: heartbeatsAsync),
              const SizedBox(height: 24),
              Text(
                'Lectures récentes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _PlaybackLogsList(async: logsAsync, mediaAsync: mediaAsync),
            ],
          );
        },
      ),
    );
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.device,
    required this.establishmentName,
    required this.currentMedia,
  });

  final Device device;
  final String? establishmentName;
  final Media? currentMedia;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOnline = device.lastSeenAt != null &&
        DateTime.now()
                .toUtc()
                .difference(device.lastSeenAt!.toUtc())
                .inMinutes <
            10;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline
                        ? Colors.green.shade400
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  isOnline ? 'En ligne' : 'Hors ligne',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _kv('Établissement', establishmentName ?? '—'),
            _kv('Orientation', device.orientation.dbValue),
            _kv(
              'Vu pour la dernière fois',
              device.lastSeenAt != null
                  ? _relSince(device.lastSeenAt!)
                  : 'jamais',
            ),
            if (device.syncProgress != null && device.syncProgress! < 100) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: device.syncProgress! / 100),
              const SizedBox(height: 4),
              Text('sync ${device.syncProgress}%',
                  style: theme.textTheme.bodySmall),
            ],
            if (currentMedia != null) ...[
              const SizedBox(height: 8),
              Text('▶ ${currentMedia!.originalFilename}',
                  style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 220,
              child: Text(key),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

class _HeartbeatsList extends StatelessWidget {
  const _HeartbeatsList({required this.async});
  final AsyncValue<List<DeviceHeartbeat>> async;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(8),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => Text('Erreur heartbeats : $e'),
      data: (list) {
        if (list.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aucun heartbeat reçu.'),
            ),
          );
        }
        return Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final hb = list[i];
              final parts = <String>[];
              if (hb.battery != null) parts.add('🔋 ${hb.battery}%');
              if (hb.storageFreeMb != null) {
                parts.add('💾 ${hb.storageFreeMb} Mo');
              }
              if (hb.appVersion != null) parts.add('v${hb.appVersion}');
              return ListTile(
                dense: true,
                leading: const Icon(Icons.favorite_outline, size: 18),
                title: Text(_fmtDateTime(hb.receivedAt)),
                subtitle: parts.isEmpty ? null : Text(parts.join(' · ')),
              );
            },
          ),
        );
      },
    );
  }
}

class _PlaybackLogsList extends StatelessWidget {
  const _PlaybackLogsList({
    required this.async,
    required this.mediaAsync,
  });
  final AsyncValue<List<PlaybackLogEntry>> async;
  final AsyncValue<List<Media>> mediaAsync;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(8),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => Text('Erreur logs : $e'),
      data: (list) {
        if (list.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aucune lecture enregistrée.'),
            ),
          );
        }
        return Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final entry = list[i];
              final mediaName = mediaAsync.maybeWhen(
                data: (medias) {
                  for (final m in medias) {
                    if (m.id == entry.mediaId) return m.originalFilename;
                  }
                  return null;
                },
                orElse: () => null,
              );
              return ListTile(
                dense: true,
                leading: const Icon(Icons.play_circle_outline, size: 18),
                title: Text(mediaName ?? entry.mediaId ?? '(média supprimé)'),
                subtitle: Text(
                  '${_fmtDateTime(entry.playedAt)} · '
                  '${_fmtDuration(entry.durationPlayedSec)}',
                ),
              );
            },
          ),
        );
      },
    );
  }
}

String _fmtDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _fmtDateTime(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _relSince(DateTime when) {
  final diff = DateTime.now().toUtc().difference(when.toUtc());
  if (diff.inMinutes < 1) return 'à l\'instant';
  if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
  if (diff.inDays < 1) return 'il y a ${diff.inHours} h';
  return 'il y a ${diff.inDays} j';
}
