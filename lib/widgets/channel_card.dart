import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/channel.dart';
import '../config/theme.dart';
import 'cinematic_banner.dart';

class ChannelCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback? onTap;

  /// Opens the channel actions menu (long-press or the ⋯ button).
  final VoidCallback? onMenu;

  const ChannelCard({
    super.key,
    required this.channel,
    this.onTap,
    this.onMenu,
  });

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> {
  bool _isPressed = false;

  void _handleTap() {
    final onTap = widget.onTap;
    if (onTap == null) return;
    HapticFeedback.selectionClick();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Main tappable surface: one merged node labelled with the channel
            // name. The actions menu lives in its own node below.
            Semantics(
              button: widget.onTap != null,
              label: '${widget.channel.name} channel',
              excludeSemantics: true,
              onTap: widget.onTap == null ? null : _handleTap,
              child: InkWell(
                onTap: widget.onTap == null ? null : _handleTap,
                onLongPress: widget.onMenu,
                onTapDown: (_) => setState(() => _isPressed = true),
                onTapUp: (_) => setState(() => _isPressed = false),
                onTapCancel: () => setState(() => _isPressed = false),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // YouTube banners are extremely wide. Here they provide
                    // ambient color instead of being stretched into the card;
                    // the sharp avatar below remains the visual anchor.
                    CinematicBanner(
                      imageUrl: widget.channel.bannerUrl,
                      showSharpArtwork: false,
                    ),

                    const Positioned(left: 12, top: 12, child: _ChannelLabel()),

                    // Channel info
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Row(
                        children: [
                          if (widget.channel.avatarUrl != null)
                            CircleAvatar(
                              radius: 18,
                              backgroundImage: CachedNetworkImageProvider(
                                CinematicBanner.highResolutionUrl(
                                  widget.channel.avatarUrl!,
                                )!,
                              ),
                              backgroundColor: NullFeedTheme.cardColor,
                            )
                          else
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: NullFeedTheme.primaryColor
                                  .withValues(alpha: 0.16),
                              child: Text(
                                widget.channel.name.isNotEmpty
                                    ? widget.channel.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: NullFeedTheme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Actions menu button — a separate, operable node on top.
            if (widget.onMenu != null)
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.more_vert, size: 20),
                  color: Colors.white70,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.4),
                  ),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: widget.onMenu,
                  tooltip: 'Channel actions',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChannelLabel extends StatelessWidget {
  const _ChannelLabel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          'CHANNEL',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}
