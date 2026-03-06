import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video.dart';
import '../services/api_service.dart';

final videoDetailProvider = FutureProvider.family<Video, String>((
  ref,
  videoId,
) async {
  final api = ref.watch(apiServiceProvider);
  return api.getVideo(videoId);
});

final videoProgressProvider =
    StateNotifierProvider.family<VideoProgressNotifier, int, String>((
      ref,
      videoId,
    ) {
      final api = ref.watch(apiServiceProvider);
      return VideoProgressNotifier(api, videoId);
    });

class VideoProgressNotifier extends StateNotifier<int> {
  final ApiService _api;
  final String _videoId;

  VideoProgressNotifier(this._api, this._videoId) : super(0);

  void setPosition(int seconds) {
    state = seconds;
  }

  Future<void> saveProgress() async {
    try {
      await _api.updateProgress(_videoId, state);
    } catch (_) {
      // Silently fail - will retry on next interval
    }
  }

  Future<void> deleteVideo() async {
    await _api.deleteVideo(_videoId);
  }
}
