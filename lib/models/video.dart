import 'package:freezed_annotation/freezed_annotation.dart';

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
class Video with _$Video {
  const factory Video({
    required String id,
    @JsonKey(name: 'youtube_video_id') required String youtubeVideoId,
    @JsonKey(name: 'channel_id') required String channelId,
    required String title,
    @JsonKey(name: 'duration_seconds') @Default(0) int durationSeconds,
    @JsonKey(name: 'uploaded_at') DateTime? uploadedAt,
    @JsonKey(name: 'file_path') String? filePath,
    @JsonKey(name: 'file_size_bytes') int? fileSizeBytes,
    @Default(VideoStatus.cataloged) VideoStatus status,
    @JsonKey(name: 'metadata_json') Map<String, dynamic>? metadataJson,
    // Joined fields from UserVideoRef
    @JsonKey(name: 'watch_position_seconds') @Default(0) int watchPositionSeconds,
    @JsonKey(name: 'is_watched') @Default(false) bool isWatched,
    // Preview
    @JsonKey(name: 'preview_status') String? previewStatus,
    // Joined from channel
    @JsonKey(name: 'channel_name') @Default('') String channelName,
  }) = _Video;

  factory Video.fromJson(Map<String, dynamic> json) => _$VideoFromJson(json);
}

extension VideoExtensions on Video {
  bool get isPlayable => status == VideoStatus.complete || previewStatus == 'READY';

  bool get hasPreviewReady => previewStatus == 'READY';

  bool get isPreviewOnly => previewStatus == 'READY' && status != VideoStatus.complete;

  bool get isDownloadable =>
      status == VideoStatus.cataloged || status == VideoStatus.failed;

  bool get isInProgress =>
      status == VideoStatus.pending || status == VideoStatus.downloading;

  double get watchProgress {
    if (durationSeconds == 0) return 0;
    return watchPositionSeconds / durationSeconds;
  }

  String get formattedDuration {
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    final seconds = durationSeconds % 60;
    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
}
