import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nullfeed/config/constants.dart';
import 'package:nullfeed/services/api_service.dart';

import '../helpers/test_helpers.dart';

/// Minimal [HttpClientAdapter] that records every request and returns a canned
/// response built by [handler]. Lets us drive [ApiService] without real HTTP.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  late FakeStorageService storage;

  setUp(() {
    storage = FakeStorageService(serverUrl: 'http://server:8484');
  });

  ApiService apiWith(_FakeAdapter adapter) {
    final dio = Dio()..httpClientAdapter = adapter;
    return ApiService(storage: storage, dio: dio);
  }

  int postsTo(_FakeAdapter adapter, bool Function(String path) match) =>
      adapter.requests.where((r) => match(r.uri.path)).length;

  group('getPlaybackTicket', () {
    test('POSTs the playback-ticket endpoint and returns the ticket', () async {
      final adapter = _FakeAdapter(
        (_) => _json({'ticket': 'pt-1', 'expires_in': 300}),
      );
      final api = apiWith(adapter);

      final ticket = await api.getPlaybackTicket('vid-1');

      expect(ticket, 'pt-1');
      expect(adapter.requests.single.method, 'POST');
      expect(
        adapter.requests.single.uri.toString(),
        'http://server:8484${AppConstants.videoPlaybackTicket('vid-1')}',
      );
    });

    test('caches per video and refetches only for a new video', () async {
      var n = 0;
      final adapter = _FakeAdapter(
        (_) => _json({'ticket': 'pt-${++n}', 'expires_in': 300}),
      );
      final api = apiWith(adapter);

      expect(await api.getPlaybackTicket('vid-1'), 'pt-1');
      expect(
        await api.getPlaybackTicket('vid-1'),
        'pt-1',
        reason: 'same video reuses the cached ticket',
      );
      expect(postsTo(adapter, (p) => p.endsWith('/playback-ticket')), 1);

      expect(
        await api.getPlaybackTicket('vid-2'),
        'pt-2',
        reason: 'a different video refetches',
      );
      expect(postsTo(adapter, (p) => p.endsWith('/playback-ticket')), 2);
    });

    test('refetches once a cached ticket nears expiry', () async {
      var n = 0;
      // 20s TTL minus the 30s refresh margin => already stale, so each call
      // mints afresh.
      final adapter = _FakeAdapter(
        (_) => _json({'ticket': 'pt-${++n}', 'expires_in': 20}),
      );
      final api = apiWith(adapter);

      expect(await api.getPlaybackTicket('vid-1'), 'pt-1');
      expect(
        await api.getPlaybackTicket('vid-1'),
        'pt-2',
        reason: 'a near-expired ticket is not reused',
      );
    });
  });

  group('stream URLs', () {
    test(
      'getVideoStreamUrl carries a ticket, never the session token',
      () async {
        await storage.setSessionToken('sess-token');
        final adapter = _FakeAdapter(
          (_) => _json({'ticket': 'pt-9', 'expires_in': 300}),
        );
        final api = apiWith(adapter);

        final url = await api.getVideoStreamUrl('vid-7');

        expect(
          url,
          'http://server:8484${AppConstants.videoStream('vid-7')}?ticket=pt-9',
        );
        expect(url, isNot(contains('token=')));
        expect(url, isNot(contains('sess-token')));
      },
    );

    test(
      'stream, instant, and preview URLs share one playback ticket',
      () async {
        var n = 0;
        final adapter = _FakeAdapter(
          (_) => _json({'ticket': 'pt-${++n}', 'expires_in': 300}),
        );
        final api = apiWith(adapter);

        final streamUrl = await api.getVideoStreamUrl('vid-3');
        final instantUrl = await api.getInstantStreamUrl('vid-3');
        final previewUrl = await api.getPreviewStreamUrl('vid-3');

        expect(
          streamUrl,
          endsWith('${AppConstants.videoStream('vid-3')}?ticket=pt-1'),
        );
        expect(
          instantUrl,
          endsWith('${AppConstants.videoInstantStream('vid-3')}?ticket=pt-1'),
        );
        expect(
          previewUrl,
          endsWith('${AppConstants.videoPreviewStream('vid-3')}?ticket=pt-1'),
        );
        expect(
          postsTo(adapter, (p) => p.endsWith('/playback-ticket')),
          1,
          reason: 'one ticket authorizes stream, instant, and preview',
        );
      },
    );

    test('surfaces an ApiException when the ticket mint fails', () async {
      final adapter = _FakeAdapter(
        (_) => _json({'code': 'unauthorized', 'detail': 'nope'}, status: 401),
      );
      final api = apiWith(adapter);

      await expectLater(
        api.getVideoStreamUrl('vid-x'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('getWsTicket', () {
    test('POSTs the ws-ticket endpoint and caches the result', () async {
      var n = 0;
      final adapter = _FakeAdapter(
        (_) => _json({'ticket': 'wt-${++n}', 'expires_in': 300}),
      );
      final api = apiWith(adapter);

      expect(await api.getWsTicket(), 'wt-1');
      expect(
        await api.getWsTicket(),
        'wt-1',
        reason: 'cached until it nears expiry',
      );
      expect(postsTo(adapter, (p) => p == AppConstants.wsTicket), 1);
    });
  });

  group('push token registration', () {
    test('POSTs the device token, id and platform, returns true', () async {
      final adapter = _FakeAdapter(
        (_) => _json({'enabled': true, 'registered': true}),
      );
      final api = apiWith(adapter);

      final ok = await api.registerPushToken(token: 'tok', deviceId: 'dev-1');

      expect(ok, isTrue);
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, AppConstants.pushRegister);
      expect(req.data, {
        'device_token': 'tok',
        'device_id': 'dev-1',
        'platform': 'ios',
      });
    });

    test('returns false when push is disabled server-side', () async {
      final adapter = _FakeAdapter((_) => _json({'enabled': false}));
      final api = apiWith(adapter);

      expect(
        await api.registerPushToken(token: 'tok', deviceId: 'dev-1'),
        isFalse,
      );
    });

    test('unregister DELETEs the device id', () async {
      final adapter = _FakeAdapter((_) => _json({}));
      final api = apiWith(adapter);

      await api.unregisterPushToken('dev-1');

      final req = adapter.requests.single;
      expect(req.method, 'DELETE');
      expect(req.uri.path, AppConstants.pushRegister);
      expect(req.data, {'device_id': 'dev-1'});
    });
  });
}
