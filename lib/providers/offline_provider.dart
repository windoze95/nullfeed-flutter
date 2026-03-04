import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/offline_service.dart';

/// Reactive list of all offline videos. Call `ref.invalidate(offlineVideosProvider)`
/// after downloads complete or videos are removed to refresh.
final offlineVideosProvider =
    StateNotifierProvider<OfflineVideosNotifier, List<Map<String, dynamic>>>(
        (ref) {
  final offlineService = ref.watch(offlineServiceProvider);
  return OfflineVideosNotifier(offlineService);
});

class OfflineVideosNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  final OfflineService _offlineService;

  OfflineVideosNotifier(this._offlineService)
      : super([]) {
    refresh();
  }

  void refresh() {
    state = _offlineService.getOfflineVideos();
  }
}

/// Offline status for a specific video: 'downloading', 'complete', 'failed', or null.
final offlineStatusProvider =
    Provider.family<String?, String>((ref, videoId) {
  final videos = ref.watch(offlineVideosProvider);
  try {
    final entry = videos.firstWhere((v) => v['video_id'] == videoId);
    return entry['status'] as String?;
  } catch (_) {
    return null;
  }
});

/// Ephemeral map of video_id -> download progress (0.0-1.0).
final offlineProgressProvider =
    StateProvider<Map<String, double>>((ref) => {});
