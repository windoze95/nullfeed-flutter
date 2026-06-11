import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';

enum WebSocketEventType {
  downloadProgress,
  downloadComplete,
  previewReady,
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
      'preview_ready' => WebSocketEventType.previewReady,
      'new_episode' => WebSocketEventType.newEpisode,
      'recommendation_ready' => WebSocketEventType.recommendationReady,
      _ => WebSocketEventType.unknown,
    };
    return WebSocketEvent(type: type, data: data);
  }
}

/// Creates a [WebSocketChannel] for [uri]. Injectable for tests.
typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

class WebSocketService {
  WebSocketService({WebSocketChannelFactory? channelFactory})
    : _channelFactory = channelFactory ?? WebSocketChannel.connect;

  static const _baseRetryDelay = Duration(seconds: 1);
  static const _maxRetryDelay = Duration(seconds: 30);

  final WebSocketChannelFactory _channelFactory;
  final _eventController = StreamController<WebSocketEvent>.broadcast();
  final _random = Random();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Uri? _uri;
  bool _intentionalClose = false;
  bool _disposed = false;
  int _retryCount = 0;

  Stream<WebSocketEvent> get events => _eventController.stream;
  bool get isConnected => _channel != null;

  /// Opens (or re-opens) the socket for [userId], authenticating with [token].
  void connect(String serverUrl, String userId, String token) {
    if (_disposed) return;
    disconnect();
    _intentionalClose = false;
    final wsScheme = serverUrl.startsWith('https') ? 'wss' : 'ws';
    final host = serverUrl
        .replaceFirst('https://', '')
        .replaceFirst('http://', '');
    _uri = Uri.parse('$wsScheme://$host/ws/$userId?token=$token');
    _retryCount = 0;
    _open();
  }

  void _open() {
    if (_disposed || _intentionalClose || _uri == null) return;
    try {
      final channel = _channelFactory(_uri!);
      _channel = channel;
      _subscription = channel.stream.listen(
        (message) {
          // A successful message means the connection is healthy again.
          _retryCount = 0;
          try {
            final json = jsonDecode(message as String) as Map<String, dynamic>;
            if (!_eventController.isClosed) {
              _eventController.add(WebSocketEvent.fromJson(json));
            }
          } catch (_) {
            // Ignore malformed messages
          }
        },
        onError: (Object _) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (_disposed || _intentionalClose) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_nextRetryDelay(), _open);
  }

  /// Exponential backoff with jitter: 1s, 2s, 4s, ... capped at 30s.
  Duration _nextRetryDelay() {
    final baseMs = min(
      _baseRetryDelay.inMilliseconds * pow(2, _retryCount).toInt(),
      _maxRetryDelay.inMilliseconds,
    );
    if (_retryCount < 10) _retryCount++;
    final jitterMs = _random.nextInt(baseMs ~/ 4 + 1);
    return Duration(milliseconds: baseMs + jitterMs);
  }

  /// Closes the socket and prevents any further reconnect attempts until the
  /// next explicit [connect] call.
  void disconnect() {
    _intentionalClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _uri = null;
    _retryCount = 0;
  }

  void dispose() {
    disconnect();
    _disposed = true;
    if (!_eventController.isClosed) {
      _eventController.close();
    }
  }
}
