import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

import '../../auth/application/current_profile_provider.dart';
import '../application/establishments_controller.dart';

class EstablishmentsListScreen extends ConsumerWidget {
  const EstablishmentsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(establishmentsListProvider);
    final isAdmin = ref.watch(isAdminProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Établissements'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(establishmentsListProvider),
          ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/establishments/new'),
              icon: const Icon(Icons.add),
              label: const Text('Nouvel établissement'),
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Aucun établissement.'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final e = list[i];
              return ListTile(
                title: Text(e.name),
                subtitle: Text('Fuseau : ${e.timezone}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isAdmin)
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Supprimer',
                        onPressed: () =>
                            _confirmDeleteEstablishment(context, ref, e),
                      ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => context.go('/establishments/${e.id}'),
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> _confirmDeleteEstablishment(
  BuildContext context,
  WidgetRef ref,
  Establishment establishment,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Supprimer cet établissement ?'),
      content: Text(
        'Établissement : "${establishment.name}".\n\n'
        'Tous les devices, playlists et médias liés seront détruits '
        '(cascade DB). Cette action est irréversible.',
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
    await ref
        .read(establishmentsRepositoryProvider)
        .delete(establishment.id);
    ref.invalidate(establishmentsListProvider);
  } on AppException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${e.message} — ${e.cause}')),
    );
  }
}
