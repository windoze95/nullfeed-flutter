import 'package:freezed_annotation/freezed_annotation.dart';

part 'youtube_import.freezed.dart';
part 'youtube_import.g.dart';

/// Identity resolved from a YouTube handle via `POST /api/youtube/resolve`.
@freezed
abstract class YoutubeProfile with _$YoutubeProfile {
  const factory YoutubeProfile({
    required String handle,
    @JsonKey(name: 'channel_id') required String channelId,
    required String name,
    String? description,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    @JsonKey(name: 'banner_url') String? bannerUrl,
    @JsonKey(name: 'follower_count') int? followerCount,
  }) = _YoutubeProfile;

  factory YoutubeProfile.fromJson(Map<String, dynamic> json) =>
      _$YoutubeProfileFromJson(json);
}

/// A channel suggestion from `POST /api/youtube/suggestions`.
@freezed
abstract class ChannelSuggestion with _$ChannelSuggestion {
  const factory ChannelSuggestion({
    @JsonKey(name: 'youtube_channel_id') required String youtubeChannelId,
    required String name,
    String? handle,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    required String source,
    @Default(0) int score,
  }) = _ChannelSuggestion;

  factory ChannelSuggestion.fromJson(Map<String, dynamic> json) =>
      _$ChannelSuggestionFromJson(json);
}

/// Per-item outcome of `POST /api/channels/subscribe-bulk`.
/// `status` is one of 'subscribed', 'already_subscribed', or 'error'.
@freezed
abstract class BulkSubscribeResult with _$BulkSubscribeResult {
  const factory BulkSubscribeResult({
    @JsonKey(name: 'youtube_channel_id') required String youtubeChannelId,
    required String status,
    @JsonKey(name: 'channel_id') String? channelId,
    String? detail,
  }) = _BulkSubscribeResult;

  factory BulkSubscribeResult.fromJson(Map<String, dynamic> json) =>
      _$BulkSubscribeResultFromJson(json);
}
