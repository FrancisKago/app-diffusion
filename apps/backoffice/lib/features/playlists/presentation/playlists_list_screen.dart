import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

import '../../establishments/application/establishments_controller.dart';
import '../application/playlists_controller.dart';

class PlaylistsListScreen extends ConsumerWidget {
  const PlaylistsListScreen({super.key});

  String _rel(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playlistsListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(playlistsListProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle playlist'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('Aucune playlist.'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = list[i];
              final subtitle = [
                'v${p.version}',
                if (p.publishedAt != null)
                  'publiée ${_rel(p.publishedAt!)}'
                else
                  'jamais publiée',
              ].join(' · ');
              return ListTile(
                leading: const Icon(Icons.playlist_play_outlined),
                title: Text(p.name),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/playlists/${p.id}'),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    String? establishmentId;
    List<Establishment> establishments;
    try {
      establishments = await ref.read(establishmentsListProvider.future);
    } catch (_) {
      return;
    }
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        String? error;
        bool saving = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Nouvelle playlist'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nom'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: establishmentId,
                      decoration: const InputDecoration(labelText: 'Établissement'),
                      items: [
                        for (final e in establishments)
                          DropdownMenuItem(value: e.id, child: Text(e.name)),
                      ],
                      onChanged: (v) => setState(() => establishmentId = v),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (nameCtrl.text.trim().isEmpty || establishmentId == null) {
                            setState(() => error = 'Nom et établissement requis');
                            return;
                          }
                          setState(() { saving = true; error = null; });
                          try {
                            await ref.read(playlistsRepositoryProvider).create(
                                  establishmentId: establishmentId!,
                                  name: nameCtrl.text.trim(),
                                );
                            ref.invalidate(playlistsListProvider);
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                          } on AppException catch (e) {
                            setState(() {
                              error = '${e.message} — ${e.cause}';
                              saving = false;
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Créer'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
