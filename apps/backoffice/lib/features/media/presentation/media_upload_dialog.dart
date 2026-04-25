import 'package:flutter/material.dart';

/// Stub — replaced in Task 7 with real implementation.
class MediaUploadDialog extends StatelessWidget {
  const MediaUploadDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Uploader un média'),
      content: const Text('À venir.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
