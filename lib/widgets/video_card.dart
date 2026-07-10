import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/video.dart';
import '../models/channel.dart';
import '../config/theme.dart';
import '../config/constants.dart';
import '../providers/feed_provider.dart';
import '../providers/offline_provider.dart';
import 'content_type_badge.dart';
import 'progress_bar.dart';
import 'queue_action.dart';
import 'unplayable_badge.dart';
import 'adaptive_layout.dart';

class VideoCard extends ConsumerStatefulWidget {
  final Video video;
  final Channel? channel;
  final bool showProgress;

  const VideoCard({
    super.key,
    required this.video,
    this.channel,
    this.showProgress = false,
  });

  @override
  ConsumerState<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends ConsumerState<VideoCard> {
  bool _isPressed = false;
  bool _isHovered = false;

  String? get _thumbnailUrl {
    if (widget.video.youtubeVideoId.isNotEmpty) {
      return 'https://i.ytimg.com/vi/${widget.video.youtubeVideoId}/maxresdefault.jpg';
    }
    return null;
  }

  String get _fallbackThumbnailUrl =>
      'https://i.ytimg.com/vi/${widget.video.youtubeVideoId}/hqdefault.jpg';

  /// One merged, human-readable label for the play target — title, channel and
  /// download state — instead of a pile of separate text/icon nodes.
  String _semanticLabel(String? offlineStatus) {
    final parts = <String>[widget.video.title];
    final channel = widget.channel;
    if (channel != null) parts.add(channel.name);
    if (offlineStatus == 'complete') parts.add('downloaded');
    final reason = widget.video.activeUnplayableReason;
    if (reason != null) parts.add(reason.label);
    return parts.join(', ');
  }

  Future<void> _onActivate() async {
    HapticFeedback.selectionClick();
    // Every home-feed card plays its video on tap; channel navigation lives
    // on the channel sub-row below (see [_openChannel]).
    await context.push('/player/${widget.video.id}');
    // Watch positions likely changed — refresh the home feed rows.
    if (!mounted) return;
    invalidateFeedProviders(ref);
  }

  void _openChannel() {
    final channel = widget.channel;
    if (channel == null) return;
    HapticFeedback.selectionClick();
    context.push('/channel/${channel.id}');
  }

  /// Long-press actions: play, toggle the watch-later queue, and (when known)
  /// jump to the channel.
  void _showMenu() {
    HapticFeedback.selectionClick();
    showVideoActionsSheet(
      context,
      video: widget.video,
      onPlay: _onActivate,
      onOpenChannel: widget.channel != null ? _openChannel : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableWidth =
        MediaQuery.sizeOf(context).width -
        (AdaptiveLayout.contentPadding(context) * 2);
    final cardWidth = availableWidth.clamp(250.0, AppConstants.videoCardWidth);
    final offlineStatus = ref.watch(offlineStatusProvider(widget.video.id));

    return AnimatedScale(
      scale: _isPressed ? 0.975 : (_isHovered ? 1.012 : 1.0),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail + progress + title are one tap target that plays.
            Semantics(
              button: true,
              label: _semanticLabel(offlineStatus),
              excludeSemantics: true,
              onTap: _onActivate,
              onLongPress: _showMenu,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: _onActivate,
                  onLongPress: _showMenu,
                  onTapDown: (_) => setState(() => _isPressed = true),
                  onTapUp: (_) => setState(() => _isPressed = false),
                  onTapCancel: () => setState(() => _isPressed = false),
                  onHover: (value) => setState(() => _isHovered = value),
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: AppConstants.cardAspectRatio,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_thumbnailUrl != null)
                                CachedNetworkImage(
                                  imageUrl: _thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  memCacheWidth:
                                      (cardWidth *
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ))
                                          .round(),
                                  filterQuality: FilterQuality.high,
                                  errorWidget: (_, __, ___) =>
                                      CachedNetworkImage(
                                        imageUrl: _fallbackThumbnailUrl,
                                        fit: BoxFit.cover,
                                        filterQuality: FilterQuality.high,
                                        errorWidget: (_, __, ___) => Container(
                                          color: NullFeedTheme.cardColor,
                                          child: const Icon(
                                            Icons.play_circle_outline_rounded,
                                            color: NullFeedTheme.textMuted,
                                            size: 40,
                                          ),
                                        ),
                                      ),
                                  placeholder: (_, __) =>
                                      Container(color: NullFeedTheme.cardColor),
                                )
                              else
                                Container(
                                  color: NullFeedTheme.cardColor,
                                  child: const Icon(
                                    Icons.play_circle_outline_rounded,
                                    color: NullFeedTheme.textMuted,
                                    size: 40,
                                  ),
                                ),

                              // A visible play affordance makes the result of
                              // tapping the artwork unambiguous.
                              Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  width: _isHovered ? 48 : 44,
                                  height: _isHovered ? 48 : 44,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(
                                      alpha: _isHovered ? 0.72 : 0.5,
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 27,
                                  ),
                                ),
                              ),

                              // Why this video can't play (age-restricted,
                              // members-only, …) — hidden once a local file
                              // makes it playable anyway. Otherwise the
                              // content-type pill (Short/Live/…) takes the same
                              // corner; the two never show together.
                              if (widget.video.activeUnplayableReason != null)
                                Positioned(
                                  left: 6,
                                  top: 6,
                                  child: UnplayableBadge(
                                    reason:
                                        widget.video.activeUnplayableReason!,
                                  ),
                                )
                              else if (widget.video.badgeContentType != null)
                                Positioned(
                                  left: 6,
                                  top: 6,
                                  child: ContentTypeBadge(
                                    type: widget.video.badgeContentType!,
                                  ),
                                ),

                              // Duration badge
                              if (widget.video.durationSeconds > 0)
                                Positioned(
                                  right: 6,
                                  bottom: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.8,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      widget.video.formattedDuration,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),

                              // Offline badge
                              if (offlineStatus == 'complete')
                                Positioned(
                                  left: 6,
                                  bottom: 6,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.7,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(
                                      Icons.offline_pin,
                                      color: NullFeedTheme.successColor,
                                      size: 16,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Progress bar
                      if (widget.showProgress && widget.video.watchProgress > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: NullFeedProgressBar(
                            progress: widget.video.watchProgress,
                            height: 3,
                            foregroundColor: NullFeedTheme.watchProgressColor,
                          ),
                        ),

                      // Title
                      Padding(
                        padding: const EdgeInsets.only(top: 9),
                        child: Text(
                          widget.video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: NullFeedTheme.textPrimary,
                            fontSize: 14,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Channel sub-row → open the channel.
            if (widget.channel != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Semantics(
                  button: true,
                  label: 'Go to ${widget.channel!.name}',
                  excludeSemantics: true,
                  onTap: _openChannel,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: _openChannel,
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          if (widget.channel!.avatarUrl != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: CircleAvatar(
                                radius: 10,
                                backgroundImage: CachedNetworkImageProvider(
                                  widget.channel!.avatarUrl!,
                                ),
                                backgroundColor: NullFeedTheme.cardColor,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              widget.channel!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: NullFeedTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
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
