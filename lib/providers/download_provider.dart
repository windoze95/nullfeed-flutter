import 'package:flutter_riverpod/flutter_riverpod.dart';

class DownloadItem {
  final String videoId;
  final String title;
  final String channelName;
  final double progress;
  final String? speed;
  final String? eta;
  final bool isComplete;

  const DownloadItem({
    required this.videoId,
    required this.title,
    required this.channelName,
    this.progress = 0,
    this.speed,
    this.eta,
    this.isComplete = false,
  });

  DownloadItem copyWith({
    double? progress,
    String? speed,
    String? eta,
    bool? isComplete,
  }) {
    return DownloadItem(
      videoId: videoId,
      title: title,
      channelName: channelName,
      progress: progress ?? this.progress,
      speed: speed ?? this.speed,
      eta: eta ?? this.eta,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

class DownloadNotifier extends StateNotifier<List<DownloadItem>> {
  DownloadNotifier() : super([]);

  void updateProgress({
    required String videoId,
    required String title,
    required String channelName,
    required double progress,
    String? speed,
    String? eta,
  }) {
    final index = state.indexWhere((d) => d.videoId == videoId);
    if (index >= 0) {
      final updated = [...state];
      updated[index] = state[index].copyWith(
        progress: progress,
        speed: speed,
        eta: eta,
      );
      state = updated;
    } else {
      state = [
        ...state,
        DownloadItem(
          videoId: videoId,
          title: title,
          channelName: channelName,
          progress: progress,
          speed: speed,
          eta: eta,
        ),
      ];
    }
  }

  void markComplete(String videoId) {
    final index = state.indexWhere((d) => d.videoId == videoId);
    if (index >= 0) {
      final updated = [...state];
      updated[index] = state[index].copyWith(
        progress: 1.0,
        isComplete: true,
      );
      state = updated;
    }
  }

  void removeCompleted() {
    state = state.where((d) => !d.isComplete).toList();
  }
}

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, List<DownloadItem>>((ref) {
  return DownloadNotifier();
});
