import 'package:freezed_annotation/freezed_annotation.dart';

part 'subscription.freezed.dart';
part 'subscription.g.dart';

enum RetentionPolicy {
  @JsonValue('KEEP_ALL')
  keepAll,
  @JsonValue('KEEP_LAST_N')
  keepLastN,
  @JsonValue('KEEP_WATCHED')
  keepWatched,
}

@freezed
class Subscription with _$Subscription {
  const factory Subscription({
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'channel_id') required String channelId,
    @JsonKey(name: 'subscribed_at') required DateTime subscribedAt,
    @JsonKey(name: 'retention_policy')
    @Default(RetentionPolicy.keepAll)
    RetentionPolicy retentionPolicy,
    @JsonKey(name: 'retention_count') int? retentionCount,
  }) = _Subscription;

  factory Subscription.fromJson(Map<String, dynamic> json) =>
      _$SubscriptionFromJson(json);
}
