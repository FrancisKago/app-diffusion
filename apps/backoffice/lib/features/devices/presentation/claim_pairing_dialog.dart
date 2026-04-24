import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../application/devices_controller.dart';

class ClaimPairingDialog extends ConsumerStatefulWidget {
  const ClaimPairingDialog({super.key});

  @override
  ConsumerState<ClaimPairingDialog> createState() => _ClaimPairingDialogState();
}

class _ClaimPairingDialogState extends ConsumerState<ClaimPairingDialog> {
  final _codeCtrl = TextEditingController();
  String? _deviceId;
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim().replaceAll(' ', '').replaceAll('-', '');
    if (code.length != 6 || _deviceId == null) {
      setState(() => _error = 'Code 6 chiffres + device requis');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(pairingRepositoryProvider).claim(
        code: code, deviceId: _deviceId!,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ref.invalidate(devicesListProvider);
      }
    } on AppException catch (e) {
      setState(() => _error = '${e.message} — ${e.cause}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(devicesListProvider);
    return AlertDialog(
      title: const Text('Appairer un appareil'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Code affiché sur la tablette',
                hintText: '482193',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            devicesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Erreur: $e'),
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _deviceId,
                decoration: const InputDecoration(labelText: 'Rattacher à l\'appareil'),
                items: [
                  for (final d in list)
                    DropdownMenuItem(value: d.id, child: Text(d.name)),
                ],
                onChanged: (v) => setState(() => _deviceId = v),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Appairer'),
        ),
      ],
    );
  }

  @override
  void dispose() { _codeCtrl.dispose(); super.dispose(); }
}
