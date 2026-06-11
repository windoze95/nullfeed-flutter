import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nullfeed/services/websocket_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Fake channel whose stream is driven by the test. Closing the sink (which
/// the service does on disconnect) also ends the stream, like a real socket.
class _FakeChannel extends Fake implements WebSocketChannel {
  final controller = StreamController<dynamic>();
  bool sinkClosed = false;
  late final _FakeSink _sink = _FakeSink(this);

  @override
  int? closeCode;

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  WebSocketSink get sink => _sink;

  void emit(Map<String, dynamic> json) => controller.add(jsonEncode(json));

  /// Simulates the server dropping the connection.
  void drop({int? code}) {
    closeCode = code;
    unawaited(controller.close());
  }
}

class _FakeSink extends Fake implements WebSocketSink {
  _FakeSink(this._channel);

  final _FakeChannel _channel;

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _channel.sinkClosed = true;
    if (!_channel.controller.isClosed) {
      await _channel.controller.close();
    }
  }
}

/// Records every channel the service opens, in order.
class _ChannelFactory {
  final channels = <_FakeChannel>[];
  final uris = <Uri>[];

  WebSocketChannel call(Uri uri) {
    uris.add(uri);
    final channel = _FakeChannel();
    channels.add(channel);
    return channel;
  }
}

Map<String, dynamic> _progressEvent(String videoId) => {
  'type': 'download_progress',
  'data': {'video_id': videoId, 'percentage': 42},
};

void main() {
  late _ChannelFactory factory;
  late WebSocketService service;

  setUp(() {
    factory = _ChannelFactory();
    service = WebSocketService(channelFactory: factory.call);
  });

  group('WebSocketEvent.fromJson', () {
    test('maps every known event type', () {
      const cases = {
        'download_progress': WebSocketEventType.downloadProgress,
        'download_complete': WebSocketEventType.downloadComplete,
        'preview_ready': WebSocketEventType.previewReady,
        'new_episode': WebSocketEventType.newEpisode,
        'recommendation_ready': WebSocketEventType.recommendationReady,
        'something_else': WebSocketEventType.unknown,
      };

      cases.forEach((typeString, expected) {
        final event = WebSocketEvent.fromJson({
          'type': typeString,
          'data': {'video_id': 'v1'},
        });
        expect(event.type, expected, reason: typeString);
        expect(event.data['video_id'], 'v1', reason: typeString);
      });
    });

    test('tolerates missing type and data', () {
      final event = WebSocketEvent.fromJson(const {});
      expect(event.type, WebSocketEventType.unknown);
      expect(event.data, isEmpty);
    });
  });

  group('connect', () {
    test('builds a ws URI with the user id and token appended', () {
      service.connect('http://192.168.1.50:8484', 'user-1', 'tok123');

      expect(
        factory.uris.single.toString(),
        'ws://192.168.1.50:8484/ws/user-1?token=tok123',
      );
      expect(service.isConnected, isTrue);

      service.dispose();
    });

    test('uses wss for https servers', () {
      service.connect('https://nullfeed.example.com', 'u1', 't');

      expect(
        factory.uris.single.toString(),
        'wss://nullfeed.example.com/ws/u1?token=t',
      );

      service.dispose();
    });

    test('connecting again closes the previous channel', () {
      service.connect('http://h1', 'u1', 't1');
      service.connect('http://h2', 'u1', 't2');

      expect(factory.channels, hasLength(2));
      expect(factory.channels.first.sinkClosed, isTrue);
      expect(factory.uris.last.host, 'h2');

      service.dispose();
    });
  });

  group('events', () {
    test('parses incoming messages and skips malformed ones', () async {
      final events = <WebSocketEvent>[];
      final subscription = service.events.listen(events.add);
      service.connect('http://h', 'u1', 't');

      final channel = factory.channels.single;
      channel.emit(_progressEvent('v1'));
      channel.controller.add('not json at all');
      channel.emit({'type': 'new_episode', 'data': <String, dynamic>{}});
      await pumpEventQueue();

      expect(events, hasLength(2));
      expect(events.first.type, WebSocketEventType.downloadProgress);
      expect(events.first.data['video_id'], 'v1');
      expect(events.last.type, WebSocketEventType.newEpisode);

      await subscription.cancel();
      service.dispose();
    });

    test('dispose closes the events stream', () async {
      var done = false;
      service.events.listen(null, onDone: () => done = true);

      service.dispose();
      await pumpEventQueue();

      expect(done, isTrue);
    });
  });

  group('reconnect state machine', () {
    testWidgets('reconnects after the connection drops', (tester) async {
      service.connect('http://h', 'u1', 't');
      expect(factory.channels, hasLength(1));

      factory.channels.single.drop();
      await tester.pump();
      expect(factory.channels, hasLength(1), reason: 'retry is delayed');

      // First retry delay is 1s plus up to 250ms of jitter.
      await tester.pump(const Duration(milliseconds: 1300));
      expect(factory.channels, hasLength(2));

      service.dispose();
    });

    testWidgets('does not reconnect after a 4401 auth reject', (tester) async {
      service.connect('http://h', 'u1', 't');
      expect(factory.channels, hasLength(1));

      // Server closes with the auth-reject code: same token can never work.
      factory.channels.single.drop(code: 4401);
      await tester.pump();
      await tester.pump(const Duration(seconds: 35));
      expect(factory.channels, hasLength(1));

      // An explicit reconnect (e.g. with a fresh token) still works.
      service.connect('http://h', 'u1', 't2');
      expect(factory.channels, hasLength(2));

      service.dispose();
    });

    testWidgets('retries when opening the channel throws', (tester) async {
      var calls = 0;
      final fallback = _FakeChannel();
      final throwingService = WebSocketService(
        channelFactory: (uri) {
          calls++;
          if (calls == 1) throw const SocketExceptionFake();
          return fallback;
        },
      );

      throwingService.connect('http://h', 'u1', 't');
      expect(calls, 1);

      await tester.pump(const Duration(milliseconds: 1300));
      expect(calls, 2);

      throwingService.dispose();
    });

    testWidgets('backoff grows and resets after a successful message', (
      tester,
    ) async {
      service.connect('http://h', 'u1', 't');

      // Failure #1: retry within [1000ms, 1250ms].
      factory.channels.last.drop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));
      expect(factory.channels, hasLength(2));

      // Failure #2: retry within [2000ms, 2500ms] — NOT within 1300ms.
      factory.channels.last.drop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));
      expect(factory.channels, hasLength(2), reason: 'backoff has grown');
      await tester.pump(const Duration(milliseconds: 1300));
      expect(factory.channels, hasLength(3));

      // A successful message resets the backoff to the base delay.
      factory.channels.last.emit(_progressEvent('v1'));
      await tester.pump();
      factory.channels.last.drop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));
      expect(
        factory.channels,
        hasLength(4),
        reason: 'retry counter was reset by the successful message',
      );

      service.dispose();
    });

    testWidgets('never reconnects after disconnect()', (tester) async {
      service.connect('http://h', 'u1', 't');
      service.disconnect();
      expect(service.isConnected, isFalse);
      expect(factory.channels.single.sinkClosed, isTrue);

      // Longer than the 30s delay cap plus maximum jitter.
      await tester.pump(const Duration(seconds: 40));
      expect(factory.channels, hasLength(1));
    });

    testWidgets('disconnect() cancels a pending retry', (tester) async {
      service.connect('http://h', 'u1', 't');
      factory.channels.single.drop();
      await tester.pump();

      service.disconnect();
      await tester.pump(const Duration(seconds: 40));
      expect(factory.channels, hasLength(1));
    });

    testWidgets('never reconnects after dispose()', (tester) async {
      service.connect('http://h', 'u1', 't');
      factory.channels.single.drop();
      await tester.pump();

      service.dispose();
      await tester.pump(const Duration(seconds: 40));
      expect(factory.channels, hasLength(1));
    });

    testWidgets('connect() after disconnect() opens a fresh connection', (
      tester,
    ) async {
      final events = <WebSocketEvent>[];
      service.events.listen(events.add);

      service.connect('http://h', 'u1', 't');
      service.disconnect();
      service.connect('http://h', 'u1', 't2');

      expect(factory.channels, hasLength(2));
      factory.channels.last.emit(_progressEvent('v2'));
      await tester.pump();

      expect(events.single.data['video_id'], 'v2');

      service.dispose();
    });
  });
}

/// Minimal stand-in for a socket failure thrown by the channel factory.
class SocketExceptionFake implements Exception {
  const SocketExceptionFake();
}
