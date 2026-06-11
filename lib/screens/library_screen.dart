import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/channel.dart';
import '../providers/channel_provider.dart';
import '../services/api_service.dart';
import '../widgets/channel_card.dart';
import '../widgets/adaptive_layout.dart';
import '../config/theme.dart';

enum _LibrarySort { alphabetical, recentlyUpdated }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  _LibrarySort _sort = _LibrarySort.recentlyUpdated;

  void _showSubscribeDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => const _SubscribeDialog(),
    );
  }

  List<Channel> _sortedChannels(List<Channel> channels) {
    final sorted = [...channels];
    switch (_sort) {
      case _LibrarySort.alphabetical:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _LibrarySort.recentlyUpdated:
        sorted.sort((a, b) {
          final aTime = a.lastCheckedAt;
          final bTime = b.lastCheckedAt;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });
    }
    return sorted;
  }

  void _showChannelMenu(Channel channel) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NullFeedTheme.cardColor,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(channel.name),
              subtitle: const Text('Open channel'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/channel/${channel.id}');
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.remove_circle_outline,
                color: NullFeedTheme.errorColor,
              ),
              title: const Text('Unsubscribe'),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmUnsubscribe(channel);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmUnsubscribe(Channel channel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NullFeedTheme.cardColor,
        title: Text('Unsubscribe from ${channel.name}?'),
        content: const Text(
          'New videos from this channel will no longer appear in your feed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Unsubscribe',
              style: TextStyle(color: NullFeedTheme.errorColor),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      // Call the API directly so a failure never wipes the loaded list.
      await ref.read(apiServiceProvider).unsubscribeFromChannel(channel.id);
      if (!mounted) return;
      await ref.read(channelsProvider.notifier).load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unsubscribed from ${channel.name}')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final channels = ref.watch(channelsProvider);
    final padding = AdaptiveLayout.contentPadding(context);

    return Scaffold(
      body: RefreshIndicator(
        color: NullFeedTheme.primaryColor,
        onRefresh: () {
          // Kick a server-side poll for new uploads alongside the reload.
          unawaited(
            ref.read(apiServiceProvider).pollAllChannels().catchError((_) {}),
          );
          return ref.read(channelsProvider.notifier).load();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              title: const Text('Library'),
              backgroundColor: NullFeedTheme.backgroundColor,
              actions: [
                PopupMenuButton<_LibrarySort>(
                  icon: const Icon(Icons.sort),
                  tooltip: 'Sort',
                  initialValue: _sort,
                  onSelected: (value) => setState(() => _sort = value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _LibrarySort.recentlyUpdated,
                      child: Text('Recently updated'),
                    ),
                    PopupMenuItem(
                      value: _LibrarySort.alphabetical,
                      child: Text('A–Z'),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _showSubscribeDialog,
                ),
              ],
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
                            'Tap + to subscribe to a YouTube channel',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final sorted = _sortedChannels(channelList);
                return SliverPadding(
                  padding: EdgeInsets.all(padding),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 400,
                          childAspectRatio: 16 / 10,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final channel = sorted[index];
                      return ChannelCard(
                        channel: channel,
                        onTap: () => context.push('/channel/${channel.id}'),
                        onMenu: () => _showChannelMenu(channel),
                      );
                    }, childCount: sorted.length),
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          '$error',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
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
      ),
    );
  }
}

/// Subscribe dialog with in-dialog loading and inline error handling.
/// The dialog stays open on failure so the URL isn't lost.
class _SubscribeDialog extends ConsumerStatefulWidget {
  const _SubscribeDialog();

  @override
  ConsumerState<_SubscribeDialog> createState() => _SubscribeDialogState();
}

class _SubscribeDialogState extends ConsumerState<_SubscribeDialog> {
  final _urlController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      // Call the API directly so a failure never wipes the loaded list.
      await ref.read(apiServiceProvider).subscribeToChannel(url);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final channelsNotifier = ref.read(channelsProvider.notifier);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Subscribed — fetching videos…')),
      );
      unawaited(channelsNotifier.load());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorText = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorText = 'Failed to subscribe: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: NullFeedTheme.cardColor,
      title: const Text('Subscribe to Channel'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlController,
            autofocus: true,
            enabled: !_isSubmitting,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              hintText: 'YouTube channel URL or ID',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          if (_errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _errorText!,
                style: const TextStyle(
                  color: NullFeedTheme.errorColor,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Subscribe'),
        ),
      ],
    );
  }
}
