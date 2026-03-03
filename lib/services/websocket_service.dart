import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

enum WebSocketEventType {
  downloadProgress,
  downloadComplete,
  newEpisode,
  recommendationReady,
  unknown,
}

class WebSocketEvent {
  final WebSocketEventType type;
  final Map<String, dynamic> data;

  const WebSocketEvent({required this.type, required this.data});

  factory WebSocketEvent.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? '';
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final type = switch (typeStr) {
      'download_progress' => WebSocketEventType.downloadProgress,
      'download_complete' => WebSocketEventType.downloadComplete,
      'new_episode' => WebSocketEventType.newEpisode,
      'recommendation_ready' => WebSocketEventType.recommendationReady,
      _ => WebSocketEventType.unknown,
    };
    return WebSocketEvent(type: type, data: data);
  }
}

class WebSocketService {
  WebSocketChannel? _channel;
  final _eventController = StreamController<WebSocketEvent>.broadcast();
  Timer? _reconnectTimer;
  String? _url;

  Stream<WebSocketEvent> get events => _eventController.stream;
  bool get isConnected => _channel != null;

  void connect(String serverUrl, String userId) {
    disconnect();
    final wsScheme = serverUrl.startsWith('https') ? 'wss' : 'ws';
    final host = serverUrl
        .replaceFirst('https://', '')
        .replaceFirst('http://', '');
    _url = '$wsScheme://$host/ws/$userId';
    _doConnect();
  }

  void _doConnect() {
    if (_url == null) return;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_url!));
      _channel!.stream.listen(
        (message) {
          try {
            final json = jsonDecode(message as String) as Map<String, dynamic>;
            _eventController.add(WebSocketEvent.fromJson(json));
          } catch (_) {
            // Ignore malformed messages
          }
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _channel = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _doConnect);
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }
}
