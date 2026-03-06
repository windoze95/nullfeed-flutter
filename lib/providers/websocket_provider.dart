import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/websocket_service.dart';
import '../services/storage_service.dart';
import '../services/offline_service.dart';
import 'auth_provider.dart';
import 'download_progress_provider.dart';
import 'feed_provider.dart';
import 'discover_provider.dart';

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService();
  ref.onDispose(service.dispose);
  return service;
});

final webSocketConnectionProvider = Provider<void>((ref) {
  final authState = ref.watch(authStateProvider);
  final storage = ref.watch(storageServiceProvider);
  final wsService = ref.watch(webSocketServiceProvider);

  final user = authState.currentUser;
  final serverUrl = storage.getServerUrl();

  if (user != null && serverUrl != null) {
    wsService.connect(serverUrl, user.id);

    StreamSubscription<WebSocketEvent>? subscription;
    subscription = wsService.events.listen((event) {
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
          final completedId = event.data['video_id'] as String?;
          if (completedId != null) {
            ref
                .read(downloadProgressProvider.notifier)
                .removeProgress(completedId);
          }
          ref.invalidate(continueWatchingProvider);
          ref.invalidate(newEpisodesProvider);
          ref.invalidate(recentlyAddedProvider);
          // Auto-offline: download to device if enabled for this channel
          final channelId = event.data['channel_id'] as String?;
          if (channelId != null) {
            final storageService = ref.read(storageServiceProvider);
            if (storageService.isAutoOfflineEnabled(channelId)) {
              final offlineService = ref.read(offlineServiceProvider);
              final videoId = event.data['video_id'] as String;
              offlineService.downloadToDevice(videoId, channelId: channelId);
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
      subscription?.cancel();
      wsService.disconnect();
    });
  }
});
