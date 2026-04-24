import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  static const _destinations = [
    _Dest('/establishments', Icons.store_outlined, 'Établissements'),
    _Dest('/devices', Icons.tv_outlined, 'Appareils'),
    _Dest('/managers', Icons.people_outline, 'Gérants'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = _destinations.indexWhere(
      (d) => location.startsWith(d.path),
    );
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected < 0 ? 0 : selected,
            onDestinationSelected: (i) => context.go(_destinations[i].path),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
            trailing: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Se déconnecter',
                onPressed: () async {
                  await ref.read(authRepositoryProvider).signOut();
                },
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
