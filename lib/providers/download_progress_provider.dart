import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ephemeral map of video_id → download percentage (0.0–100.0).
/// Updated via WebSocket events, not persisted.
class DownloadProgressNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => {};

  void updateProgress(String videoId, double pct) {
    state = {...state, videoId: pct};
  }

  void removeProgress(String videoId) {
    final current = Map<String, double>.from(state);
    current.remove(videoId);
    state = current;
  }
}

final downloadProgressProvider =
    NotifierProvider<DownloadProgressNotifier, Map<String, double>>(
      DownloadProgressNotifier.new,
    );
