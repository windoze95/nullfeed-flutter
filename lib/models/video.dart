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
