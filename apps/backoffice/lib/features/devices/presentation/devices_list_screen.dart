import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/devices_controller.dart';
import 'claim_pairing_dialog.dart';

class DevicesListScreen extends ConsumerWidget {
  const DevicesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(devicesListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appareils'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(devicesListProvider),
          ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Appairer par code',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const ClaimPairingDialog(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/devices/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouvel appareil'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Aucun appareil.'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = list[i];
              return ListTile(
                leading: Icon(
                  d.orientation.dbValue == 'portrait'
                      ? Icons.stay_current_portrait
                      : Icons.tv_outlined,
                ),
                title: Text(d.name),
                subtitle: Text('${d.orientation.dbValue} · ${d.id.substring(0, 8)}…'),
              );
            },
          );
        },
      ),
    );
  }
}
