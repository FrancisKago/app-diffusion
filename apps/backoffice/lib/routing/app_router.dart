import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/devices/presentation/device_detail_screen.dart';
import '../features/devices/presentation/device_form_screen.dart';
import '../features/devices/presentation/devices_list_screen.dart';
import '../features/establishments/presentation/establishment_form_screen.dart';
import '../features/establishments/presentation/establishments_list_screen.dart';
import '../features/managers/presentation/manager_form_screen.dart';
import '../features/managers/presentation/managers_list_screen.dart';
import '../features/media/presentation/media_library_screen.dart';
import '../features/playlists/presentation/playlist_editor_screen.dart';
import '../features/playlists/presentation/playlists_list_screen.dart';
import '../shared_widgets/app_shell.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/establishments',
    redirect: (context, state) {
      final session = ref.read(currentSessionProvider);
      final loggedIn = session != null;
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/establishments';
      return null;
    },
    refreshListenable: _AuthRefreshNotifier(ref),
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/establishments',
            builder: (_, __) => const EstablishmentsListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, __) => const EstablishmentFormScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (_, s) => EstablishmentFormScreen(
                  establishmentId: s.pathParameters['id'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/devices',
            builder: (_, __) => const DevicesListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, __) => const DeviceFormScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (_, s) => DeviceDetailScreen(
                  deviceId: s.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/media',
            builder: (_, __) => const MediaLibraryScreen(),
          ),
          GoRoute(
            path: '/playlists',
            builder: (_, __) => const PlaylistsListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => PlaylistEditorScreen(
                  playlistId: s.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/managers',
            builder: (_, __) => const ManagersListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, __) => const ManagerFormScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _sub = ref.listen<AsyncValue<dynamic>>(
      authStateProvider,
      (_, __) => notifyListeners(),
    );
  }
  late final ProviderSubscription<AsyncValue<dynamic>> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
