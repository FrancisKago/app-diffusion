import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

import '../application/establishments_controller.dart';

class EstablishmentFormScreen extends ConsumerStatefulWidget {
  const EstablishmentFormScreen({this.establishmentId, super.key});

  final String? establishmentId;
  bool get isEditing => establishmentId != null;

  @override
  ConsumerState<EstablishmentFormScreen> createState() =>
      _EstablishmentFormScreenState();
}

class _EstablishmentFormScreenState
    extends ConsumerState<EstablishmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _tzCtrl = TextEditingController(text: 'Africa/Yaounde');
  bool _saving = false;
  String? _error;
  Establishment? _loaded;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) _load();
  }

  Future<void> _load() async {
    final list = await ref.read(establishmentsListProvider.future);
    final found = list.where((x) => x.id == widget.establishmentId);
    if (found.isEmpty) return;
    final e = found.first;
    if (!mounted) return;
    setState(() {
      _loaded = e;
      _nameCtrl.text = e.name;
      _tzCtrl.text = e.timezone;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(establishmentsRepositoryProvider);
      if (widget.isEditing) {
        await repo.update(
          id: widget.establishmentId!,
          name: _nameCtrl.text.trim(),
          timezone: _tzCtrl.text.trim(),
        );
      } else {
        await repo.create(
          name: _nameCtrl.text.trim(),
          timezone: _tzCtrl.text.trim(),
        );
      }
      ref.invalidate(establishmentsListProvider);
      if (mounted) context.go('/establishments');
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Text('Supprimer "${_loaded?.name}" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(establishmentsRepositoryProvider).delete(widget.establishmentId!);
      ref.invalidate(establishmentsListProvider);
      if (mounted) context.go('/establishments');
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Modifier' : 'Nouvel établissement'),
        actions: [
          if (widget.isEditing)
            IconButton(icon: const Icon(Icons.delete), onPressed: _delete),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tzCtrl,
                decoration: const InputDecoration(
                  labelText: 'Fuseau horaire',
                  helperText: 'Ex: Africa/Yaounde, Europe/Paris, UTC',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Fuseau requis' : null,
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _tzCtrl.dispose();
    super.dispose();
  }
}
