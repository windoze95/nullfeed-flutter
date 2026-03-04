import 'package:freezed_annotation/freezed_annotation.dart';

part 'channel.freezed.dart';
part 'channel.g.dart';

@freezed
class Channel with _$Channel {
  const factory Channel({
    required String id,
    @JsonKey(name: 'youtube_channel_id') required String youtubeChannelId,
    required String name,
    required String slug,
    String? description,
    @JsonKey(name: 'banner_url') String? bannerUrl,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    @JsonKey(name: 'last_checked_at') DateTime? lastCheckedAt,
    @JsonKey(name: 'tracking_mode') String? trackingMode,
  }) = _Channel;

  factory Channel.fromJson(Map<String, dynamic> json) =>
      _$ChannelFromJson(json);
}
