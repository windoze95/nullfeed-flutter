import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/models/video.dart';
import 'package:nullfeed/models/video_page.dart';
import 'package:nullfeed/providers/queue_provider.dart';
import 'package:nullfeed/providers/session_scope_provider.dart';
import 'package:nullfeed/services/api_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService api;

  setUp(() {
    api = MockApiService();
  });

  Video video(String id, {String title = 'A Video'}) =>
      Video(id: id, youtubeVideoId: 'yt-$id', channelId: 'c1', title: title);

  /// Lets [QueueNotifier.build]'s deferred first load and any awaited API calls
  /// settle.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  void activate(ProviderContainer container) {
    container
        .read(activeSessionScopeProvider.notifier)
        .activate(serverUrl: 'http://test-server:8484', userId: 'u1');
  }

  /// Builds a container whose queue has finished its initial load with
  /// [initial] as the first page.
  Future<ProviderContainer> seededContainer(
    List<Video> initial, {
    String? nextCursor,
    int? total,
  }) async {
    when(() => api.getQueue()).thenAnswer(
      (_) async => VideoPage(
        items: initial,
        total: total ?? initial.length,
        nextCursor: nextCursor,
      ),
    );
    final container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    activate(container);
    container.read(queueProvider);
    await settle();
    return container;
  }

  group('initial load', () {
    test(
      'maps the getQueue page (items, total, next_cursor) into state',
      () async {
        when(() => api.getQueue()).thenAnswer(
          (_) async => VideoPage(
            items: [video('v1'), video('v2')],
            total: 5,
            nextCursor: 'cursor-1',
          ),
        );
        final container = ProviderContainer(
          overrides: [apiServiceProvider.overrideWithValue(api)],
        );
        addTearDown(container.dispose);
        activate(container);

        container.read(queueProvider);
        await settle();

        final state = container.read(queueProvider);
        expect(state.videos.map((v) => v.id), ['v1', 'v2']);
        expect(state.total, 5);
        expect(state.nextCursor, 'cursor-1');
        expect(state.hasMore, isTrue);
        expect(state.isLoading, isFalse);
        expect(state.error, isNull);
      },
    );

    test('reports an empty queue', () async {
      final container = await seededContainer(const []);

      final state = container.read(queueProvider);
      expect(state.isEmpty, isTrue);
      expect(state.hasMore, isFalse);
      expect(state.error, isNull);
    });

    test('surfaces an ApiException message as the error', () async {
      when(() => api.getQueue()).thenThrow(
        const ApiException(message: 'Server exploded', statusCode: 500),
      );
      final container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      activate(container);

      container.read(queueProvider);
      await settle();

      final state = container.read(queueProvider);
      expect(state.error, 'Server exploded');
      expect(state.isLoading, isFalse);
      expect(state.isEmpty, isTrue);
    });
  });

  group('optimistic add', () {
    test('appends to the end immediately, before the server responds', () async {
      final container = await seededContainer([video('v1')], total: 1);
      final notifier = container.read(queueProvider.notifier);

      // A pending server call so the optimistic state is observable on its own.
      final completer = Completer<void>();
      when(() => api.addToQueue('v2')).thenAnswer((_) => completer.future);

      final future = notifier.add(video('v2'));

      // Optimistic: in the queue and counted before the call resolves.
      final mid = container.read(queueProvider);
      expect(mid.videos.map((v) => v.id), ['v1', 'v2']);
      expect(mid.total, 2);

      completer.complete();
      await future;

      expect(container.read(queueProvider).isQueued('v2'), isTrue);
      verify(() => api.addToQueue('v2')).called(1);
    });

    test('reverts and rethrows when the server call fails', () async {
      final container = await seededContainer([video('v1')], total: 1);
      final notifier = container.read(queueProvider.notifier);

      when(
        () => api.addToQueue('v2'),
      ).thenThrow(const ApiException(message: 'nope'));

      await expectLater(
        notifier.add(video('v2')),
        throwsA(isA<ApiException>()),
      );

      final state = container.read(queueProvider);
      expect(state.isQueued('v2'), isFalse);
      expect(state.videos.map((v) => v.id), ['v1']);
      expect(state.total, 1);
    });

    test('is a no-op (no network call) for an already-queued video', () async {
      final container = await seededContainer([video('v1')], total: 1);
      final notifier = container.read(queueProvider.notifier);

      await notifier.add(video('v1'));

      expect(container.read(queueProvider).total, 1);
      verifyNever(() => api.addToQueue(any()));
    });
  });

  group('optimistic remove', () {
    test('removes immediately and persists on success', () async {
      final container = await seededContainer([
        video('v1'),
        video('v2'),
      ], total: 2);
      final notifier = container.read(queueProvider.notifier);
      when(() => api.removeFromQueue('v2')).thenAnswer((_) async {});

      await notifier.remove('v2');

      final state = container.read(queueProvider);
      expect(state.videos.map((v) => v.id), ['v1']);
      expect(state.total, 1);
      verify(() => api.removeFromQueue('v2')).called(1);
    });

    test('reverts and rethrows when the server call fails', () async {
      final container = await seededContainer([
        video('v1'),
        video('v2'),
      ], total: 2);
      final notifier = container.read(queueProvider.notifier);
      when(
        () => api.removeFromQueue('v1'),
      ).thenThrow(const ApiException(message: 'nope'));

      await expectLater(notifier.remove('v1'), throwsA(isA<ApiException>()));

      final state = container.read(queueProvider);
      expect(state.videos.map((v) => v.id), ['v1', 'v2']);
      expect(state.total, 2);
    });
  });

  group('toggle', () {
    test('adds when absent, removes when present', () async {
      final container = await seededContainer([video('v1')], total: 1);
      final notifier = container.read(queueProvider.notifier);
      when(() => api.addToQueue('v2')).thenAnswer((_) async {});
      when(() => api.removeFromQueue('v2')).thenAnswer((_) async {});

      await notifier.toggle(video('v2'));
      expect(container.read(queueProvider).isQueued('v2'), isTrue);

      await notifier.toggle(video('v2'));
      expect(container.read(queueProvider).isQueued('v2'), isFalse);

      verify(() => api.addToQueue('v2')).called(1);
      verify(() => api.removeFromQueue('v2')).called(1);
    });
  });

  group('pagination', () {
    test(
      'loadMore appends the next page and clears the final cursor',
      () async {
        final container = await seededContainer(
          [video('v1')],
          nextCursor: 'c1',
          total: 3,
        );
        when(() => api.getQueue(cursor: 'c1')).thenAnswer(
          (_) async => VideoPage(items: [video('v2'), video('v3')], total: 3),
        );
        expect(container.read(queueProvider).hasMore, isTrue);

        await container.read(queueProvider.notifier).loadMore();

        final state = container.read(queueProvider);
        expect(state.videos.map((v) => v.id), ['v1', 'v2', 'v3']);
        expect(state.nextCursor, isNull);
        expect(state.hasMore, isFalse);
        expect(state.isLoadingMore, isFalse);
      },
    );

    test('loadMore is a no-op once on the last page', () async {
      final container = await seededContainer([video('v1')], total: 1);

      await container.read(queueProvider.notifier).loadMore();

      // Only the initial load hit the API — no cursor page was fetched.
      verify(() => api.getQueue()).called(1);
      verifyNever(() => api.getQueue(cursor: any(named: 'cursor')));
    });
  });

  group('nextAfter (auto-advance target)', () {
    test('returns the item after the finished one', () async {
      final container = await seededContainer([
        video('v1'),
        video('v2'),
        video('v3'),
      ], total: 3);
      final notifier = container.read(queueProvider.notifier);

      expect(notifier.nextAfter('v1'), 'v2');
      expect(notifier.nextAfter('v2'), 'v3');
    });

    test('returns null after the last queued item', () async {
      final container = await seededContainer([
        video('v1'),
        video('v2'),
      ], total: 2);

      expect(container.read(queueProvider.notifier).nextAfter('v2'), isNull);
    });

    test('does not enter Watch Later from an unrelated video', () async {
      final container = await seededContainer([
        video('v1'),
        video('v2'),
      ], total: 2);

      expect(
        container.read(queueProvider.notifier).nextAfter('outsider'),
        isNull,
      );
    });

    test('returns null when the queue is empty', () async {
      final container = await seededContainer(const []);

      expect(container.read(queueProvider.notifier).nextAfter('v1'), isNull);
    });
  });
}
