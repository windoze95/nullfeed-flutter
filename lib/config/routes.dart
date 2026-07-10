import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
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
import '../widgets/adaptive_layout.dart';
import '../widgets/app_ui.dart';
import '../widgets/profile_avatar.dart';
import 'theme.dart';

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
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: LibraryScreen(
                showAddChannel: state.uri.queryParameters['add'] == '1',
              ),
            ),
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
    _NavDest('/home', Icons.home_outlined, Icons.home_rounded, 'Home'),
    _NavDest(
      '/library',
      Icons.subscriptions_outlined,
      Icons.subscriptions_rounded,
      'Channels',
    ),
    _NavDest(
      '/discover',
      Icons.auto_awesome_outlined,
      Icons.auto_awesome_rounded,
      'Explore',
    ),
    _NavDest(
      '/downloads',
      Icons.download_for_offline_outlined,
      Icons.download_for_offline_rounded,
      'Saved',
    ),
    _NavDest(
      '/settings',
      Icons.person_outline_rounded,
      Icons.person_rounded,
      'You',
    ),
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
    final authState = ref.watch(authStateProvider);
    final serverBaseUrl = ref.watch(settingsProvider).serverUrl;

    // Wide viewports get a persistent, labelled product sidebar. Phones keep
    // a compact NavigationBar with the same plain-language destinations.
    if (AdaptiveLayout.isWide(context)) {
      return Scaffold(
        backgroundColor: NullFeedTheme.backgroundColor,
        body: AppBackdrop(
          child: Row(
            children: [
              _DesktopSidebar(
                destinations: destinations,
                selectedIndex: selectedIndex,
                onSelected: (index) => context.go(destinations[index].route),
                onSearch: () => context.push('/search'),
                onQueue: () => context.push('/queue'),
                profileName: authState.currentUser?.displayName,
                profileAvatarUrl: authState.currentUser?.avatarUrl,
                serverBaseUrl: serverBaseUrl,
              ),
              Expanded(child: child),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: NullFeedTheme.backgroundColor,
      body: AppBackdrop(child: child),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: NullFeedTheme.dividerColor)),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) =>
              context.go(destinations[index].route),
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.activeIcon),
                label: d.label,
                tooltip: d.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.onSearch,
    required this.onQueue,
    this.profileName,
    this.profileAvatarUrl,
    this.serverBaseUrl,
  });

  final List<_NavDest> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onSearch;
  final VoidCallback onQueue;
  final String? profileName;
  final String? profileAvatarUrl;
  final String? serverBaseUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: NullFeedTheme.surfaceColor.withValues(alpha: 0.86),
        border: const Border(
          right: BorderSide(color: NullFeedTheme.dividerColor),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: NullFeedMark(compact: true),
              ),
              const SizedBox(height: 36),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'YOUR SPACE',
                  style: TextStyle(
                    color: NullFeedTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.25,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < destinations.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: _SidebarDestination(
                    destination: destinations[index],
                    selected: selectedIndex == index,
                    onTap: () => onSelected(index),
                  ),
                ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 18),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'QUICK ACTIONS',
                  style: TextStyle(
                    color: NullFeedTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.25,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _SidebarShortcut(
                icon: Icons.search_rounded,
                label: 'Search everything',
                onTap: onSearch,
              ),
              _SidebarShortcut(
                icon: Icons.playlist_play_rounded,
                label: 'Watch later',
                onTap: onQueue,
              ),
              const Spacer(),
              if (profileName != null)
                Material(
                  color: NullFeedTheme.cardColor,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: NullFeedTheme.borderColor),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onSelected(
                      destinations.indexWhere((d) => d.route == '/settings'),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          ProfileAvatar(
                            name: profileName!,
                            avatarUrl: profileAvatarUrl,
                            serverBaseUrl: serverBaseUrl,
                            size: 34,
                            borderRadius: 11,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profileName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: NullFeedTheme.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Text(
                                  'Profile & settings',
                                  style: TextStyle(
                                    color: NullFeedTheme.textMuted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarDestination extends StatelessWidget {
  const _SidebarDestination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _NavDest destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? NullFeedTheme.selectionFill : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                selected ? destination.activeIcon : destination.icon,
                size: 21,
                color: selected
                    ? NullFeedTheme.primaryColor
                    : NullFeedTheme.textMuted,
              ),
              const SizedBox(width: 12),
              Text(
                destination.label,
                style: TextStyle(
                  color: selected
                      ? NullFeedTheme.textPrimary
                      : NullFeedTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              if (selected) ...[
                const Spacer(),
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: NullFeedTheme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarShortcut extends StatelessWidget {
  const _SidebarShortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 19, color: NullFeedTheme.textMuted),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: NullFeedTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
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
