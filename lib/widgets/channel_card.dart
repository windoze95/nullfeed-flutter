import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/channel.dart';
import '../config/theme.dart';

class ChannelCard extends StatefulWidget {
  final Channel channel;
  final VoidCallback? onTap;

  const ChannelCard({
    super.key,
    required this.channel,
    this.onTap,
  });

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> {
  bool _isHovered = false;
  bool _isFocused = false;

  bool get _isHighlighted => _isHovered || _isFocused;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: _isHighlighted
                ? (Matrix4.identity()..scale(1.03))
                : Matrix4.identity(),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: _isFocused
                  ? Border.all(
                      color: NullFeedTheme.primaryColor,
                      width: 3,
                    )
                  : null,
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color:
                            NullFeedTheme.primaryColor.withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Card(
              clipBehavior: Clip.antiAlias,
              color: _isHighlighted ? NullFeedTheme.cardHoverColor : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Banner image
                  if (widget.channel.bannerUrl != null)
                    CachedNetworkImage(
                      imageUrl: widget.channel.bannerUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          Container(color: NullFeedTheme.cardColor),
                      placeholder: (_, __) => Container(
                        color: NullFeedTheme.cardColor,
                      ),
                    )
                  else
                    Container(
                      color: NullFeedTheme.cardColor,
                      child: Center(
                        child: Icon(
                          Icons.subscriptions,
                          size: 40,
                          color: NullFeedTheme.primaryColor
                              .withValues(alpha: 0.3),
                        ),
                      ),
                    ),

                  // Gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.85),
                        ],
                        stops: const [0.3, 1.0],
                      ),
                    ),
                  ),

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
                              widget.channel.avatarUrl!,
                            ),
                          )
                        else
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: NullFeedTheme.primaryColor
                                .withValues(alpha: 0.3),
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
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
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
        ),
      ),
    );
  }
}
