import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/channel_provider.dart';
import '../widgets/video_list_tile.dart';
import '../config/theme.dart';

class ChannelDetailScreen extends ConsumerWidget {
  final String channelId;
  const ChannelDetailScreen({super.key, required this.channelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelAsync = ref.watch(channelDetailProvider(channelId));
    final videosAsync = ref.watch(channelVideosProvider(channelId));

    return Scaffold(
      body: channelAsync.when(
        data: (channel) => CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              backgroundColor: NullFeedTheme.surfaceColor,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (channel.bannerUrl != null)
                      CachedNetworkImage(
                        imageUrl: channel.bannerUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: NullFeedTheme.cardColor,
                        ),
                      )
                    else
                      Container(color: NullFeedTheme.cardColor),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            NullFeedTheme.backgroundColor.withValues(alpha: 0.9),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (channel.avatarUrl != null)
                          CircleAvatar(
                            radius: 32,
                            backgroundImage:
                                CachedNetworkImageProvider(channel.avatarUrl!),
                          )
                        else
                          CircleAvatar(
                            radius: 32,
                            backgroundColor:
                                NullFeedTheme.primaryColor.withValues(alpha: 0.2),
                            child: Text(
                              channel.name.isNotEmpty
                                  ? channel.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: NullFeedTheme.primaryColor,
                              ),
                            ),
                          ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                channel.name,
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              if (channel.description != null &&
                                  channel.description!.isNotEmpty)
                                Text(
                                  channel.description!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Resume / Play Next button
                    videosAsync.when(
                      data: (videos) {
                        if (videos.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        final firstUnwatched = videos.where((v) => !v.isWatched);
                        final resumeVideo = firstUnwatched.isNotEmpty
                            ? firstUnwatched.first
                            : videos.first;
                        final hasProgress =
                            resumeVideo.watchPositionSeconds > 0;
                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                context.push('/player/${resumeVideo.id}'),
                            icon: Icon(
                              hasProgress ? Icons.play_arrow : Icons.play_arrow,
                              size: 24,
                            ),
                            label: Text(
                              hasProgress ? 'Resume' : 'Play Next',
                            ),
                          ),
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Videos',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            videosAsync.when(
              data: (videos) {
                if (videos.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No videos downloaded yet',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final video = videos[index];
                      return VideoListTile(
                        video: video,
                        onTap: () => context.push('/player/${video.id}'),
                      );
                    },
                    childCount: videos.length,
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
              error: (error, _) => SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Failed to load videos',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: NullFeedTheme.errorColor),
              const SizedBox(height: 16),
              Text('Failed to load channel',
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
