import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import 'package:video_player/video_player.dart';

import '../application/media_controller.dart';

class MediaPreviewDialog extends ConsumerWidget {
  const MediaPreviewDialog({required this.media, super.key});
  final Media media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(mediaSignedUrlProvider(media));
    return Dialog(
      insetPadding: const EdgeInsets.all(48),
      child: SizedBox(
        width: 800,
        height: 600,
        child: Column(
          children: [
            AppBar(
              title: Text(media.originalFilename),
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Expanded(
              child: urlAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erreur : $e')),
                data: (url) => media.type == MediaType.image
                    ? InteractiveViewer(
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              const Center(child: Icon(Icons.broken_image)),
                        ),
                      )
                    : _VideoPreview(url: url),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({required this.url});
  final String url;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: VideoProgressIndicator(_controller, allowScrubbing: true),
        ),
        Positioned(
          bottom: 32,
          child: IconButton.filled(
            icon: Icon(_controller.value.isPlaying
                ? Icons.pause
                : Icons.play_arrow),
            onPressed: () => setState(() {
              _controller.value.isPlaying
                  ? _controller.pause()
                  : _controller.play();
            }),
          ),
        ),
      ],
    );
  }
}
