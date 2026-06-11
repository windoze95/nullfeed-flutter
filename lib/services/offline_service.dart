import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../config/constants.dart';
import '../providers/offline_provider.dart';
import 'api_service.dart';

final offlineServiceProvider = Provider<OfflineService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return OfflineService(
    apiService: apiService,
    onProgress: (videoId, progress) => ref
        .read(offlineProgressProvider.notifier)
        .setProgress(videoId, progress),
    onListChanged: () => ref.read(offlineVideosProvider.notifier).refresh(),
  );
});

class OfflineService {
  final ApiService apiService;

  /// Reports live download progress (0.0–1.0). `null` clears the entry
  /// (download finished, failed, or was cancelled).
  final void Function(String videoId, double? progress)? onProgress;

  /// Fired whenever the set of offline entries changes (download started,
  /// finished, failed, cancelled) so list UIs can refresh immediately.
  final void Function()? onListChanged;

  final Dio _dio = Dio();
  final Map<String, CancelToken> _cancelTokens = {};

  OfflineService({
    required this.apiService,
    this.onProgress,
    this.onListChanged,
  });

  Box get _box => Hive.box(AppConstants.offlineBox);

  Future<String> get _offlineDir async {
    final dir = await getApplicationDocumentsDirectory();
    final offlineDir = Directory('${dir.path}/offline');
    if (!await offlineDir.exists()) {
      await offlineDir.create(recursive: true);
    }
    return offlineDir.path;
  }

  /// Merges [updates] into the stored entry for [videoId].
  /// No-op if the entry was removed concurrently (e.g. deleted mid-download).
  void _updateEntry(String videoId, Map<String, dynamic> updates) {
    final entry = _box.get(videoId);
    if (entry == null) return;
    _box.put(videoId, {...(entry as Map).cast<String, dynamic>(), ...updates});
  }

  Future<void> downloadToDevice(
    String videoId, {
    String? channelId,
    String? title,
    String? youtubeVideoId,
  }) async {
    // In-flight guard: a second tap must not start a concurrent download
    // writing to the same file. Registered before the first await.
    if (_cancelTokens.containsKey(videoId)) return;
    final cancelToken = CancelToken();
    _cancelTokens[videoId] = cancelToken;

    final dir = await _offlineDir;
    final localPath = '$dir/$videoId.mp4';
    final url = apiService.getVideoStreamUrl(videoId);

    await _box.put(videoId, {
      'video_id': videoId,
      'channel_id': channelId ?? '',
      'title': title ?? '',
      'youtube_video_id': youtubeVideoId ?? '',
      'local_path': localPath,
      'file_size_bytes': 0,
      'status': 'downloading',
      'progress': 0.0,
      'watch_position': getWatchPosition(videoId),
      'downloaded_at': DateTime.now().toIso8601String(),
    });
    onProgress?.call(videoId, 0.0);
    onListChanged?.call();

    try {
      await _dio.download(
        url,
        localPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            _updateEntry(videoId, {
              'progress': progress,
              'file_size_bytes': total,
            });
            onProgress?.call(videoId, progress);
          }
        },
      );

      final file = File(localPath);
      final fileSize = await file.length();
      _updateEntry(videoId, {
        'status': 'complete',
        'progress': 1.0,
        'file_size_bytes': fileSize,
        'downloaded_at': DateTime.now().toIso8601String(),
      });
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        await _box.delete(videoId);
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } else {
        _updateEntry(videoId, {'status': 'failed'});
      }
    } finally {
      _cancelTokens.remove(videoId);
      onProgress?.call(videoId, null);
      onListChanged?.call();
    }
  }

  /// Returns all offline entries after marking entries stuck in
  /// 'downloading' (no active download — e.g. the app was killed) as failed.
  /// Call on app start.
  List<Map<String, dynamic>> loadOfflineVideos() {
    for (final key in _box.keys.toList()) {
      final entry = _box.get(key);
      if (entry == null) continue;
      final map = (entry as Map).cast<String, dynamic>();
      if (map['status'] == 'downloading' && !_cancelTokens.containsKey(key)) {
        _box.put(key, {...map, 'status': 'failed'});
      }
    }
    return getOfflineVideos();
  }

  Future<void> removeOfflineVideo(String videoId) async {
    final entry = _box.get(videoId);
    if (entry != null) {
      final localPath = (entry as Map)['local_path'] as String?;
      if (localPath != null) {
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      await _box.delete(videoId);
    }
  }

  bool isAvailableOffline(String videoId) {
    final entry = _box.get(videoId);
    if (entry == null) return false;
    return (entry as Map)['status'] == 'complete';
  }

  String? getLocalPath(String videoId) {
    final entry = _box.get(videoId);
    if (entry == null) return null;
    final map = entry as Map;
    if (map['status'] != 'complete') return null;
    return map['local_path'] as String?;
  }

  /// Locally cached watch position in seconds (used for offline playback).
  int getWatchPosition(String videoId) {
    final entry = _box.get(videoId);
    if (entry == null) return 0;
    return ((entry as Map)['watch_position'] as num?)?.toInt() ?? 0;
  }

  Future<void> setWatchPosition(String videoId, int seconds) async {
    final entry = _box.get(videoId);
    if (entry == null) return;
    await _box.put(videoId, {
      ...(entry as Map).cast<String, dynamic>(),
      'watch_position': seconds,
    });
  }

  List<Map<String, dynamic>> getOfflineVideos() {
    return _box.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  int getTotalOfflineSize() {
    int total = 0;
    for (final entry in _box.values) {
      final map = entry as Map;
      total += (map['file_size_bytes'] as int? ?? 0);
    }
    return total;
  }

  void cancelDownload(String videoId) {
    final token = _cancelTokens[videoId];
    if (token != null && !token.isCancelled) {
      token.cancel('User cancelled download');
    }
  }
}
