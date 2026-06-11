import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/websocket_service.dart';
import '../services/storage_service.dart';
import '../services/offline_service.dart';
import 'auth_provider.dart';
import 'channel_provider.dart';
import 'download_progress_provider.dart';
import 'feed_provider.dart';
import 'discover_provider.dart';
import 'offline_provider.dart';
import 'video_provider.dart';

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService();
  ref.onDispose(service.dispose);
  return service;
});

final webSocketConnectionProvider = Provider<void>((ref) {
  // Watch only the user id so unrelated auth-state changes (loading flags,
  // error messages, profile lists) don't tear the connection down.
  final userId = ref.watch(
    authStateProvider.select((state) => state.currentUser?.id),
  );
  final storage = ref.watch(storageServiceProvider);
  final wsService = ref.watch(webSocketServiceProvider);

  final serverUrl = storage.getServerUrl();
  final token = storage.getSessionToken();

  if (userId == null || serverUrl == null || token == null) {
    return;
  }

  wsService.connect(serverUrl, userId, token);

  final subscription = wsService.events.listen((event) {
    switch (event.type) {
      case WebSocketEventType.downloadProgress:
        final videoId = event.data['video_id'] as String?;
        final pct = (event.data['percentage'] as num?)?.toDouble();
        if (videoId != null && pct != null) {
          ref
              .read(downloadProgressProvider.notifier)
              .updateProgress(videoId, pct);
        }
      case WebSocketEventType.downloadComplete:
        final videoId = event.data['video_id'] as String?;
        final channelId = event.data['channel_id'] as String?;
        if (videoId != null) {
          ref.read(downloadProgressProvider.notifier).removeProgress(videoId);
          ref.invalidate(videoDetailProvider(videoId));
        }
        if (channelId != null) {
          ref.invalidate(channelVideosProvider(channelId));
        }
        ref.invalidate(continueWatchingProvider);
        ref.invalidate(newEpisodesProvider);
        ref.invalidate(recentlyAddedProvider);
        // Auto-offline: download to device if enabled for this channel
        if (videoId != null && channelId != null) {
          final storageService = ref.read(storageServiceProvider);
          if (storageService.isAutoOfflineEnabled(channelId)) {
            final offlineService = ref.read(offlineServiceProvider);
            unawaited(
              Future<void>(() async {
                await offlineService.downloadToDevice(
                  videoId,
                  channelId: channelId,
                  title: event.data['title'] as String?,
                  youtubeVideoId: event.data['youtube_video_id'] as String?,
                );
              }).whenComplete(() {
                try {
                  ref.read(offlineVideosProvider.notifier).refresh();
                } catch (_) {
                  // Provider container may be gone; nothing to refresh.
                }
              }),
            );
          }
        }
      case WebSocketEventType.previewReady:
        break; // Player screen listens directly via wsService.events
      case WebSocketEventType.newEpisode:
        ref.invalidate(newEpisodesProvider);
        ref.invalidate(recentlyAddedProvider);
      case WebSocketEventType.recommendationReady:
        ref.read(discoverProvider.notifier).load();
      case WebSocketEventType.unknown:
        break;
    }
  });

  ref.onDispose(() {
    subscription.cancel();
    wsService.disconnect();
  });
});
