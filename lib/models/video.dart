import 'package:freezed_annotation/freezed_annotation.dart';
import 'json_converters.dart';

part 'video.freezed.dart';
part 'video.g.dart';

enum VideoStatus {
  @JsonValue('CATALOGED')
  cataloged,
  @JsonValue('PENDING')
  pending,
  @JsonValue('DOWNLOADING')
  downloading,
  @JsonValue('COMPLETE')
  complete,
  @JsonValue('FAILED')
  failed,
}

/// Why YouTube refuses this video, as classified by the backend from yt-dlp
/// failures and playlist availability badges. Null on the wire means playable
/// as far as the server knows; [unknown] absorbs vocabulary the backend adds
/// before this client learns it (still bannered, just generically).
enum UnplayableReason {
  @JsonValue('age_restricted')
  ageRestricted,
  @JsonValue('members_only')
  membersOnly,
  @JsonValue('premium')
  premium,
  @JsonValue('private')
  private,
  @JsonValue('geo_blocked')
  geoBlocked,
  @JsonValue('removed')
  removed,
  @JsonValue('drm')
  drm,
  @JsonValue('upcoming')
  upcoming,
  @JsonValue('unavailable')
  unavailable,
  unknown,
}

extension UnplayableReasonLabels on UnplayableReason {
  /// Short uppercase-style banner text for thumbnails.
  String get label => switch (this) {
    UnplayableReason.ageRestricted => 'Age-restricted',
    UnplayableReason.membersOnly => 'Members only',
    UnplayableReason.premium => 'Premium',
    UnplayableReason.private => 'Private',
    UnplayableReason.geoBlocked => 'Geo-blocked',
    UnplayableReason.removed => 'Removed',
    UnplayableReason.drm => 'DRM-protected',
    UnplayableReason.upcoming => 'Upcoming',
    UnplayableReason.unavailable || UnplayableReason.unknown => 'Unavailable',
  };

  /// One-sentence explanation for menus and the player's blocked view.
  String get description => switch (this) {
    UnplayableReason.ageRestricted =>
      'YouTube age-restricts this video. It can play once the server has '
          'working YouTube cookies from an age-verified account.',
    UnplayableReason.membersOnly =>
      'This video is exclusive to channel members on YouTube, so the server '
          'can\'t fetch it.',
    UnplayableReason.premium =>
      'YouTube requires payment or a Premium subscription for this video.',
    UnplayableReason.private => 'The uploader made this video private.',
    UnplayableReason.geoBlocked =>
      'This video isn\'t available in the server\'s country.',
    UnplayableReason.removed =>
      'This video was removed from YouTube or its account was terminated.',
    UnplayableReason.drm =>
      'This video is DRM-protected and can\'t be fetched.',
    UnplayableReason.upcoming =>
      'This video hasn\'t premiered yet. It becomes playable once it airs.',
    UnplayableReason.unavailable ||
    UnplayableReason.unknown => 'YouTube reports this video as unavailable.',
  };
}

/// What kind of media a video is, classified by the backend at catalog time. A
/// stable label (unlike [UnplayableReason], which clears once playable), used to
/// badge the thumbnail and drive the per-channel filter. Null/[regular] is a
/// plain upload; [unknown] absorbs vocabulary the backend adds before this
/// client learns it.
enum ContentType {
  @JsonValue('regular')
  regular,
  @JsonValue('short')
  short,
  @JsonValue('live')
  live,
  @JsonValue('premiere')
  premiere,
  @JsonValue('age_restricted')
  ageRestricted,
  @JsonValue('members_only')
  membersOnly,
  @JsonValue('premium')
  premium,
  unknown,
}

extension ContentTypeLabels on ContentType {
  /// Short thumbnail-badge text (singular).
  String get label => switch (this) {
    ContentType.short => 'Short',
    ContentType.live => 'Live',
    ContentType.premiere => 'Premiere',
    ContentType.ageRestricted => 'Age-restricted',
    ContentType.membersOnly => 'Members only',
    ContentType.premium => 'Premium',
    ContentType.regular || ContentType.unknown => '',
  };

  /// Filter-menu label (plural where natural).
  String get menuLabel => switch (this) {
    ContentType.regular => 'Videos',
    ContentType.short => 'Shorts',
    ContentType.live => 'Live',
    ContentType.premiere => 'Premieres',
    ContentType.ageRestricted => 'Age-restricted',
    ContentType.membersOnly => 'Members only',
    ContentType.premium => 'Premium',
    ContentType.unknown => 'Other',
  };

  /// The backend wire value (matches the @JsonValue), for the filter API and
  /// comparing against a channel's hidden/available lists.
  String get wire => switch (this) {
    ContentType.regular => 'regular',
    ContentType.short => 'short',
    ContentType.live => 'live',
    ContentType.premiere => 'premiere',
    ContentType.ageRestricted => 'age_restricted',
    ContentType.membersOnly => 'members_only',
    ContentType.premium => 'premium',
    ContentType.unknown => 'unknown',
  };
}

/// Parse a backend content-type wire value (e.g. from a channel's
/// available/hidden lists) into a [ContentType], or null if unrecognized.
ContentType? contentTypeFromWire(String value) => switch (value) {
  'regular' => ContentType.regular,
  'short' => ContentType.short,
  'live' => ContentType.live,
  'premiere' => ContentType.premiere,
  'age_restricted' => ContentType.ageRestricted,
  'members_only' => ContentType.membersOnly,
  'premium' => ContentType.premium,
  _ => null,
};

@freezed
abstract class Video with _$Video {
  const factory Video({
    required String id,
    @JsonKey(name: 'youtube_video_id') required String youtubeVideoId,
    @JsonKey(name: 'channel_id') required String channelId,
    required String title,
    @JsonKey(name: 'duration_seconds') @Default(0) int durationSeconds,
    @JsonKey(name: 'uploaded_at', fromJson: nullableDateTimeFromJson)
    DateTime? uploadedAt,
    @JsonKey(name: 'file_path') String? filePath,
    @JsonKey(name: 'file_size_bytes') int? fileSizeBytes,
    @Default(VideoStatus.cataloged) VideoStatus status,
    @JsonKey(name: 'metadata_json') Map<String, dynamic>? metadataJson,
    // Joined fields from UserVideoRef
    @JsonKey(name: 'watch_position_seconds')
    @Default(0)
    int watchPositionSeconds,
    @JsonKey(name: 'is_watched') @Default(false) bool isWatched,
    @JsonKey(name: 'last_watched_at', fromJson: nullableDateTimeFromJson)
    DateTime? lastWatchedAt,
    // Preview
    @JsonKey(name: 'preview_status') String? previewStatus,
    // Why YouTube refuses this video (see UnplayableReason); null = playable.
    @JsonKey(
      name: 'unplayable_reason',
      unknownEnumValue: UnplayableReason.unknown,
    )
    UnplayableReason? unplayableReason,
    // What kind of media this is (see ContentType); null = regular.
    @JsonKey(name: 'content_type', unknownEnumValue: ContentType.unknown)
    ContentType? contentType,
    // Joined from channel
    @JsonKey(name: 'channel_name') @Default('') String channelName,
  }) = _Video;

  factory Video.fromJson(Map<String, dynamic> json) => _$VideoFromJson(json);
}

/// Seconds to rewind when resuming so the viewer gets a moment of context
/// before the position they left off at.
const int _resumeRewindSeconds = 10;

extension VideoExtensions on Video {
  bool get isPlayable =>
      status == VideoStatus.complete || previewStatus == 'READY';

  /// The unplayable reason worth showing. A video we already hold a playable
  /// file for (HQ or preview) plays regardless of a stale label, so no banner.
  UnplayableReason? get activeUnplayableReason =>
      isPlayable ? null : unplayableReason;

  /// The content type worth badging on the thumbnail, or null. Regular/unknown
  /// aren't badged, and the unplayable banner already covers members/premium/
  /// age when it's showing — so the two badges never stack.
  ContentType? get badgeContentType {
    if (activeUnplayableReason != null) return null;
    final ct = contentType;
    if (ct == null || ct == ContentType.regular || ct == ContentType.unknown) {
      return null;
    }
    return ct;
  }

  bool get hasPreviewReady => previewStatus == 'READY';

  bool get isPreviewOnly =>
      previewStatus == 'READY' && status != VideoStatus.complete;

  bool get isDownloadable =>
      status == VideoStatus.cataloged || status == VideoStatus.failed;

  bool get isInProgress =>
      status == VideoStatus.pending || status == VideoStatus.downloading;

  double get watchProgress {
    if (durationSeconds == 0) return 0;
    return watchPositionSeconds / durationSeconds;
  }

  /// Whether opening this video should resume from [watchPositionSeconds]
  /// rather than starting over. True only for partially-watched videos: a
  /// fresh video (position 0) or a fully-watched one ([isWatched]) starts from
  /// the top. Drives the player's resume affordance.
  bool get canResume => watchPositionSeconds > 0 && !isWatched;

  /// Where playback should seek when resuming: [watchPositionSeconds] rewound a
  /// few seconds for context, clamped to the video. Falls back to the raw
  /// position as the upper bound when the duration is unknown.
  int get resumeSeekSeconds {
    final maxSeconds = durationSeconds > 0
        ? durationSeconds
        : watchPositionSeconds;
    return (watchPositionSeconds - _resumeRewindSeconds).clamp(0, maxSeconds);
  }

  String get formattedDuration {
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    final seconds = durationSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
