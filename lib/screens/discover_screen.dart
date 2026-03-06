import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/discover_provider.dart';
import '../providers/channel_provider.dart';
import '../config/theme.dart';
import '../widgets/adaptive_layout.dart';

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommendations = ref.watch(discoverProvider);
    final isTv = AdaptiveLayout.isTv(context);
    final padding = AdaptiveLayout.contentPadding(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          if (!isTv)
            SliverAppBar(
              floating: true,
              title: const Text('Discover'),
              backgroundColor: NullFeedTheme.backgroundColor,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      ref.read(discoverProvider.notifier).refresh(),
                ),
              ],
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 16, padding, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _TVRefreshButton(
                      onSelect: () =>
                          ref.read(discoverProvider.notifier).refresh(),
                    ),
                  ],
                ),
              ),
            ),
          recommendations.when(
            data: (recs) {
              if (recs.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.explore_outlined,
                          size: 64,
                          color: NullFeedTheme.textMuted,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No recommendations yet',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Subscribe to more channels to get AI-powered suggestions.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () =>
                              ref.read(discoverProvider.notifier).refresh(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: EdgeInsets.all(padding),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final rec = recs[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _RecommendationCard(
                        channelName: rec.channelName,
                        reasoning: rec.reasoning,
                        onDismiss: () =>
                            ref.read(discoverProvider.notifier).dismiss(rec.id),
                        onSubscribe: rec.youtubeChannelId != null
                            ? () {
                                ref
                                    .read(channelsProvider.notifier)
                                    .subscribe(rec.youtubeChannelId!);
                                ref
                                    .read(discoverProvider.notifier)
                                    .dismiss(rec.id);
                              }
                            : null,
                      ),
                    );
                  }, childCount: recs.length),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: NullFeedTheme.errorColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load recommendations',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () =>
                          ref.read(discoverProvider.notifier).load(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recommendation card with focus support
// ---------------------------------------------------------------------------

class _RecommendationCard extends StatefulWidget {
  final String channelName;
  final String reasoning;
  final VoidCallback onDismiss;
  final VoidCallback? onSubscribe;

  const _RecommendationCard({
    required this.channelName,
    required this.reasoning,
    required this.onDismiss,
    this.onSubscribe,
  });

  @override
  State<_RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends State<_RecommendationCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _isFocused = f),
      skipTraversal: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: _isFocused
              ? Border.all(color: NullFeedTheme.primaryColor, width: 2)
              : null,
        ),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: NullFeedTheme.primaryColor.withValues(
                          alpha: 0.2,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Center(
                        child: Text(
                          widget.channelName.isNotEmpty
                              ? widget.channelName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: NullFeedTheme.primaryColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        widget.channelName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.reasoning,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: widget.onDismiss,
                      child: const Text('Dismiss'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: widget.onSubscribe,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Subscribe'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TV refresh button
// ---------------------------------------------------------------------------

class _TVRefreshButton extends StatefulWidget {
  final VoidCallback onSelect;
  const _TVRefreshButton({required this.onSelect});

  @override
  State<_TVRefreshButton> createState() => _TVRefreshButtonState();
}

class _TVRefreshButtonState extends State<_TVRefreshButton> {
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
                Icons.refresh,
                color: _isFocused
                    ? NullFeedTheme.primaryColor
                    : NullFeedTheme.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Refresh',
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
