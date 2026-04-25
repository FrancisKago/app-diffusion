import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// Stub — replaced in Task 8 with real implementation.
class MediaPreviewDialog extends StatelessWidget {
  const MediaPreviewDialog({required this.media, super.key});

  final Media media;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 400,
        height: 200,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(media.originalFilename),
            const SizedBox(height: 16),
            const Text('Aperçu à venir.'),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        ),
      ),
    );
  }
}
