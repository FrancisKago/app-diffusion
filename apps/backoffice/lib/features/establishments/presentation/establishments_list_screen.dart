import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/establishments/${e.id}'),
              );
            },
          );
        },
      ),
    );
  }
}
