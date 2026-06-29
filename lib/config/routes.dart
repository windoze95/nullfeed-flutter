import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/websocket_provider.dart';
import '../screens/profile_picker_screen.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/discover_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/channel_detail_screen.dart';
import '../screens/video_player_screen.dart';
import '../screens/search_screen.dart';
import '../screens/queue_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Bridges Riverpod auth changes to GoRouter's [refreshListenable] so the
/// router instance itself is never recreated on auth changes.
class GoRouterRefreshNotifier extends ChangeNotifier {
  GoRouterRefreshNotifier(Ref ref) {
    ref.listen<String?>(
      authStateProvider.select((state) => state.currentUser?.id),
      (previous, next) => notifyListeners(),
    );
  }
}

final _routerRefreshProvider = Provider<GoRouterRefreshNotifier>((ref) {
  final notifier = GoRouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  // The router is created once; auth changes only trigger a redirect pass
  // via refreshListenable instead of rebuilding the whole router.
  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: ref.watch(_routerRefreshProvider),
    redirect: (context, state) {
      final isAuthenticated = ref.read(authStateProvider).currentUser != null;
      final isOnProfilePicker = state.matchedLocation == '/';

      if (!isAuthenticated && !isOnProfilePicker) {
        return '/';
      }
      if (isAuthenticated && isOnProfilePicker) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ProfilePickerScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => _ScaffoldWithNav(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/library',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: LibraryScreen()),
          ),
          GoRoute(
            path: '/discover',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DiscoverScreen()),
          ),
          GoRoute(
            path: '/downloads',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DownloadsScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/channel/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            ChannelDetailScreen(channelId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/player/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            VideoPlayerScreen(videoId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/search',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: '/queue',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const QueueScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _ScaffoldWithNav extends ConsumerWidget {
  final Widget child;
  const _ScaffoldWithNav({required this.child});

  static const List<_NavDest> _allDestinations = [
    _NavDest('/home', Icons.home_outlined, Icons.home, 'Home'),
    _NavDest(
      '/library',
      Icons.video_library_outlined,
      Icons.video_library,
      'Library',
    ),
    _NavDest('/discover', Icons.explore_outlined, Icons.explore, 'Discover'),
    _NavDest(
      '/downloads',
      Icons.offline_pin_outlined,
      Icons.offline_pin,
      'Offline',
    ),
    _NavDest('/settings', Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  /// The Offline tab is on-device storage, which the web build doesn't have, so
  /// it's dropped on web.
  static List<_NavDest> get _destinations => kIsWeb
      ? _allDestinations.where((d) => d.route != '/downloads').toList()
      : _allDestinations;

  static int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _destinations.indexWhere((d) => location.startsWith(d.route));
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the WebSocket connection alive on every tab (not just Home) so
    // events keep flowing and a Settings-triggered invalidate reconnects
    // immediately instead of waiting for the Home tab to be visited.
    ref.watch(webSocketConnectionProvider);
    final destinations = _destinations;
    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (index) => context.go(destinations[index].route),
        type: BottomNavigationBarType.fixed,
        items: [
          for (final d in destinations)
            BottomNavigationBarItem(
              icon: Icon(d.icon),
              activeIcon: Icon(d.activeIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _NavDest {
  final String route;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavDest(this.route, this.icon, this.activeIcon, this.label);
}
