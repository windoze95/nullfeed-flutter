import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/websocket_service.dart';
import '../services/storage_service.dart';
import 'auth_provider.dart';
import 'download_provider.dart';
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
          ref.read(downloadProvider.notifier).updateProgress(
                videoId: event.data['video_id'] as String? ?? '',
                title: event.data['title'] as String? ?? '',
                channelName: event.data['channel_name'] as String? ?? '',
                progress:
                    (event.data['progress'] as num?)?.toDouble() ?? 0,
                speed: event.data['speed'] as String?,
                eta: event.data['eta'] as String?,
              );
        case WebSocketEventType.downloadComplete:
          final videoId = event.data['video_id'] as String? ?? '';
          ref.read(downloadProvider.notifier).markComplete(videoId);
          ref.invalidate(continueWatchingProvider);
          ref.invalidate(newEpisodesProvider);
          ref.invalidate(recentlyAddedProvider);
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
