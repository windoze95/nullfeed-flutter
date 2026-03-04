import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/profile_picker_screen.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/discover_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/channel_detail_screen.dart';
import '../screens/video_player_screen.dart';
import '../widgets/adaptive_layout.dart';
import 'theme.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final isAuthenticated = authState.currentUser != null;
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
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/library',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: LibraryScreen(),
            ),
          ),
          GoRoute(
            path: '/discover',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DiscoverScreen(),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/channel/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ChannelDetailScreen(
          channelId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/player/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => VideoPlayerScreen(
          videoId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
});

class _ScaffoldWithNav extends StatelessWidget {
  final Widget child;
  const _ScaffoldWithNav({required this.child});

  static int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/library')) return 1;
    if (location.startsWith('/discover')) return 2;
    if (location.startsWith('/settings')) return 3;
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
        context.go('/settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    if (AdaptiveLayout.isTv(context)) {
      return Scaffold(
        backgroundColor: NullFeedTheme.backgroundColor,
        body: Column(
          children: [
            _TVTabBar(
              selectedIndex: selectedIndex,
              onTap: (index) => _onTap(context, index),
            ),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (index) => _onTap(context, index),
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
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TV top tab bar
// ---------------------------------------------------------------------------

class _TVTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _TVTabBar({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NullFeedTheme.surfaceColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.rss_feed,
                  color: NullFeedTheme.primaryColor, size: 36),
              const SizedBox(width: 12),
              const Text(
                'NullFeed',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: NullFeedTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 48),
              _TVTabItem(
                icon: Icons.home,
                label: 'Home',
                isSelected: selectedIndex == 0,
                onSelect: () => onTap(0),
                autofocus: selectedIndex == 0,
              ),
              const SizedBox(width: 8),
              _TVTabItem(
                icon: Icons.video_library,
                label: 'Library',
                isSelected: selectedIndex == 1,
                onSelect: () => onTap(1),
              ),
              const SizedBox(width: 8),
              _TVTabItem(
                icon: Icons.explore,
                label: 'Discover',
                isSelected: selectedIndex == 2,
                onSelect: () => onTap(2),
              ),
              const SizedBox(width: 8),
              _TVTabItem(
                icon: Icons.settings,
                label: 'Settings',
                isSelected: selectedIndex == 3,
                onSelect: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TVTabItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onSelect;
  final bool autofocus;

  const _TVTabItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onSelect,
    this.autofocus = false,
  });

  @override
  State<_TVTabItem> createState() => _TVTabItemState();
}

class _TVTabItemState extends State<_TVTabItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || widget.isSelected;

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: _isFocused
                ? NullFeedTheme.primaryColor.withValues(alpha: 0.2)
                : widget.isSelected
                    ? NullFeedTheme.primaryColor.withValues(alpha: 0.1)
                    : Colors.transparent,
            border: Border.all(
              color: _isFocused
                  ? NullFeedTheme.primaryColor
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                color: isHighlighted
                    ? NullFeedTheme.primaryColor
                    : NullFeedTheme.textMuted,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: isHighlighted
                      ? NullFeedTheme.primaryColor
                      : NullFeedTheme.textMuted,
                  fontSize: 18,
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
