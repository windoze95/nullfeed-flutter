import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../config/constants.dart';
import '../models/active_session_scope.dart';
import '../providers/offline_provider.dart';
import '../providers/session_scope_provider.dart';
import 'api_service.dart';

final offlineServiceProvider = Provider<OfflineService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final scope = ref.watch(activeSessionScopeProvider);
  final service = OfflineService(
    apiService: apiService,
    scope: scope,
    onProgress: scope == null
        ? null
        : (videoId, progress) {
            if (ref.read(activeSessionScopeProvider) != scope) return;
            ref
                .read(offlineProgressProvider.notifier)
                .setProgress(scope, videoId, progress);
          },
    onListChanged: scope == null
        ? null
        : () {
            if (ref.read(activeSessionScopeProvider) != scope) return;
            ref.read(offlineVideosProvider.notifier).refresh();
          },
  );
  ref.onDispose(service.dispose);
  return service;
});

class OfflineService {
  final ApiService apiService;
  final ActiveSessionScope? scope;

  /// Reports live download progress (0.0–1.0). `null` clears the entry
  /// (download finished, failed, or was cancelled).
  final void Function(String videoId, double? progress)? onProgress;

  /// Fired whenever the set of offline entries changes (download started,
  /// finished, failed, cancelled) so list UIs can refresh immediately.
  final void Function()? onListChanged;

  final Dio _dio;
  final Future<Directory> Function() _documentsDirectory;
  final Map<String, CancelToken> _cancelTokens = {};
  bool _disposed = false;

  OfflineService({
    required this.apiService,
    required this.scope,
    this.onProgress,
    this.onListChanged,
    Dio? dio,
    Future<Directory> Function()? documentsDirectory,
  }) : _dio = dio ?? Dio(),
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  Box get _box => Hive.box(AppConstants.offlineBox);

  String? get _scopeKey => scope?.cacheKeyPrefix;

  String? _entryKey(String videoId) {
    final owner = _scopeKey;
    if (owner == null) return null;
    return '$owner::offline::${Uri.encodeComponent(videoId)}';
  }

  String _pathComponent(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  Future<String> get _offlineDir async {
    final owner = _scopeKey;
    if (owner == null) {
      throw StateError('Offline storage requires an active session');
    }
    final dir = await _documentsDirectory();
    final offlineDir = Directory(
      '${dir.path}/offline/${_pathComponent(owner)}',
    );
    if (!await offlineDir.exists()) {
      await offlineDir.create(recursive: true);
    }
    return offlineDir.path;
  }

  Map<String, dynamic>? _entry(String videoId) {
    if (_disposed) return null;
    final key = _entryKey(videoId);
    final owner = _scopeKey;
    if (key == null || owner == null) return null;
    final value = _box.get(key);
    if (value is! Map) return null;
    final entry = value.cast<String, dynamic>();
    if (entry['owner_scope'] != owner || entry['video_id'] != videoId) {
      return null;
    }
    return entry;
  }

  Iterable<Map<String, dynamic>> get _ownedEntries sync* {
    final owner = _scopeKey;
    if (_disposed || owner == null) return;
    for (final value in _box.values) {
      if (value is! Map) continue;
      final entry = value.cast<String, dynamic>();
      if (entry['owner_scope'] == owner) yield entry;
    }
  }

  /// Merges [updates] into the stored entry for [videoId].
  /// No-op if the entry was removed concurrently (e.g. deleted mid-download).
  void _updateEntry(String videoId, Map<String, dynamic> updates) {
    final key = _entryKey(videoId);
    final entry = _entry(videoId);
    if (key == null || entry == null) return;
    _box.put(key, {...entry, ...updates});
  }

  void _reportProgress(String videoId, double? progress) {
    if (!_disposed) onProgress?.call(videoId, progress);
  }

  void _reportListChanged() {
    if (!_disposed) onListChanged?.call();
  }

  Future<void> _deleteEntryAndFile(String videoId, String? localPath) async {
    final key = _entryKey(videoId);
    if (key != null) await _box.delete(key);
    if (localPath == null) return;
    final file = File(localPath);
    if (await file.exists()) await file.delete();
  }

  Future<void> downloadToDevice(
    String videoId, {
    String? channelId,
    String? title,
    String? youtubeVideoId,
  }) async {
    // Web has no on-device filesystem; offline save is unsupported there. The
    // UI hides it, but guard defensively so a stray call can't throw.
    if (kIsWeb || _disposed || scope == null) return;
    // In-flight guard: a second tap must not start a concurrent download
    // writing to the same file. Registered before the first await.
    if (_cancelTokens.containsKey(videoId)) return;
    final cancelToken = CancelToken();
    _cancelTokens[videoId] = cancelToken;
    String? localPath;

    try {
      final key = _entryKey(videoId)!;
      final owner = _scopeKey!;
      final dir = await _offlineDir;
      localPath = '$dir/${_pathComponent(videoId)}.mp4';
      if (_disposed || cancelToken.isCancelled) {
        await _deleteEntryAndFile(videoId, localPath);
        return;
      }

      await _box.put(key, {
        'owner_scope': owner,
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
      _reportProgress(videoId, 0.0);
      _reportListChanged();

      // Mint the ticketed stream URL here (not before the entry is written) so
      // a failed ticket mint marks the download failed via the catch below
      // rather than escaping the method and stranding the in-flight guard.
      final url = await apiService.getVideoStreamUrl(videoId);
      if (_disposed || cancelToken.isCancelled) {
        await _deleteEntryAndFile(videoId, localPath);
        return;
      }
      await _dio.download(
        url,
        localPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (!_disposed && !cancelToken.isCancelled && total > 0) {
            final progress = received / total;
            _updateEntry(videoId, {
              'progress': progress,
              'file_size_bytes': total,
            });
            _reportProgress(videoId, progress);
          }
        },
      );

      if (_disposed || cancelToken.isCancelled) {
        await _deleteEntryAndFile(videoId, localPath);
        return;
      }
      final file = File(localPath);
      final fileSize = await file.length();
      _updateEntry(videoId, {
        'status': 'complete',
        'progress': 1.0,
        'file_size_bytes': fileSize,
        'downloaded_at': DateTime.now().toIso8601String(),
      });
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel || _disposed) {
        await _deleteEntryAndFile(videoId, localPath);
      } else {
        _updateEntry(videoId, {'status': 'failed'});
      }
    } catch (_) {
      // Couldn't mint a playback ticket (or any other unexpected error) — mark
      // the entry failed so the UI can offer a retry.
      if (_disposed) {
        await _deleteEntryAndFile(videoId, localPath);
      } else {
        _updateEntry(videoId, {'status': 'failed'});
      }
    } finally {
      _cancelTokens.remove(videoId);
      _reportProgress(videoId, null);
      _reportListChanged();
    }
  }

  /// Returns all offline entries after marking entries stuck in
  /// 'downloading' (no active download — e.g. the app was killed) as failed.
  /// Call on app start.
  List<Map<String, dynamic>> loadOfflineVideos() {
    for (final entry in _ownedEntries.toList()) {
      final videoId = entry['video_id'] as String?;
      if (videoId == null) continue;
      if (entry['status'] == 'downloading' &&
          !_cancelTokens.containsKey(videoId)) {
        _updateEntry(videoId, {'status': 'failed'});
      }
    }
    return getOfflineVideos();
  }

  Future<void> removeOfflineVideo(String videoId) async {
    final entry = _entry(videoId);
    if (entry != null) {
      await _deleteEntryAndFile(videoId, entry['local_path'] as String?);
      _reportListChanged();
    }
  }

  bool isAvailableOffline(String videoId) {
    return _entry(videoId)?['status'] == 'complete';
  }

  String? getLocalPath(String videoId) {
    final entry = _entry(videoId);
    if (entry == null) return null;
    if (entry['status'] != 'complete') return null;
    return entry['local_path'] as String?;
  }

  /// Locally cached watch position in seconds (used for offline playback).
  int getWatchPosition(String videoId) {
    final entry = _entry(videoId);
    if (entry == null) return 0;
    return (entry['watch_position'] as num?)?.toInt() ?? 0;
  }

  Future<void> setWatchPosition(String videoId, int seconds) async {
    final key = _entryKey(videoId);
    final entry = _entry(videoId);
    if (key == null || entry == null) return;
    await _box.put(key, {...entry, 'watch_position': seconds});
  }

  List<Map<String, dynamic>> getOfflineVideos() {
    return _ownedEntries
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  int getTotalOfflineSize() {
    int total = 0;
    for (final entry in _ownedEntries) {
      total += (entry['file_size_bytes'] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  void cancelDownload(String videoId) {
    final token = _cancelTokens[videoId];
    if (token != null && !token.isCancelled) {
      token.cancel('User cancelled download');
    }
  }

  /// Stops all work owned by this immutable scope. A provider rebuild on
  /// profile/server change disposes the old instance before exposing the new
  /// one, so its late callbacks cannot mutate the new profile's UI state.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) token.cancel('Offline scope changed');
    }
  }
}
