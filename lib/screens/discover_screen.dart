import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/theme.dart';
import '../models/recommendation.dart';
import '../providers/channel_provider.dart';
import '../providers/discover_provider.dart';
import '../services/api_service.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/app_ui.dart';
import '../widgets/cinematic_banner.dart';

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  Future<void> _subscribe(
    BuildContext context,
    WidgetRef ref,
    Recommendation rec,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(channelsProvider.notifier)
          .subscribe(rec.youtubeChannelId!);
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not subscribe: ${error.message}')),
      );
      rethrow;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Subscribed to ${rec.channelName}')),
    );
    try {
      await ref.read(discoverProvider.notifier).dismiss(rec.id);
    } catch (_) {
      // The follow succeeded. A cleanup failure must not be described as a
      // failed subscription or encourage the user to subscribe twice.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Subscribed to ${rec.channelName}, but the suggestion could not be cleared.',
          ),
        ),
      );
    }
  }

  Future<void> _dismiss(
    BuildContext context,
    WidgetRef ref,
    Recommendation rec,
  ) async {
    try {
      await ref.read(discoverProvider.notifier).dismiss(rec.id);
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not dismiss: ${error.message}')),
      );
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommendations = ref.watch(discoverProvider);
    final padding = AdaptiveLayout.contentPadding(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: NullFeedTheme.primaryColor,
        onRefresh: () => ref.read(discoverProvider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: PageIntro(
                  eyebrow: 'Private discovery',
                  title: 'Explore beyond your usual',
                  description:
                      'A small set of suggestions shaped by channels you '
                      'already follow. Nothing is added until you choose it.',
                  trailing: AdaptiveLayout.isPhone(context)
                      ? null
                      : ElevatedButton.icon(
                          onPressed: () =>
                              ref.read(discoverProvider.notifier).refresh(),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Find new picks'),
                        ),
                  bottom: AdaptiveLayout.isPhone(context)
                      ? SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                ref.read(discoverProvider.notifier).refresh(),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Find new picks'),
                          ),
                        )
                      : const _PrivacyNote(),
                ),
              ),
            ),
            if (AdaptiveLayout.isPhone(context))
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: _PrivacyNote(),
                ),
              ),
            recommendations.when(
              data: (recs) {
                if (recs.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyStatePanel(
                      icon: Icons.auto_awesome_rounded,
                      eyebrow: 'Teach your taste',
                      title: 'Your next picks need a little context',
                      description:
                          'Follow a few channels first. NullFeed uses that '
                          'starting point to make focused suggestions instead '
                          'of filling the page with generic trends.',
                      primaryLabel: 'Add a channel',
                      primaryAction: () => context.go('/library?add=1'),
                      secondaryLabel: 'Check again',
                      secondaryAction: () =>
                          ref.read(discoverProvider.notifier).refresh(),
                    ),
                  );
                }

                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 4, padding, 32),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 560,
                          mainAxisExtent: 340,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final rec = recs[index];
                      return _RecommendationCard(
                        recommendation: rec,
                        onPreview: rec.channelId == null
                            ? null
                            : () => context.push('/channel/${rec.channelId}'),
                        onDismiss: () => _dismiss(context, ref, rec),
                        onSubscribe: rec.youtubeChannelId == null
                            ? null
                            : () => _subscribe(context, ref, rec),
                      );
                    }, childCount: recs.length),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyStatePanel(
                  icon: Icons.cloud_off_rounded,
                  eyebrow: 'Suggestions unavailable',
                  title: 'Explore could not check in',
                  description:
                      'Your channels are unaffected. Retry when the server is '
                      'available.\n\n$error',
                  primaryLabel: 'Try again',
                  primaryAction: () =>
                      ref.read(discoverProvider.notifier).load(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 660),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: NullFeedTheme.accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: NullFeedTheme.accentColor.withValues(alpha: 0.16),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.privacy_tip_outlined,
            size: 17,
            color: NullFeedTheme.accentColor,
          ),
          SizedBox(width: 9),
          Flexible(
            child: Text(
              'Suggestions are generated for this profile and never auto-follow channels.',
              style: TextStyle(
                color: NullFeedTheme.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatefulWidget {
  const _RecommendationCard({
    required this.recommendation,
    required this.onDismiss,
    this.onSubscribe,
    this.onPreview,
  });

  final Recommendation recommendation;
  final Future<void> Function() onDismiss;
  final Future<void> Function()? onSubscribe;
  final VoidCallback? onPreview;

  @override
  State<_RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends State<_RecommendationCard> {
  bool _busy = false;
  bool _hovered = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      // The screen-level action already translated the failure into a clear
      // message. Keep this card mounted and tappable for a retry.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.recommendation;
    return AnimatedScale(
      scale: _hovered ? 1.008 : 1,
      duration: const Duration(milliseconds: 140),
      child: Card(
        child: InkWell(
          onHover: (value) => setState(() => _hovered = value),
          onTap: widget.onPreview,
          mouseCursor: widget.onPreview == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 112,
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    CinematicBanner(
                      imageUrl: rec.bannerUrl,
                      showSharpArtwork: false,
                    ),
                    Positioned(
                      left: 18,
                      bottom: -24,
                      child: _RecommendationAvatar(rec: rec),
                    ),
                    const Positioned(
                      top: 12,
                      right: 12,
                      child: AppStatusPill(
                        label: 'FOR YOU',
                        icon: Icons.auto_awesome_rounded,
                        onImage: true,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 34, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rec.channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 7),
                      Expanded(
                        child: Text(
                          rec.reasoning,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(widget.onDismiss),
                            child: const Text('Not for me'),
                          ),
                          const Spacer(),
                          if (_busy)
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            ElevatedButton.icon(
                              onPressed: widget.onSubscribe == null
                                  ? null
                                  : () => _run(widget.onSubscribe!),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Subscribe'),
                            ),
                        ],
                      ),
                    ],
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

class _RecommendationAvatar extends StatelessWidget {
  const _RecommendationAvatar({required this.rec});

  final Recommendation rec;

  @override
  Widget build(BuildContext context) {
    final url = CinematicBanner.highResolutionUrl(rec.avatarUrl);
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: NullFeedTheme.primaryColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: NullFeedTheme.surfaceColor, width: 3),
        image: url == null
            ? null
            : DecorationImage(
                image: CachedNetworkImageProvider(url),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
      ),
      alignment: Alignment.center,
      child: url == null
          ? Text(
              rec.channelName.isEmpty ? '?' : rec.channelName[0].toUpperCase(),
              style: const TextStyle(
                color: NullFeedTheme.accentColor,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }
}
