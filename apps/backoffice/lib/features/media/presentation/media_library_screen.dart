import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../auth/application/current_profile_provider.dart';
import '../application/media_controller.dart';
import '../data/media_repository.dart';
import 'media_preview.dart';
import 'media_upload_dialog.dart';

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes o';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} Mo';
}

class MediaLibraryScreen extends ConsumerWidget {
  const MediaLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mediaWithUsageListProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final unusedOnly = ref.watch(mediaUnusedOnlyFilterProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Médias'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(mediaWithUsageListProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const MediaUploadDialog(),
        ),
        icon: const Icon(Icons.upload),
        label: const Text('Uploader un média'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (all) {
          final unusedCount = all.where((m) => m.isUnused).length;
          final list =
              unusedOnly ? all.where((m) => m.isUnused).toList() : all;
          return Column(
            children: [
              _Toolbar(
                total: all.length,
                unusedCount: unusedCount,
                unusedOnly: unusedOnly,
                isAdmin: isAdmin,
                onToggleUnused: (v) => ref
                    .read(mediaUnusedOnlyFilterProvider.notifier)
                    .state = v,
                onPurgeUnused: () => _confirmPurgeUnused(
                  context,
                  ref,
                  all.where((m) => m.isUnused).toList(),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text(
                          unusedOnly
                              ? 'Aucun média non utilisé.'
                              : 'Aucun média.',
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _MediaCard(usage: list[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.total,
    required this.unusedCount,
    required this.unusedOnly,
    required this.isAdmin,
    required this.onToggleUnused,
    required this.onPurgeUnused,
  });

  final int total;
  final int unusedCount;
  final bool unusedOnly;
  final bool isAdmin;
  final ValueChanged<bool> onToggleUnused;
  final VoidCallback onPurgeUnused;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Text(
            '$total média(s) · $unusedCount non utilisé(s)',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const Spacer(),
          FilterChip(
            avatar: const Icon(Icons.filter_alt_outlined, size: 18),
            label: const Text('Non utilisés'),
            selected: unusedOnly,
            onSelected: onToggleUnused,
          ),
          if (isAdmin) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: unusedCount == 0 ? null : onPurgeUnused,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: Text('Purger les non utilisés ($unusedCount)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaCard extends ConsumerWidget {
  const _MediaCard({required this.usage});

  final MediaWithUsage usage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = usage.media;
    final isAdmin = ref.watch(isAdminProvider);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => MediaPreviewDialog(media: media),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: Colors.black,
                      child: media.type == MediaType.image
                          ? _ImageThumb(media: media)
                          : Stack(
                              alignment: Alignment.center,
                              children: const [
                                Icon(Icons.movie_outlined,
                                    color: Colors.white24, size: 64),
                                Icon(Icons.play_arrow,
                                    color: Colors.white70, size: 48),
                              ],
                            ),
                    ),
                  ),
                  if (isAdmin)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.white, size: 20),
                          tooltip: 'Supprimer',
                          onPressed: () =>
                              _confirmDeleteMedia(context, ref, usage),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.originalFilename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _TypeChip(type: media.type),
                      const Spacer(),
                      Text(humanSize(media.fileSize),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _UsageChip(usage: usage),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageChip extends StatelessWidget {
  const _UsageChip({required this.usage});
  final MediaWithUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (usage.isUnused) {
      return Row(
        children: [
          Icon(Icons.link_off, size: 14, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Text('Non utilisé',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
      );
    }
    final label = usage.playlistNames.isNotEmpty
        ? 'Utilisé : ${usage.playlistNames.join(", ")}'
        : 'Utilisé dans ${usage.usageCount} playlist(s)';
    return Row(
      children: [
        Icon(Icons.playlist_add_check,
            size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
      ],
    );
  }
}

Future<void> _confirmDeleteMedia(
  BuildContext context,
  WidgetRef ref,
  MediaWithUsage usage,
) async {
  final media = usage.media;
  // A used media cannot be deleted (FK restrict). Explain why instead of
  // failing with a cryptic database error.
  if (!usage.isUnused) {
    final where = usage.playlistNames.isNotEmpty
        ? usage.playlistNames.map((n) => '« $n »').join(', ')
        : '${usage.usageCount} playlist(s)';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Média utilisé'),
        content: Text(
          '"${media.originalFilename}" est utilisé dans : $where.\n\n'
          'Retirez-le de ces playlists avant de pouvoir le supprimer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
    return;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Supprimer ce média ?'),
      content: Text(
        'Fichier : "${media.originalFilename}".\n\n'
        'Le fichier sera retiré du stockage. Cette action est irréversible.',
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
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(mediaRepositoryProvider).delete(media);
    ref.invalidate(mediaWithUsageListProvider);
    ref.invalidate(mediaListProvider);
  } on AppException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${e.message} — ${e.cause}')),
    );
  }
}

Future<void> _confirmPurgeUnused(
  BuildContext context,
  WidgetRef ref,
  List<MediaWithUsage> unused,
) async {
  if (unused.isEmpty) return;
  final totalBytes =
      unused.fold<int>(0, (sum, u) => sum + u.media.fileSize);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Supprimer ${unused.length} média(s) non utilisé(s) ?'),
      content: Text(
        'Tous les médias qui ne sont dans aucune playlist seront supprimés '
        'du stockage (${humanSize(totalBytes)} libérés). '
        'Cette action est irréversible.',
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
          child: const Text('Tout supprimer'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    final n = await ref
        .read(mediaRepositoryProvider)
        .deleteMany(unused.map((u) => u.media).toList());
    ref.invalidate(mediaWithUsageListProvider);
    ref.invalidate(mediaListProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$n média(s) supprimé(s).')),
    );
  } on AppException catch (e) {
    ref.invalidate(mediaWithUsageListProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${e.message} — ${e.cause}')),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});
  final MediaType type;

  @override
  Widget build(BuildContext context) {
    final color = type == MediaType.video
        ? Colors.indigo
        : Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type == MediaType.video ? 'vidéo' : 'image',
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }
}

class _ImageThumb extends ConsumerWidget {
  const _ImageThumb({required this.media});
  final Media media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(mediaSignedUrlProvider(media));
    return urlAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white24)),
      data: (url) => Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Center(child: Icon(Icons.broken_image, color: Colors.white24)),
      ),
    );
  }
}
