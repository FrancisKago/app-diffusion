import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../establishments/application/establishments_controller.dart';
import '../application/media_controller.dart';
import '../data/media_repository.dart';

class MediaUploadDialog extends ConsumerStatefulWidget {
  const MediaUploadDialog({super.key});

  @override
  ConsumerState<MediaUploadDialog> createState() => _MediaUploadDialogState();
}

class _MediaUploadDialogState extends ConsumerState<MediaUploadDialog> {
  String? _establishmentId;
  PlatformFile? _file;
  String? _error;
  bool _uploading = false;

  static const _videoExt = {'mp4'};
  static const _imageExt = {'jpg', 'jpeg', 'png', 'webp'};
  static const _videoMax = 100 * 1024 * 1024;
  static const _imageMax = 10 * 1024 * 1024;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [..._videoExt, ..._imageExt],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    setState(() {
      _file = f;
      _error = _validate(f);
    });
  }

  String? _validate(PlatformFile f) {
    final ext = f.extension?.toLowerCase();
    if (ext == null) return 'Extension manquante';
    final isVideo = _videoExt.contains(ext);
    final isImage = _imageExt.contains(ext);
    if (!isVideo && !isImage) return 'Format non supporté';
    final maxSize = isVideo ? _videoMax : _imageMax;
    if (f.size > maxSize) {
      return 'Fichier trop gros (max ${(maxSize / 1024 / 1024).toInt()} Mo)';
    }
    if (f.bytes == null) return 'Lecture du fichier impossible';
    return null;
  }

  Future<void> _upload() async {
    if (_file == null || _error != null || _establishmentId == null) return;
    final f = _file!;
    final bytes = f.bytes!;
    final ext = f.extension!.toLowerCase();
    final isVideo = _videoExt.contains(ext);

    setState(() => _uploading = true);
    try {
      final checksum = sha256.convert(bytes).toString();

      int? width;
      int? height;
      if (!isVideo) {
        try {
          final img = await decodeImageFromList(bytes);
          width = img.width;
          height = img.height;
        } catch (_) {
          // Best-effort — don't block upload if dimensions can't be decoded.
        }
      }
      // TODO Phase 3.5: extract video duration/dimensions via video_player

      final mime = switch (ext) {
        'mp4' => 'video/mp4',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'application/octet-stream',
      };

      await ref.read(mediaRepositoryProvider).upload(MediaUploadInput(
            establishmentId: _establishmentId!,
            type: isVideo ? MediaType.video : MediaType.image,
            bytes: bytes,
            mimeType: mime,
            checksum: checksum,
            originalFilename: f.name,
            width: width,
            height: height,
          ));

      ref.invalidate(mediaListProvider);
      ref.invalidate(mediaWithUsageListProvider);
      if (mounted) Navigator.of(context).pop();
    } on AppException catch (e) {
      setState(() => _error = '${e.message} — ${e.cause}');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final establishmentsAsync = ref.watch(establishmentsListProvider);
    return AlertDialog(
      title: const Text('Uploader un média'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            establishmentsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Erreur: $e'),
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _establishmentId,
                decoration: const InputDecoration(labelText: 'Établissement'),
                items: [
                  for (final e in list)
                    DropdownMenuItem(value: e.id, child: Text(e.name)),
                ],
                onChanged: (v) => setState(() => _establishmentId = v),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickFile,
              icon: const Icon(Icons.attach_file),
              label: Text(_file?.name ?? 'Choisir un fichier'),
            ),
            const SizedBox(height: 8),
            Text('MP4 ≤ 100 Mo · JPG/PNG/WebP ≤ 10 Mo',
                style: Theme.of(context).textTheme.bodySmall),
            if (_file != null) ...[
              const SizedBox(height: 12),
              Text(
                '${(_file!.size / 1024 / 1024).toStringAsFixed(2)} Mo',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_uploading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _uploading ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: (_uploading ||
                  _file == null ||
                  _error != null ||
                  _establishmentId == null)
              ? null
              : _upload,
          child: _uploading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Uploader'),
        ),
      ],
    );
  }
}
