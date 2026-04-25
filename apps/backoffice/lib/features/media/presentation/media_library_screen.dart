import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../application/media_controller.dart';
import 'media_preview.dart';
import 'media_upload_dialog.dart';

class MediaLibraryScreen extends ConsumerWidget {
  const MediaLibraryScreen({super.key});

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} Mo';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mediaListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Médias'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(mediaListProvider),
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
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Aucun média.'));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.8,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final m = list[i];
              return _MediaCard(
                media: m,
                sizeLabel: _humanSize(m.fileSize),
              );
            },
          );
        },
      ),
    );
  }
}

class _MediaCard extends ConsumerWidget {
  const _MediaCard({required this.media, required this.sizeLabel});

  final Media media;
  final String sizeLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      Text(sizeLabel,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
