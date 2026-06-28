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

  static int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/library')) return 1;
    if (location.startsWith('/discover')) return 2;
    if (location.startsWith('/downloads')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
      case 1:
        context.go('/library');
      case 2:
        context.go('/discover');
      case 3:
        context.go('/downloads');
      case 4:
        context.go('/settings');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the WebSocket connection alive on every tab (not just Home) so
    // events keep flowing and a Settings-triggered invalidate reconnects
    // immediately instead of waiting for the Home tab to be visited.
    ref.watch(webSocketConnectionProvider);
    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (index) => _onTap(context, index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.video_library_outlined),
            activeIcon: Icon(Icons.video_library),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.download_outlined),
            activeIcon: Icon(Icons.download),
            label: 'Downloads',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
