import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video.dart';
import '../services/api_service.dart';
import 'session_scope_provider.dart';

class VideoDetailNotifier extends Notifier<AsyncValue<Video>> {
  late final String _videoId;
  int _requestId = 0;

  void init(String videoId) => _videoId = videoId;

  @override
  AsyncValue<Video> build() {
    final scope = ref.watch(activeSessionScopeProvider);
    _requestId++;
    if (scope == null) return const AsyncValue.loading();
    Future.microtask(refresh);
    return const AsyncValue.loading();
  }

  Future<void> refresh() async {
    final scope = ref.read(activeSessionScopeProvider);
    if (scope == null) {
      state = const AsyncValue.loading();
      return;
    }
    final requestId = ++_requestId;
    try {
      final video = await ref.read(apiServiceProvider).getVideo(_videoId);
      if (ref.mounted &&
          requestId == _requestId &&
          ref.read(activeSessionScopeProvider) == scope) {
        state = AsyncValue.data(video);
      }
    } catch (error, stackTrace) {
      if (ref.mounted && requestId == _requestId) {
        state = AsyncValue.error(error, stackTrace);
      }
    }
  }
}

final videoDetailProvider =
    NotifierProvider.family<VideoDetailNotifier, AsyncValue<Video>, String>((
      videoId,
    ) {
      final notifier = VideoDetailNotifier();
      notifier.init(videoId);
      return notifier;
    });

class VideoProgressNotifier extends Notifier<int> {
  late final String _videoId;

  @override
  int build() {
    ref.watch(activeSessionScopeProvider);
    return 0;
  }

  void init(String videoId) {
    _videoId = videoId;
  }

  ApiService get _api => ref.read(apiServiceProvider);

  void setPosition(int seconds) {
    state = seconds;
  }

  Future<void> saveProgress() async {
    if (ref.read(activeSessionScopeProvider) == null) return;
    try {
      await _api.updateProgress(_videoId, state);
    } catch (_) {
      // Silently fail - will retry on next interval
    }
  }

  Future<void> deleteVideo() async {
    if (ref.read(activeSessionScopeProvider) == null) {
      throw const ApiException(message: 'No active profile');
    }
    await _api.deleteVideo(_videoId);
  }
}

final videoProgressProvider =
    NotifierProvider.family<VideoProgressNotifier, int, String>((videoId) {
      final notifier = VideoProgressNotifier();
      notifier.init(videoId);
      return notifier;
    });
