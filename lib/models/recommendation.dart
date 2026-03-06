import 'package:freezed_annotation/freezed_annotation.dart';

part 'recommendation.freezed.dart';
part 'recommendation.g.dart';

@freezed
abstract class Recommendation with _$Recommendation {
  const factory Recommendation({
    required String id,
    @JsonKey(name: 'channel_name') required String channelName,
    @JsonKey(name: 'channel_id') String? channelId,
    @JsonKey(name: 'youtube_channel_id') String? youtubeChannelId,
    required String reasoning,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    @JsonKey(name: 'banner_url') String? bannerUrl,
    @Default(false) bool dismissed,
  }) = _Recommendation;

  factory Recommendation.fromJson(Map<String, dynamic> json) =>
      _$RecommendationFromJson(json);
}
