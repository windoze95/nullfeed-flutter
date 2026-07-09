import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/channel.dart';
import '../models/video.dart';
import '../services/api_service.dart';
import 'session_scope_provider.dart';

/// Immutable state for the search screen: the committed [query], the channel
/// and video matches, and the pagination/loading bookkeeping that backs the
/// list states.
class SearchState {
  final String query;
  final List<Channel> channels;
  final List<Video> videos;

  /// Opaque cursor for the next video page, or null when on the last page.
  final String? nextCursor;

  /// Total matching videos, independent of how many pages are loaded.
  final int total;

  /// A new query is loading its first page.
  final bool isLoading;

  /// A further page is being appended via [SearchNotifier.loadMore].
  final bool isLoadingMore;

  final String? error;

  const SearchState({
    this.query = '',
    this.channels = const [],
    this.videos = const [],
    this.nextCursor,
    this.total = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  bool get hasMore => nextCursor != null;
  bool get hasResults => channels.isNotEmpty || videos.isNotEmpty;

  SearchState copyWith({
    String? query,
    List<Channel>? channels,
    List<Video>? videos,
    String? nextCursor,
    bool clearNextCursor = false,
    int? total,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
  }) {
    return SearchState(
      query: query ?? this.query,
      channels: channels ?? this.channels,
      videos: videos ?? this.videos,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      total: total ?? this.total,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives library search: debounces the query, fetches channel + video matches
/// for the first page, then appends further video pages on demand.
///
/// An empty query lists recent library items (videos only — the whole channel
/// list isn't worth dumping). State only changes from the [search]/[loadMore]
/// event handlers, never from a widget's build.
class SearchNotifier extends Notifier<SearchState> {
  Timer? _debounce;

  /// Bumped on every new query so a slow in-flight response can't overwrite
  /// the results of a newer one.
  int _requestId = 0;

  static const _debounceDuration = Duration(milliseconds: 300);

  @override
  SearchState build() {
    final scope = ref.watch(activeSessionScopeProvider);
    _debounce?.cancel();
    _requestId++;
    ref.onDispose(() => _debounce?.cancel());
    if (scope == null) return const SearchState();
    // Load recent library items once the provider is initialized (deferred so
    // the synchronous part runs after build() returns).
    Future.microtask(() => _run(''));
    return const SearchState(isLoading: true);
  }

  ApiService get _api => ref.read(apiServiceProvider);

  /// Debounced entry point wired to the search field's `onChanged`.
  void search(String query) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () => _run(query));
  }

  /// Clears the query immediately (no debounce) and reloads recent items.
  void clear() {
    _debounce?.cancel();
    _run('');
  }

  /// Re-runs the current query after an error.
  void retry() => _run(state.query);

  Future<void> _run(String query) async {
    final scope = ref.read(activeSessionScopeProvider);
    if (scope == null) {
      state = const SearchState();
      return;
    }
    final q = query.trim();
    final requestId = ++_requestId;
    // Reset to a clean loading state so stale results don't linger under the
    // spinner while the new query resolves.
    state = state.copyWith(
      query: q,
      channels: const [],
      videos: const [],
      total: 0,
      clearNextCursor: true,
      isLoading: true,
      isLoadingMore: false,
      clearError: true,
    );

    try {
      // Start both requests before awaiting so they run concurrently. Channel
      // search is skipped for the empty (recent) query.
      final pageFuture = _api.searchVideos(q: q.isEmpty ? null : q);
      final channelsFuture = q.isEmpty
          ? Future.value(<Channel>[])
          : _api.searchChannels(q);
      final page = await pageFuture;
      final channels = await channelsFuture;
      if (!ref.mounted ||
          requestId != _requestId ||
          ref.read(activeSessionScopeProvider) != scope) {
        return;
      }
      state = state.copyWith(
        channels: channels,
        videos: page.items,
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        total: page.total,
        isLoading: false,
      );
    } catch (e) {
      if (!ref.mounted || requestId != _requestId) return;
      state = state.copyWith(
        isLoading: false,
        error: e is ApiException
            ? e.message
            : 'Search failed. Please try again.',
      );
    }
  }

  /// Appends the next video page. No-op while a query loads, while already
  /// appending, or once the last page has been reached.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || state.nextCursor == null) {
      return;
    }
    final requestId = _requestId;
    final scope = ref.read(activeSessionScopeProvider);
    if (scope == null) return;
    final cursor = state.nextCursor;
    final q = state.query;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _api.searchVideos(
        q: q.isEmpty ? null : q,
        cursor: cursor,
      );
      // A new query started while this page was in flight — drop the result.
      if (!ref.mounted ||
          requestId != _requestId ||
          ref.read(activeSessionScopeProvider) != scope) {
        return;
      }
      state = state.copyWith(
        videos: [...state.videos, ...page.items],
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        total: page.total,
        isLoadingMore: false,
      );
    } catch (_) {
      if (!ref.mounted || requestId != _requestId) return;
      // Keep what's loaded; just stop the footer spinner.
      state = state.copyWith(isLoadingMore: false);
    }
  }
}

final searchProvider = NotifierProvider<SearchNotifier, SearchState>(
  SearchNotifier.new,
);
