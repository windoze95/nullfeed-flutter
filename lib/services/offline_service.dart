import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../config/constants.dart';
import 'api_service.dart';

final offlineServiceProvider = Provider<OfflineService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return OfflineService(apiService: apiService);
});

class OfflineService {
  final ApiService apiService;
  final Dio _dio = Dio();
  final Map<String, CancelToken> _cancelTokens = {};

  OfflineService({required this.apiService});

  Box get _box => Hive.box(AppConstants.offlineBox);

  Future<String> get _offlineDir async {
    final dir = await getApplicationDocumentsDirectory();
    final offlineDir = Directory('${dir.path}/offline');
    if (!await offlineDir.exists()) {
      await offlineDir.create(recursive: true);
    }
    return offlineDir.path;
  }

  Future<void> downloadToDevice(
    String videoId, {
    String? channelId,
    String? title,
    String? youtubeVideoId,
  }) async {
    final dir = await _offlineDir;
    final localPath = '$dir/$videoId.mp4';
    final url = apiService.getVideoStreamUrl(videoId);
    final cancelToken = CancelToken();
    _cancelTokens[videoId] = cancelToken;

    await _box.put(videoId, {
      'video_id': videoId,
      'channel_id': channelId ?? '',
      'title': title ?? '',
      'youtube_video_id': youtubeVideoId ?? '',
      'local_path': localPath,
      'file_size_bytes': 0,
      'status': 'downloading',
      'progress': 0.0,
      'downloaded_at': DateTime.now().toIso8601String(),
    });

    try {
      await _dio.download(
        url,
        localPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            _box.put(videoId, {
              ...(_box.get(videoId) as Map).cast<String, dynamic>(),
              'progress': progress,
              'file_size_bytes': total,
            });
          }
        },
      );

      final file = File(localPath);
      final fileSize = await file.length();
      _box.put(videoId, {
        ...(_box.get(videoId) as Map).cast<String, dynamic>(),
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
        _box.put(videoId, {
          ...(_box.get(videoId) as Map).cast<String, dynamic>(),
          'status': 'failed',
        });
      }
    } finally {
      _cancelTokens.remove(videoId);
    }
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
