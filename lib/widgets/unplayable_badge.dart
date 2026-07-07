import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/video.dart';

/// Per-reason accent for [UnplayableBadge]. The chip itself keeps the shared
/// black-badge background so it reads like the other thumbnail badges; the
/// icon carries the color coding.
Color unplayableReasonColor(UnplayableReason reason) => switch (reason) {
  UnplayableReason.ageRestricted => NullFeedTheme.errorColor,
  UnplayableReason.membersOnly => const Color(0xFFFFB74D),
  UnplayableReason.premium => NullFeedTheme.primaryColor,
  UnplayableReason.geoBlocked => const Color(0xFF64B5F6),
  UnplayableReason.upcoming => const Color(0xFF4DB6AC),
  UnplayableReason.private ||
  UnplayableReason.removed ||
  UnplayableReason.drm ||
  UnplayableReason.unavailable ||
  UnplayableReason.unknown => NullFeedTheme.textMuted,
};

IconData unplayableReasonIcon(UnplayableReason reason) => switch (reason) {
  UnplayableReason.ageRestricted => Icons.explicit,
  UnplayableReason.membersOnly => Icons.card_membership,
  UnplayableReason.premium => Icons.workspace_premium,
  UnplayableReason.private => Icons.lock,
  UnplayableReason.geoBlocked => Icons.public_off,
  UnplayableReason.removed => Icons.block,
  UnplayableReason.drm => Icons.security,
  UnplayableReason.upcoming => Icons.schedule,
  UnplayableReason.unavailable ||
  UnplayableReason.unknown => Icons.videocam_off,
};

/// Non-tappable actions-sheet row explaining why a video can't be played or
/// downloaded, in a full sentence (the thumbnail badge only has room for a
/// couple of words).
class UnplayableReasonTile extends StatelessWidget {
  final UnplayableReason reason;

  const UnplayableReasonTile({super.key, required this.reason});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        unplayableReasonIcon(reason),
        color: unplayableReasonColor(reason),
      ),
      title: Text(reason.label),
      subtitle: Text(
        reason.description,
        style: const TextStyle(color: NullFeedTheme.textMuted, fontSize: 12),
      ),
    );
  }
}

/// Thumbnail banner explaining why a video can't be played or downloaded
/// (age-restricted, members-only, premium, …). Sits in a tile's thumbnail
/// [Stack]; [compact] shrinks it for the small list-tile thumbnails.
class UnplayableBadge extends StatelessWidget {
  final UnplayableReason reason;
  final bool compact;

  const UnplayableBadge({
    super.key,
    required this.reason,
    this.compact = false,
  });

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
            unplayableReasonIcon(reason),
            color: unplayableReasonColor(reason),
            size: iconSize,
          ),
          SizedBox(width: compact ? 3 : 4),
          Text(
            reason.label,
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
