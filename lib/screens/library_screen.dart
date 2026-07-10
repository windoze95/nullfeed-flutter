import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/channel.dart';
import '../providers/channel_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_ui.dart';
import '../widgets/channel_card.dart';
import '../widgets/adaptive_layout.dart';
import '../config/theme.dart';

enum _LibrarySort { alphabetical, recentlyUpdated }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.showAddChannel = false});

  final bool showAddChannel;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  _LibrarySort _sort = _LibrarySort.recentlyUpdated;

  @override
  void initState() {
    super.initState();
    if (widget.showAddChannel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showSubscribeDialog();
      });
    }
  }

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
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: Text(channel.name),
              subtitle: const Text('Open channel'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/channel/${channel.id}');
              },
            ),
            if (channel.isSubscribed)
              ListTile(
                leading: const Icon(
                  Icons.remove_circle_outline_rounded,
                  color: NullFeedTheme.errorColor,
                ),
                title: const Text('Unsubscribe'),
                subtitle: const Text('Remove from this profile\'s Library'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmUnsubscribe(channel);
                },
              )
            else
              ListTile(
                leading: const Icon(
                  Icons.add_circle_outline_rounded,
                  color: NullFeedTheme.primaryColor,
                ),
                title: const Text('Subscribe'),
                subtitle: const Text('Add to this profile\'s Library'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _subscribeToExistingChannel(channel);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _subscribeToExistingChannel(Channel channel) async {
    try {
      await ref
          .read(channelsProvider.notifier)
          .subscribe(channel.youtubeChannelId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${channel.name} to your Library')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _confirmUnsubscribe(Channel channel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Unsubscribe from ${channel.name}?'),
        content: const Text(
          'This removes the channel from this profile\'s Library. New uploads '
          'will no longer appear in Home.',
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
      await ref.read(channelsProvider.notifier).unsubscribe(channel.id);
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
    final channels = ref.watch(subscribedChannelsProvider);
    final padding = AdaptiveLayout.contentPadding(context);

    return Scaffold(
      body: AppBackdrop(
        child: RefreshIndicator(
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
                title: const Text('Channels'),
                actions: [
                  PopupMenuButton<_LibrarySort>(
                    icon: const Icon(Icons.sort_rounded),
                    tooltip: 'Sort channels',
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
                ],
              ),
              SliverToBoxAdapter(
                child: PageIntro(
                  eyebrow: 'Your collection',
                  title: 'Channels you follow',
                  description:
                      'This Library belongs to the current profile. Add a '
                      'channel once and new uploads will surface automatically.',
                  bottom: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      QuickActionButton(
                        icon: Icons.add_rounded,
                        label: 'Add channel',
                        onTap: _showSubscribeDialog,
                        emphasized: true,
                      ),
                      QuickActionButton(
                        icon: Icons.search_rounded,
                        label: 'Search videos',
                        onTap: () => context.push('/search'),
                      ),
                      QuickActionButton(
                        icon: Icons.playlist_play_rounded,
                        label: 'Watch later',
                        onTap: () => context.push('/queue'),
                      ),
                    ],
                  ),
                ),
              ),
              channels.when(
                data: (channelList) {
                  if (channelList.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: padding),
                        child: EmptyStatePanel(
                          icon: Icons.video_library_outlined,
                          eyebrow: 'Start your Library',
                          title: 'Follow your first channel',
                          description:
                              'Paste a YouTube channel link or @handle. '
                              'NullFeed will add it to this profile and watch '
                              'for new uploads.',
                          steps: const [
                            'Copy a channel URL or @handle from YouTube.',
                            'Add it here — NullFeed handles the rest.',
                          ],
                          primaryAction: _showSubscribeDialog,
                          primaryLabel: 'Add your first channel',
                        ),
                      ),
                    );
                  }
                  final sorted = _sortedChannels(channelList);
                  return SliverPadding(
                    padding: EdgeInsets.fromLTRB(padding, 4, padding, padding),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 400,
                            childAspectRatio: 16 / 10,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
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
                error: (error, _) => SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: padding),
                    child: EmptyStatePanel(
                      icon: Icons.cloud_off_rounded,
                      eyebrow: 'Library unavailable',
                      title: 'We couldn\'t load your channels',
                      description: '$error',
                      primaryAction: () =>
                          ref.read(channelsProvider.notifier).load(),
                      primaryLabel: 'Try again',
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
    if (_isSubmitting) return;
    if (url.isEmpty) {
      setState(() {
        _errorText = 'Enter a channel URL, @handle, or channel ID.';
      });
      return;
    }

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
        const SnackBar(content: Text('Added to Library — checking uploads…')),
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
      title: const Text('Add a YouTube channel'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paste a channel URL, @handle, or channel ID. It will be added to '
            'this profile\'s Library, and new uploads will appear automatically.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _urlController,
            autofocus: true,
            enabled: !_isSubmitting,
            autocorrect: false,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.url],
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Channel link or @handle',
              hintText: 'youtube.com/@channel',
              helperText: 'Example: @mkbhd or a youtube.com/channel/... link',
              prefixIcon: Icon(Icons.link_rounded),
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
              : const Text('Add to Library'),
        ),
      ],
    );
  }
}
