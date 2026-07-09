import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/active_session_scope.dart';
import '../services/offline_service.dart';
import 'session_scope_provider.dart';

/// Reactive list of all offline videos. Call `ref.invalidate(offlineVideosProvider)`
/// or `refresh()` after downloads complete or videos are removed.
class OfflineVideosNotifier extends Notifier<List<Map<String, dynamic>>> {
  @override
  List<Map<String, dynamic>> build() {
    final scope = ref.watch(activeSessionScopeProvider);
    if (scope == null) return const [];
    final offlineService = ref.watch(offlineServiceProvider);
    // Also marks entries stuck in 'downloading' (e.g. after an app kill)
    // as failed before returning them.
    return offlineService.loadOfflineVideos();
  }

  void refresh() {
    if (ref.read(activeSessionScopeProvider) == null) {
      state = const [];
      return;
    }
    final offlineService = ref.read(offlineServiceProvider);
    state = offlineService.getOfflineVideos();
  }
}

final offlineVideosProvider =
    NotifierProvider<OfflineVideosNotifier, List<Map<String, dynamic>>>(
      OfflineVideosNotifier.new,
    );

/// Offline status for a specific video: 'downloading', 'complete', 'failed', or null.
final offlineStatusProvider = Provider.family<String?, String>((ref, videoId) {
  final videos = ref.watch(offlineVideosProvider);
  try {
    final entry = videos.firstWhere((v) => v['video_id'] == videoId);
    return entry['status'] as String?;
  } catch (_) {
    return null;
  }
});

/// Ephemeral map of video_id -> download progress (0.0-1.0).
class OfflineProgressNotifier extends Notifier<Map<String, double>> {
  ActiveSessionScope? _scope;

  @override
  Map<String, double> build() {
    _scope = ref.watch(activeSessionScopeProvider);
    return {};
  }

  /// Sets progress only when [owner] is still the active session. This rejects
  /// delayed Dio callbacks after a server/profile switch.
  void setProgress(ActiveSessionScope owner, String videoId, double? progress) {
    if (_scope != owner || ref.read(activeSessionScopeProvider) != owner) {
      return;
    }
    if (progress == null) {
      clear(videoId);
    } else {
      state = {...state, videoId: progress};
    }
  }

  void clear(String videoId) {
    if (!state.containsKey(videoId)) return;
    final next = Map<String, double>.from(state)..remove(videoId);
    state = next;
  }
}

final offlineProgressProvider =
    NotifierProvider<OfflineProgressNotifier, Map<String, double>>(
      OfflineProgressNotifier.new,
    );
