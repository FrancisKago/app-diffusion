import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

import '../../establishments/application/establishments_controller.dart';
import '../application/devices_controller.dart';

class DeviceFormScreen extends ConsumerStatefulWidget {
  const DeviceFormScreen({super.key});

  @override
  ConsumerState<DeviceFormScreen> createState() => _DeviceFormScreenState();
}

class _DeviceFormScreenState extends ConsumerState<DeviceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  String? _establishmentId;
  DeviceOrientation _orientation = DeviceOrientation.landscape;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_establishmentId == null) {
      setState(() => _error = 'Établissement requis');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(devicesRepositoryProvider).create(
        establishmentId: _establishmentId!,
        name: _nameCtrl.text.trim(),
        orientation: _orientation,
      );
      ref.invalidate(devicesListProvider);
      if (mounted) context.go('/devices');
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final establishmentsAsync = ref.watch(establishmentsListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvel appareil')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 16),
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
              Text('Orientation', style: Theme.of(context).textTheme.titleMedium),
              RadioListTile<DeviceOrientation>(
                title: const Text('Paysage (TV)'),
                value: DeviceOrientation.landscape,
                groupValue: _orientation,
                onChanged: (v) => setState(() => _orientation = v!),
              ),
              RadioListTile<DeviceOrientation>(
                title: const Text('Portrait (menu vertical)'),
                value: DeviceOrientation.portrait,
                groupValue: _orientation,
                onChanged: (v) => setState(() => _orientation = v!),
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Créer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }
}
