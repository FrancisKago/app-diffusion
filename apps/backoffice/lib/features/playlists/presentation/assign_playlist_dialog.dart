import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../application/playlists_controller.dart';

class AssignPlaylistDialog extends ConsumerStatefulWidget {
  const AssignPlaylistDialog({required this.device, super.key});
  final Device device;

  @override
  ConsumerState<AssignPlaylistDialog> createState() =>
      _AssignPlaylistDialogState();
}

class _AssignPlaylistDialogState extends ConsumerState<AssignPlaylistDialog> {
  String? _playlistId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    try {
      final current = await ref
          .read(devicePlaylistsRepositoryProvider)
          .playlistForDevice(widget.device.id);
      if (mounted) setState(() => _playlistId = current);
    } catch (_) {
      // ignore — user can still pick
    }
  }

  Future<void> _assign() async {
    if (_playlistId == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(devicePlaylistsRepositoryProvider).assign(
            deviceId: widget.device.id,
            playlistId: _playlistId!,
          );
      if (mounted) Navigator.pop(context);
    } on AppException catch (e) {
      setState(() => _error = '${e.message} — ${e.cause}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _unassign() async {
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(devicePlaylistsRepositoryProvider).unassign(widget.device.id);
      if (mounted) Navigator.pop(context);
    } on AppException catch (e) {
      setState(() => _error = '${e.message} — ${e.cause}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsListProvider);
    return AlertDialog(
      title: Text('Playlist pour ${widget.device.name}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            playlistsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Erreur: $e'),
              data: (list) {
                final scoped = list
                    .where((p) => p.establishmentId == widget.device.establishmentId)
                    .toList();
                if (scoped.isEmpty) {
                  return const Text(
                      'Aucune playlist dans l\'établissement de cet appareil.');
                }
                return DropdownButtonFormField<String>(
                  initialValue: _playlistId,
                  decoration: const InputDecoration(labelText: 'Playlist'),
                  items: [
                    for (final p in scoped)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setState(() => _playlistId = v),
                );
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: _saving ? null : _unassign,
          child: const Text('Détacher'),
        ),
        FilledButton(
          onPressed: (_saving || _playlistId == null) ? null : _assign,
          child: _saving
              ? const SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Assigner'),
        ),
      ],
    );
  }
}
