import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/current_profile_provider.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final destinations = <_Dest>[
      const _Dest('/establishments', Icons.store_outlined, 'Établissements'),
      const _Dest('/devices', Icons.tv_outlined, 'Appareils'),
      const _Dest('/media', Icons.perm_media_outlined, 'Médias'),
      const _Dest('/playlists', Icons.queue_music_outlined, 'Playlists'),
      if (isAdmin)
        const _Dest('/managers', Icons.people_outline, 'Gérants'),
      if (isAdmin)
        const _Dest('/audit', Icons.history_outlined, 'Audit'),
    ];
    final selected = destinations.indexWhere(
      (d) => location.startsWith(d.path),
    );
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected < 0 ? 0 : selected,
            onDestinationSelected: (i) => context.go(destinations[i].path),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
            trailing: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isAdmin ? 'admin' : 'gérant',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Se déconnecter',
                    onPressed: () async {
                      await ref.read(authRepositoryProvider).signOut();
                    },
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Dest {
  const _Dest(this.path, this.icon, this.label);
  final String path;
  final IconData icon;
  final String label;
}
