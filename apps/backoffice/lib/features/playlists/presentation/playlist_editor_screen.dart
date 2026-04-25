import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

import '../../media/application/media_controller.dart';
import '../application/playlists_controller.dart';

class PlaylistEditorScreen extends ConsumerStatefulWidget {
  const PlaylistEditorScreen({required this.playlistId, super.key});
  final String playlistId;

  @override
  ConsumerState<PlaylistEditorScreen> createState() =>
      _PlaylistEditorScreenState();
}

class _PlaylistEditorScreenState extends ConsumerState<PlaylistEditorScreen> {
  List<PlaylistItem>? _localItems;
  bool _publishing = false;
  String? _error;

  String _rel(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }

  Future<void> _publish() async {
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      await ref.read(playlistsRepositoryProvider).publish(widget.playlistId);
      ref.invalidate(playlistDetailProvider(widget.playlistId));
      ref.invalidate(playlistsListProvider);
    } on AppException catch (e) {
      setState(() => _error = '${e.message} — ${e.cause}');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _addMedia(Playlist playlist) async {
    final mediaList = await ref.read(mediaListProvider.future);
    final sameEstab = mediaList
        .where((m) => m.establishmentId == playlist.establishmentId)
        .toList();
    if (!mounted) return;
    final selected = await showDialog<Media>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter un média'),
        content: SizedBox(
          width: 480,
          height: 400,
          child: sameEstab.isEmpty
              ? const Center(child: Text('Aucun média pour cet établissement.'))
              : ListView.builder(
                  itemCount: sameEstab.length,
                  itemBuilder: (_, i) {
                    final m = sameEstab[i];
                    return ListTile(
                      leading: Icon(m.type == MediaType.video
                          ? Icons.movie_outlined
                          : Icons.image_outlined),
                      title: Text(m.originalFilename,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${m.type.dbValue} · ${(m.fileSize / 1024 / 1024).toStringAsFixed(1)} Mo'),
                      onTap: () => Navigator.pop(ctx, m),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    try {
      await ref
          .read(playlistItemsRepositoryProvider)
          .append(playlistId: widget.playlistId, mediaId: selected.id);
      ref.invalidate(playlistItemsProvider(widget.playlistId));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = '${e.message} — ${e.cause}');
    }
  }

  Future<void> _deleteItem(String itemId) async {
    try {
      await ref.read(playlistItemsRepositoryProvider).delete(itemId);
      ref.invalidate(playlistItemsProvider(widget.playlistId));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = '${e.message} — ${e.cause}');
    }
  }

  Future<void> _editItem(PlaylistItem item, Media? media) async {
    final durCtrl =
        TextEditingController(text: item.displayDurationSec.toString());
    DateTime? startsAt = item.startsAt;
    DateTime? endsAt = item.endsAt;
    final isImage = media?.type == MediaType.image;
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setState) {
        final datesInvalid = startsAt != null &&
            endsAt != null &&
            !startsAt!.isBefore(endsAt!);
        return AlertDialog(
          title: const Text("Éditer l'élément"),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isImage)
                  TextField(
                    controller: durCtrl,
                    decoration: const InputDecoration(
                      labelText: "Durée d'affichage (s)",
                    ),
                    keyboardType: TextInputType.number,
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: startsAt ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) setState(() => startsAt = picked);
                        },
                        child: Text(startsAt == null
                            ? 'Début (aucun)'
                            : 'Début : ${startsAt!.toIso8601String().substring(0, 10)}'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => startsAt = null),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: endsAt ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) setState(() => endsAt = picked);
                        },
                        child: Text(endsAt == null
                            ? 'Fin (aucune)'
                            : 'Fin : ${endsAt!.toIso8601String().substring(0, 10)}'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => endsAt = null),
                    ),
                  ],
                ),
                if (datesInvalid) ...[
                  const SizedBox(height: 12),
                  Text(
                    'La date de fin doit être strictement après la date de début.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: datesInvalid
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Enregistrer'),
            ),
          ],
        );
      }),
    );
    if (result != true) return;
    try {
      final durParsed = int.tryParse(durCtrl.text);
      await ref.read(playlistItemsRepositoryProvider).updateItem(
            id: item.id,
            displayDurationSec: isImage ? durParsed : null,
            startsAt: startsAt,
            endsAt: endsAt,
            clearStartsAt: startsAt == null && item.startsAt != null,
            clearEndsAt: endsAt == null && item.endsAt != null,
          );
      ref.invalidate(playlistItemsProvider(widget.playlistId));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = '${e.message} — ${e.cause}');
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (_localItems == null) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _localItems!.removeAt(oldIndex);
      _localItems!.insert(newIndex, item);
    });
    try {
      await ref.read(playlistItemsRepositoryProvider).reorder(
            playlistId: widget.playlistId,
            orderedItemIds: _localItems!.map((i) => i.id).toList(),
          );
      ref.invalidate(playlistItemsProvider(widget.playlistId));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = '${e.message} — ${e.cause}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistAsync = ref.watch(playlistDetailProvider(widget.playlistId));
    final itemsAsync = ref.watch(playlistItemsProvider(widget.playlistId));
    final mediaAsync = ref.watch(mediaListProvider);

    return Scaffold(
      appBar: AppBar(
        title: playlistAsync.maybeWhen(
          data: (p) => Text(p.name),
          orElse: () => const Text('Playlist'),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/playlists'),
        ),
      ),
      body: playlistAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (playlist) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Version ${playlist.version}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            playlist.publishedAt == null
                                ? 'Jamais publiée'
                                : 'Publiée ${_rel(playlist.publishedAt!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _publishing ? null : _publish,
                      icon: _publishing
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.publish),
                      label: const Text('Publier'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _addMedia(playlist),
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter un média'),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              const Divider(height: 1),
              Expanded(
                child: itemsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Erreur items : $e')),
                  data: (items) {
                    _localItems ??= List.of(items);
                    if (_localItems!.length != items.length ||
                        !_sameOrder(_localItems!, items)) {
                      _localItems = List.of(items);
                    }
                    if (_localItems!.isEmpty) {
                      return const Center(
                          child: Text('Playlist vide. Ajoutez un média.'));
                    }
                    final mediaById = <String, Media>{};
                    mediaAsync.whenData(
                        (list) => mediaById.addEntries(list.map((m) => MapEntry(m.id, m))));
                    return ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _localItems!.length,
                      onReorder: _onReorder,
                      itemBuilder: (_, i) {
                        final item = _localItems![i];
                        final media = mediaById[item.mediaId];
                        return ListTile(
                          key: ValueKey(item.id),
                          leading: SizedBox(
                            width: 48,
                            child: Row(
                              children: [
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Icon(Icons.drag_handle),
                                ),
                              ],
                            ),
                          ),
                          title: Text(media?.originalFilename ?? '(média ${item.mediaId.substring(0, 8)}…)'),
                          subtitle: Text(_subtitle(item, media)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editItem(item, media),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteItem(item.id),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _subtitle(PlaylistItem item, Media? media) {
    final parts = <String>['pos ${item.position}'];
    if (media?.type == MediaType.image) {
      parts.add('${item.displayDurationSec}s');
    }
    if (item.startsAt != null || item.endsAt != null) {
      final start = item.startsAt?.toIso8601String().substring(0, 10) ?? '∞';
      final end = item.endsAt?.toIso8601String().substring(0, 10) ?? '∞';
      parts.add('$start → $end');
    }
    return parts.join(' · ');
  }

  bool _sameOrder(List<PlaylistItem> a, List<PlaylistItem> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }
}
