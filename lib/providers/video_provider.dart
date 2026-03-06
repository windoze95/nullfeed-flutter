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

class VideoProgressNotifier extends Notifier<int> {
  late final String _videoId;

  @override
  int build() => 0;

  void init(String videoId) {
    _videoId = videoId;
  }

  ApiService get _api => ref.read(apiServiceProvider);

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

final videoProgressProvider =
    NotifierProvider.family<VideoProgressNotifier, int, String>((videoId) {
      final notifier = VideoProgressNotifier();
      notifier.init(videoId);
      return notifier;
    });
