import 'package:freezed_annotation/freezed_annotation.dart';
import 'json_converters.dart';

part 'channel.freezed.dart';
part 'channel.g.dart';

@freezed
abstract class Channel with _$Channel {
  const factory Channel({
    required String id,
    @JsonKey(name: 'youtube_channel_id') required String youtubeChannelId,
    required String name,
    required String slug,
    String? description,
    @JsonKey(name: 'banner_url') String? bannerUrl,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    @JsonKey(name: 'last_checked_at', fromJson: nullableDateTimeFromJson)
    DateTime? lastCheckedAt,
    @JsonKey(name: 'tracking_mode') String? trackingMode,
    @JsonKey(name: 'is_subscribed') @Default(false) bool isSubscribed,
    // Content types (wire values, e.g. 'short') this user has hidden for this
    // channel, and the distinct types the channel actually has — together they
    // drive the per-channel filter menu.
    @JsonKey(name: 'hidden_content_types')
    @Default(<String>[])
    List<String> hiddenContentTypes,
    @JsonKey(name: 'available_content_types')
    @Default(<String>[])
    List<String> availableContentTypes,
  }) = _Channel;

  factory Channel.fromJson(Map<String, dynamic> json) =>
      _$ChannelFromJson(json);
}
