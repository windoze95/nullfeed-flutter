import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/websocket_service.dart';
import '../services/storage_service.dart';
import '../services/offline_service.dart';
import '../services/api_service.dart';
import 'channel_provider.dart';
import 'feed_provider.dart';
import 'discover_provider.dart';
import 'offline_provider.dart';
import 'video_provider.dart';
import 'session_scope_provider.dart';

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService();
  ref.onDispose(service.dispose);
  return service;
});

final webSocketConnectionProvider = Provider<void>((ref) {
  // The scope changes only when the authenticated server/profile boundary
  // changes, so unrelated auth loading/error state never tears down the socket.
  final scope = ref.watch(activeSessionScopeProvider);
  final storage = ref.watch(storageServiceProvider);
  final apiService = ref.watch(apiServiceProvider);
  final wsService = ref.watch(webSocketServiceProvider);

  final token = storage.getSessionToken();

  // A stored token gates connecting (we must be signed in) but never goes into
  // the URL — the socket authenticates with a short-lived ticket minted per
  // connection via [ApiService.getWsTicket].
  if (scope == null || token == null) {
    return;
  }

  wsService.connect(scope.serverUrl, scope.userId, apiService.getWsTicket);

  final subscription = wsService.events.listen((event) {
    switch (event.type) {
      case WebSocketEventType.downloadProgress:
        // Caching is invisible — download progress is no longer surfaced.
        break;
      case WebSocketEventType.downloadComplete:
        final videoId = event.data['video_id'] as String?;
        final channelId = event.data['channel_id'] as String?;
        if (videoId != null) {
          ref.invalidate(videoDetailProvider(videoId));
        }
        if (channelId != null) {
          ref.invalidate(channelVideosProvider(channelId));
        }
        ref.invalidate(continueWatchingProvider);
        ref.invalidate(newEpisodesProvider);
        ref.invalidate(recentlyAddedProvider);
        ref.invalidate(homeFeedProvider);
        // Auto-offline: download to device if enabled for this channel.
        // Web has no on-device storage, so it never auto-saves.
        if (!kIsWeb && videoId != null && channelId != null) {
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
      case WebSocketEventType.adSegmentsReady:
        break; // Player screen listens directly via wsService.events
      case WebSocketEventType.newEpisode:
        // New content landed server-side — refresh the home feed in place.
        ref.invalidate(newEpisodesProvider);
        ref.invalidate(recentlyAddedProvider);
        ref.invalidate(homeFeedProvider);
      case WebSocketEventType.progressUpdated:
        // Cross-device watch-progress sync: another device moved the playhead,
        // so resume positions and continue-watching ordering may have changed.
        final videoId = event.data['video_id'] as String?;
        if (videoId != null) {
          ref.invalidate(videoDetailProvider(videoId));
        }
        ref.invalidate(continueWatchingProvider);
        ref.invalidate(homeFeedProvider);
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
