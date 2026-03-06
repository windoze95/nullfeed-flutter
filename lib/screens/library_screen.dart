import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/channel_provider.dart';
import '../widgets/channel_card.dart';
import '../widgets/adaptive_layout.dart';
import '../config/theme.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  void _showSubscribeDialog() {
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NullFeedTheme.cardColor,
        title: const Text('Subscribe to Channel'),
        content: TextField(
          controller: urlController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'YouTube channel URL or ID',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isNotEmpty) {
                ref.read(channelsProvider.notifier).subscribe(url);
                Navigator.pop(context);
              }
            },
            child: const Text('Subscribe'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final channels = ref.watch(channelsProvider);
    final isTv = AdaptiveLayout.isTv(context);
    final padding = AdaptiveLayout.contentPadding(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          if (!isTv)
            SliverAppBar(
              floating: true,
              title: const Text('Library'),
              backgroundColor: NullFeedTheme.backgroundColor,
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _showSubscribeDialog,
                ),
              ],
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 16, padding, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [_TVAddButton(onSelect: _showSubscribeDialog)],
                ),
              ),
            ),
          channels.when(
            data: (channelList) {
              if (channelList.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.video_library_outlined,
                          size: 64,
                          color: NullFeedTheme.textMuted,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No channels yet',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isTv
                              ? 'Select "Add Channel" to subscribe'
                              : 'Tap + to subscribe to a YouTube channel',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: EdgeInsets.all(padding),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: isTv ? 500 : 400,
                    childAspectRatio: 16 / 10,
                    crossAxisSpacing: isTv ? 20 : 12,
                    mainAxisSpacing: isTv ? 20 : 12,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final channel = channelList[index];
                    return ChannelCard(
                      channel: channel,
                      onTap: () => context.push('/channel/${channel.id}'),
                    );
                  }, childCount: channelList.length),
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
                      'Failed to load channels',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () =>
                          ref.read(channelsProvider.notifier).load(),
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
// TV add channel button
// ---------------------------------------------------------------------------

class _TVAddButton extends StatefulWidget {
  final VoidCallback onSelect;
  const _TVAddButton({required this.onSelect});

  @override
  State<_TVAddButton> createState() => _TVAddButtonState();
}

class _TVAddButtonState extends State<_TVAddButton> {
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
                Icons.add,
                color: _isFocused
                    ? NullFeedTheme.primaryColor
                    : NullFeedTheme.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Add Channel',
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
