import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';

enum WebSocketEventType {
  downloadProgress,
  downloadComplete,
  previewReady,
  newEpisode,
  progressUpdated,
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
      'progress_updated' => WebSocketEventType.progressUpdated,
      'recommendation_ready' => WebSocketEventType.recommendationReady,
      _ => WebSocketEventType.unknown,
    };
    return WebSocketEvent(type: type, data: data);
  }
}

/// Creates a [WebSocketChannel] for [uri]. Injectable for tests.
typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

/// Mints a fresh, short-lived ticket authorizing one WebSocket connection.
/// Called on every (re)connect so the socket carries a ticket — never the
/// long-lived session token — and a stale ticket is refreshed transparently.
typedef WsTicketFetcher = Future<String> Function();

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

  /// Socket URL without the auth query; the ticket is appended fresh on every
  /// [_open] so an expired ticket never sticks. Null when there's no target.
  String? _wsUrl;
  WsTicketFetcher? _ticketFetcher;

  bool _intentionalClose = false;
  bool _disposed = false;
  int _retryCount = 0;

  /// Bumped by every [connect]/[disconnect] so an in-flight async [_open] from
  /// a superseded connection notices it's stale and bails instead of clobbering
  /// the current channel after its ticket fetch resolves.
  int _generation = 0;

  Stream<WebSocketEvent> get events => _eventController.stream;
  bool get isConnected => _channel != null;

  /// Opens (or re-opens) the socket for [userId]. [ticketFetcher] mints a
  /// short-lived access ticket; it's invoked on every connect and reconnect so
  /// the long-lived session token never appears in the URL and an expired
  /// ticket is refreshed automatically.
  void connect(String serverUrl, String userId, WsTicketFetcher ticketFetcher) {
    if (_disposed) return;
    disconnect();
    _intentionalClose = false;
    final wsScheme = serverUrl.startsWith('https') ? 'wss' : 'ws';
    final host = serverUrl
        .replaceFirst('https://', '')
        .replaceFirst('http://', '');
    _wsUrl = '$wsScheme://$host/ws/$userId';
    _ticketFetcher = ticketFetcher;
    _retryCount = 0;
    _open();
  }

  Future<void> _open() async {
    if (_disposed || _intentionalClose) return;
    final wsUrl = _wsUrl;
    final fetcher = _ticketFetcher;
    if (wsUrl == null || fetcher == null) return;

    // Capture the generation before the async gap so a connect()/disconnect()
    // that lands while we await the ticket can be detected below.
    final generation = _generation;
    final String ticket;
    try {
      ticket = await fetcher();
    } catch (_) {
      // Couldn't mint a ticket (offline, or the session is gone). Retry with
      // backoff rather than hanging; a genuinely dead session is torn down by
      // the global 401 handler when other requests fail.
      if (generation == _generation) _scheduleReconnect();
      return;
    }
    // A newer connect()/disconnect() superseded this attempt mid-fetch.
    if (generation != _generation || _disposed || _intentionalClose) return;

    try {
      final channel = _channelFactory(Uri.parse('$wsUrl?ticket=$ticket'));
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
        onDone: () {
          // 4401 = server rejected the ticket at the handshake. We just minted
          // a fresh one, so a reject means the underlying session is dead, not
          // a stale ticket — reconnecting can't help. Wait for the next
          // connect() (which the global 401 sign-out flow triggers).
          if (_channel?.closeCode == 4401) {
            disconnect();
            return;
          }
          _scheduleReconnect();
        },
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
    // Invalidate any in-flight _open() still awaiting a ticket.
    _generation++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _wsUrl = null;
    _ticketFetcher = null;
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
