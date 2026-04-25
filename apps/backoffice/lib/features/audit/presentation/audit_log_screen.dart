import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/audit_controller.dart';
import '../data/audit_repository.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => ref.invalidate(auditEventsProvider),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  IconData _iconFor(String eventType) => switch (eventType) {
        'device_paired' => Icons.link_outlined,
        'device_revoked' => Icons.block_outlined,
        'playlist_published' => Icons.publish_outlined,
        'user_created' => Icons.person_add_outlined,
        _ => Icons.event_outlined,
      };

  Color _colorFor(BuildContext context, String eventType) => switch (eventType) {
        'device_paired' => Colors.green.shade700,
        'device_revoked' => Theme.of(context).colorScheme.error,
        'playlist_published' => Colors.indigo.shade700,
        'user_created' => Colors.blue.shade700,
        _ => Colors.grey.shade700,
      };

  String _summary(AuditEvent e) {
    final meta = e.metadata ?? {};
    return switch (e.eventType) {
      'device_paired' =>
        'Appareil "${meta['device_name'] ?? '?'}" appairé',
      'device_revoked' =>
        'Appareil "${meta['device_name'] ?? '?'}" révoqué',
      'playlist_published' =>
        'Playlist "${meta['playlist_name'] ?? '?'}" publiée v${meta['version'] ?? '?'}',
      'user_created' =>
        'Profil créé : ${meta['full_name'] ?? '(sans nom)'} (${meta['role'] ?? '?'})',
      _ => e.eventType,
    };
  }

  String _rel(DateTime when) {
    final diff = DateTime.now().difference(when.toLocal());
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(auditEventsProvider);
    final filter = ref.watch(auditFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal d\'audit'),
        actions: [
          const Icon(Icons.circle, size: 8, color: Colors.green),
          const SizedBox(width: 4),
          const Text('live ', style: TextStyle(fontSize: 12)),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(auditEventsProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: filter.eventType,
                    decoration: const InputDecoration(
                      labelText: 'Type d\'événement',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Tous')),
                      DropdownMenuItem(value: 'device_paired', child: Text('Appairage')),
                      DropdownMenuItem(value: 'device_revoked', child: Text('Révocation')),
                      DropdownMenuItem(
                          value: 'playlist_published', child: Text('Publication')),
                      DropdownMenuItem(
                          value: 'user_created', child: Text('Création profil')),
                    ],
                    onChanged: (v) {
                      ref.read(auditFilterProvider.notifier).state =
                          AuditFilter(eventType: v, since: filter.since);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue:
                        DateTime.now().difference(filter.since ?? DateTime.now()).inDays,
                    decoration: const InputDecoration(
                      labelText: 'Période',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Dernières 24h')),
                      DropdownMenuItem(value: 7, child: Text('7 derniers jours')),
                      DropdownMenuItem(value: 30, child: Text('30 derniers jours')),
                    ],
                    onChanged: (days) {
                      if (days == null) return;
                      ref.read(auditFilterProvider.notifier).state = AuditFilter(
                        eventType: filter.eventType,
                        since: DateTime.now().subtract(Duration(days: days)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erreur : $e')),
              data: (events) {
                if (events.isEmpty) {
                  return const Center(child: Text('Aucun événement.'));
                }
                return ListView.separated(
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = events[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            _colorFor(context, e.eventType).withValues(alpha: 0.15),
                        child: Icon(
                          _iconFor(e.eventType),
                          color: _colorFor(context, e.eventType),
                          size: 20,
                        ),
                      ),
                      title: Text(_summary(e)),
                      subtitle: Text(
                        '${e.actorType} · ${_rel(e.createdAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
