import 'package:freezed_annotation/freezed_annotation.dart';
import 'channel.dart';
import 'video.dart';

part 'feed.freezed.dart';
part 'feed.g.dart';

@freezed
class FeedItem with _$FeedItem {
  const factory FeedItem({
    required Channel channel,
    required Video video,
  }) = _FeedItem;

  factory FeedItem.fromJson(Map<String, dynamic> json) =>
      _$FeedItemFromJson(json);
}

@freezed
class HomeFeed with _$HomeFeed {
  const factory HomeFeed({
    @JsonKey(name: 'continue_watching')
    @Default([])
    List<FeedItem> continueWatching,
    @JsonKey(name: 'new_episodes') @Default([]) List<FeedItem> newEpisodes,
    @JsonKey(name: 'recently_added')
    @Default([])
    List<FeedItem> recentlyAdded,
  }) = _HomeFeed;

  factory HomeFeed.fromJson(Map<String, dynamic> json) =>
      _$HomeFeedFromJson(json);
}
