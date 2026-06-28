import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video.dart';
import '../services/api_service.dart';

/// Immutable state for the watch-later queue: the loaded [videos] in play
/// order (front first), the pagination cursor and total, plus the loading and
/// error bookkeeping shared by the Queue screen and the per-video toggles.
class QueueState {
  final List<Video> videos;

  /// Opaque cursor for the next queue page, or null when on the last page.
  final String? nextCursor;

  /// Total queued videos, independent of how many pages are loaded.
  final int total;

  /// The first page is loading (or reloading).
  final bool isLoading;

  /// A further page is being appended via [QueueNotifier.loadMore].
  final bool isLoadingMore;

  final String? error;

  const QueueState({
    this.videos = const [],
    this.nextCursor,
    this.total = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  bool get hasMore => nextCursor != null;
  bool get isEmpty => videos.isEmpty;

  /// Whether [videoId] is in the loaded queue. Membership is only known for
  /// pages that have been fetched; an unloaded later page reads as absent,
  /// which is harmless since adding is idempotent server-side.
  bool isQueued(String videoId) => videos.any((v) => v.id == videoId);

  QueueState copyWith({
    List<Video>? videos,
    String? nextCursor,
    bool clearNextCursor = false,
    int? total,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
  }) {
    return QueueState(
      videos: videos ?? this.videos,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      total: total ?? this.total,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Owns the watch-later queue. Loads the first page on build, paginates on
/// demand, and applies add/remove optimistically — the UI updates immediately
/// and only rolls back if the server call fails.
///
/// A single non-autoDispose instance is shared app-wide, so the player can
/// keep advancing through the queue across route replacements and every card's
/// Add/Remove toggle reflects the same source of truth.
class QueueNotifier extends Notifier<QueueState> {
  /// Bumped on every [load] so a slow in-flight page can't overwrite a newer
  /// reload's results.
  int _requestId = 0;

  @override
  QueueState build() {
    // Deferred so the synchronous part runs after build() returns and `state`
    // exists.
    Future.microtask(load);
    return const QueueState(isLoading: true);
  }

  ApiService get _api => ref.read(apiServiceProvider);

  /// Fetches the first page, replacing the loaded queue. Existing items stay on
  /// screen while the request is in flight (the Queue screen only shows a
  /// full-screen spinner when nothing is loaded yet).
  Future<void> load() async {
    final requestId = ++_requestId;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final page = await _api.getQueue();
      if (requestId != _requestId) return;
      state = state.copyWith(
        videos: page.items,
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        total: page.total,
        isLoading: false,
        isLoadingMore: false,
      );
    } catch (e) {
      if (requestId != _requestId) return;
      state = state.copyWith(
        isLoading: false,
        error: e is ApiException ? e.message : 'Failed to load your queue.',
      );
    }
  }

  /// Re-runs the first-page load (pull-to-refresh, retry after error).
  Future<void> refresh() => load();

  /// Appends the next page. No-op while the first page loads, while already
  /// appending, or once the last page has been reached.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || state.nextCursor == null) {
      return;
    }
    final requestId = _requestId;
    final cursor = state.nextCursor;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _api.getQueue(cursor: cursor);
      // A reload started while this page was in flight — drop the result.
      if (requestId != _requestId) return;
      state = state.copyWith(
        videos: [...state.videos, ...page.items],
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        total: page.total,
        isLoadingMore: false,
      );
    } catch (_) {
      if (requestId != _requestId) return;
      // Keep what's loaded; just stop the footer spinner.
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Adds [video] to the end of the queue optimistically, then persists. On
  /// failure the optimistic change is rolled back and the error rethrown so
  /// the caller can surface it. No-op (and no network call) if [video] is
  /// already in the loaded queue, since adding is idempotent.
  Future<void> add(Video video) async {
    if (state.isQueued(video.id)) return;
    final previous = state;
    state = state.copyWith(
      videos: [...state.videos, video],
      total: state.total + 1,
    );
    try {
      await _api.addToQueue(video.id);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }

  /// Removes [videoId] from the queue optimistically, then persists, rolling
  /// back and rethrowing on failure. If the video isn't in the loaded queue
  /// (e.g. it lives on an unfetched page) the server is still told to remove
  /// it — there's just nothing to roll back.
  Future<void> remove(String videoId) async {
    if (!state.isQueued(videoId)) {
      await _api.removeFromQueue(videoId);
      return;
    }
    final previous = state;
    state = state.copyWith(
      videos: state.videos.where((v) => v.id != videoId).toList(),
      total: (state.total - 1).clamp(0, previous.total),
    );
    try {
      await _api.removeFromQueue(videoId);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }

  /// Toggles [video]'s membership — removes it when queued, adds it otherwise.
  Future<void> toggle(Video video) =>
      state.isQueued(video.id) ? remove(video.id) : add(video);

  /// The id of the item to play after [finishedId] finishes, or null if the
  /// queue can't advance. Pure — does not mutate the queue.
  ///
  /// When [finishedId] is in the queue, returns the item directly after it;
  /// when it isn't (the video was opened from outside the queue), returns the
  /// queue's head so a finished video still flows into a non-empty queue.
  String? nextAfter(String finishedId) {
    final q = state.videos;
    if (q.isEmpty) return null;
    final i = q.indexWhere((v) => v.id == finishedId);
    if (i == -1) return q.first.id;
    if (i + 1 < q.length) return q[i + 1].id;
    return null;
  }
}

final queueProvider = NotifierProvider<QueueNotifier, QueueState>(
  QueueNotifier.new,
);
