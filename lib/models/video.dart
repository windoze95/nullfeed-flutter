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
