import 'package:freezed_annotation/freezed_annotation.dart';
import 'video.dart';

part 'video_page.freezed.dart';
part 'video_page.g.dart';

/// One page of cursor-paginated video search results.
///
/// Mirrors the backend `VideoSearchPage`: [items] are this page's videos,
/// [total] is the full match count (independent of the cursor), and
/// [nextCursor] is an opaque token to send back as `?cursor=` for the next
/// page — null on the last page.
@freezed
abstract class VideoPage with _$VideoPage {
  const factory VideoPage({
    @Default(<Video>[]) List<Video> items,
    @Default(0) int total,
    @JsonKey(name: 'next_cursor') String? nextCursor,
  }) = _VideoPage;

  factory VideoPage.fromJson(Map<String, dynamic> json) =>
      _$VideoPageFromJson(json);
}

extension VideoPageExtensions on VideoPage {
  /// Whether another page can be fetched with [VideoPage.nextCursor].
  bool get hasMore => nextCursor != null;
}
