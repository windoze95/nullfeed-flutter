import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/video.dart';

/// Per-type accent for [ContentTypeBadge]. The chip keeps the shared black
/// background so it reads like the other thumbnail badges; the icon carries the
/// color. Reuses the unplayable-badge colors where types overlap.
Color contentTypeColor(ContentType type) => switch (type) {
  ContentType.short => NullFeedTheme.primaryColor,
  ContentType.live => NullFeedTheme.errorColor,
  ContentType.premiere => const Color(0xFF4DB6AC),
  ContentType.ageRestricted => NullFeedTheme.errorColor,
  ContentType.membersOnly => const Color(0xFFFFB74D),
  ContentType.premium => NullFeedTheme.primaryColor,
  ContentType.regular || ContentType.unknown => NullFeedTheme.textMuted,
};

IconData contentTypeIcon(ContentType type) => switch (type) {
  ContentType.short => Icons.smart_display,
  ContentType.live => Icons.sensors,
  ContentType.premiere => Icons.schedule,
  ContentType.ageRestricted => Icons.explicit,
  ContentType.membersOnly => Icons.card_membership,
  ContentType.premium => Icons.workspace_premium,
  ContentType.regular || ContentType.unknown => Icons.videocam,
};

/// Thumbnail pill marking a video's content type (Short, Live, Premiere, …).
/// Sits in a tile's thumbnail [Stack]; [compact] shrinks it for the small
/// list-tile thumbnails. Mirrors [UnplayableBadge] — the two never show at once
/// (see [VideoExtensions.badgeContentType]).
class ContentTypeBadge extends StatelessWidget {
  final ContentType type;
  final bool compact;

  const ContentTypeBadge({super.key, required this.type, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 10.0 : 12.0;
    final fontSize = compact ? 9.0 : 10.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            contentTypeIcon(type),
            color: contentTypeColor(type),
            size: iconSize,
          ),
          SizedBox(width: compact ? 3 : 4),
          Text(
            type.label,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
