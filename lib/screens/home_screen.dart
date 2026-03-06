import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/feed_provider.dart';
import '../providers/websocket_provider.dart';
import '../widgets/content_row.dart';
import '../widgets/video_card.dart';
import '../widgets/adaptive_layout.dart';
import '../config/theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize WebSocket connection
    ref.watch(webSocketConnectionProvider);

    final continueWatching = ref.watch(continueWatchingProvider);
    final newEpisodes = ref.watch(newEpisodesProvider);
    final recentlyAdded = ref.watch(recentlyAddedProvider);
    final isTv = AdaptiveLayout.isTv(context);

    void refresh() {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(newEpisodesProvider);
      ref.invalidate(recentlyAddedProvider);
    }

    Widget body = CustomScrollView(
      slivers: [
        if (!isTv)
          const SliverAppBar(
            floating: true,
            title: Row(
              children: [
                Icon(
                  Icons.rss_feed,
                  color: NullFeedTheme.primaryColor,
                  size: 28,
                ),
                SizedBox(width: 8),
                Text('NullFeed'),
              ],
            ),
            backgroundColor: NullFeedTheme.backgroundColor,
          )
        else
          // TV: slim top padding + refresh button
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(60, 16, 60, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _TVActionButton(
                    icon: Icons.refresh,
                    label: 'Refresh',
                    onSelect: refresh,
                  ),
                ],
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              continueWatching.when(
                data: (items) {
                  if (items.isEmpty) return const SizedBox.shrink();
                  return ContentRow(
                    title: 'Continue Watching',
                    children: items
                        .map(
                          (item) => VideoCard(
                            video: item.video,
                            channel: item.channel,
                            showProgress: true,
                          ),
                        )
                        .toList(),
                  );
                },
                loading: () => const ContentRow(
                  title: 'Continue Watching',
                  isLoading: true,
                  children: [],
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
              newEpisodes.when(
                data: (items) {
                  if (items.isEmpty) return const SizedBox.shrink();
                  return ContentRow(
                    title: 'New Episodes',
                    children: items
                        .map(
                          (item) => VideoCard(
                            video: item.video,
                            channel: item.channel,
                          ),
                        )
                        .toList(),
                  );
                },
                loading: () => const ContentRow(
                  title: 'New Episodes',
                  isLoading: true,
                  children: [],
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
              recentlyAdded.when(
                data: (items) {
                  if (items.isEmpty) return const SizedBox.shrink();
                  return ContentRow(
                    title: 'Recently Added',
                    children: items
                        .map(
                          (item) => VideoCard(
                            video: item.video,
                            channel: item.channel,
                          ),
                        )
                        .toList(),
                  );
                },
                loading: () => const ContentRow(
                  title: 'Recently Added',
                  isLoading: true,
                  children: [],
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
              // Empty state
              if (continueWatching.value?.isEmpty == true &&
                  newEpisodes.value?.isEmpty == true &&
                  recentlyAdded.value?.isEmpty == true)
                const _EmptyHomeState(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );

    // On mobile, wrap with RefreshIndicator
    if (!isTv) {
      body = RefreshIndicator(
        color: NullFeedTheme.primaryColor,
        onRefresh: () async => refresh(),
        child: body,
      );
    }

    return Scaffold(body: body);
  }
}

// ---------------------------------------------------------------------------
// TV action button — focusable inline button for TV UI
// ---------------------------------------------------------------------------

class _TVActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onSelect;

  const _TVActionButton({
    required this.icon,
    required this.label,
    required this.onSelect,
  });

  @override
  State<_TVActionButton> createState() => _TVActionButtonState();
}

class _TVActionButtonState extends State<_TVActionButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: _isFocused
                ? NullFeedTheme.primaryColor.withValues(alpha: 0.2)
                : NullFeedTheme.cardColor,
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
                color: _isFocused
                    ? NullFeedTheme.primaryColor
                    : NullFeedTheme.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: _isFocused
                      ? NullFeedTheme.primaryColor
                      : NullFeedTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHomeState extends StatelessWidget {
  const _EmptyHomeState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.subscriptions_outlined,
              size: 64,
              color: NullFeedTheme.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'Your feed is empty',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Subscribe to channels in the Library tab to start building your feed.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
