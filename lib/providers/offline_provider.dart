import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/offline_service.dart';

/// Reactive list of all offline videos. Call `ref.invalidate(offlineVideosProvider)`
/// or `refresh()` after downloads complete or videos are removed.
class OfflineVideosNotifier extends Notifier<List<Map<String, dynamic>>> {
  @override
  List<Map<String, dynamic>> build() {
    final offlineService = ref.watch(offlineServiceProvider);
    // Also marks entries stuck in 'downloading' (e.g. after an app kill)
    // as failed before returning them.
    return offlineService.loadOfflineVideos();
  }

  void refresh() {
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
  @override
  Map<String, double> build() => {};

  /// Sets the progress for [videoId]; `null` clears it.
  void setProgress(String videoId, double? progress) {
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
