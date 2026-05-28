import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

import '../../auth/application/current_profile_provider.dart';
import '../application/managers_controller.dart';
import '../data/managers_repository.dart';

class ManagersListScreen extends ConsumerWidget {
  const ManagersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(managersListProvider);
    final isAdmin = ref.watch(isAdminProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gérants'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(managersListProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/managers/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau gérant'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Aucun gérant.'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final m = list[i];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(m.profile.fullName),
                subtitle: Text(
                  '${m.establishmentIds.length} établissement(s)',
                ),
                trailing: isAdmin
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Supprimer',
                        onPressed: () => _confirmDeleteManager(context, ref, m),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> _confirmDeleteManager(
  BuildContext context,
  WidgetRef ref,
  ManagerWithEstablishments manager,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Supprimer ce gérant ?'),
      content: Text(
        'Gérant : "${manager.profile.fullName}".\n\n'
        'Son compte de connexion et toutes ses affectations '
        "d'établissements seront supprimés. Cette action est irréversible.",
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
    await ref.read(managersRepositoryProvider).delete(manager.profile.id);
    ref.invalidate(managersListProvider);
  } on AppException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${e.message} — ${e.cause}')),
    );
  }
}
