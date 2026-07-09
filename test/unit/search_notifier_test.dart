import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/models/channel.dart';
import 'package:nullfeed/models/video.dart';
import 'package:nullfeed/models/video_page.dart';
import 'package:nullfeed/providers/search_provider.dart';
import 'package:nullfeed/providers/session_scope_provider.dart';
import 'package:nullfeed/services/api_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService api;

  setUp(() {
    api = MockApiService();
  });

  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    container
        .read(activeSessionScopeProvider.notifier)
        .activate(serverUrl: 'http://test-server:8484', userId: 'u1');
    return container;
  }

  Video video(String id, {String title = 'A Video'}) =>
      Video(id: id, youtubeVideoId: 'yt-$id', channelId: 'c1', title: title);

  Channel channel(String id, String name) => Channel(
    id: id,
    youtubeChannelId: 'UC-$id',
    name: name,
    slug: name.toLowerCase(),
  );

  /// Lets [SearchNotifier.build]'s deferred recent-load and any awaited API
  /// calls finish, without tripping the 300ms search debounce.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  /// Long enough for the debounce timer started by [SearchNotifier.search].
  Future<void> debounce() =>
      Future<void>.delayed(const Duration(milliseconds: 350));

  group('initial load', () {
    test(
      'lists recent library videos (empty query, no channel call)',
      () async {
        when(() => api.searchVideos()).thenAnswer(
          (_) async => VideoPage(items: [video('v1'), video('v2')], total: 2),
        );
        final container = createContainer();

        container.read(searchProvider);
        await settle();

        final state = container.read(searchProvider);
        expect(state.query, '');
        expect(state.videos.map((v) => v.id), ['v1', 'v2']);
        expect(state.channels, isEmpty);
        expect(state.isLoading, isFalse);
        expect(state.hasResults, isTrue);
        // The empty (recent) query must not dump the whole channel list.
        verifyNever(() => api.searchChannels(any()));
      },
    );

    test('reports no results when the library is empty', () async {
      when(() => api.searchVideos()).thenAnswer((_) async => const VideoPage());
      final container = createContainer();

      container.read(searchProvider);
      await settle();

      final state = container.read(searchProvider);
      expect(state.hasResults, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('surfaces an ApiException message as the error', () async {
      when(() => api.searchVideos()).thenThrow(
        const ApiException(message: 'Server exploded', statusCode: 500),
      );
      final container = createContainer();

      container.read(searchProvider);
      await settle();

      final state = container.read(searchProvider);
      expect(state.error, 'Server exploded');
      expect(state.isLoading, isFalse);
      expect(state.hasResults, isFalse);
    });
  });

  group('querying', () {
    test('debounced query fetches channels + videos and total', () async {
      when(() => api.searchVideos()).thenAnswer((_) async => const VideoPage());
      when(() => api.searchVideos(q: 'cats')).thenAnswer(
        (_) async => VideoPage(items: [video('v1', title: 'Cats')], total: 1),
      );
      when(
        () => api.searchChannels('cats'),
      ).thenAnswer((_) async => [channel('c9', 'Cool Cats')]);
      final container = createContainer();
      container.read(searchProvider);
      await settle();

      container.read(searchProvider.notifier).search('cats');
      await debounce();

      final state = container.read(searchProvider);
      expect(state.query, 'cats');
      expect(state.videos.single.title, 'Cats');
      expect(state.channels.single.name, 'Cool Cats');
      expect(state.total, 1);
      expect(state.isLoading, isFalse);
    });
  });

  group('pagination', () {
    test(
      'loadMore appends the next page and clears the final cursor',
      () async {
        when(() => api.searchVideos()).thenAnswer(
          (_) async =>
              VideoPage(items: [video('v1')], total: 3, nextCursor: 'c1'),
        );
        when(() => api.searchVideos(cursor: 'c1')).thenAnswer(
          (_) async => VideoPage(items: [video('v2'), video('v3')], total: 3),
        );
        final container = createContainer();
        container.read(searchProvider);
        await settle();
        expect(container.read(searchProvider).hasMore, isTrue);

        await container.read(searchProvider.notifier).loadMore();

        final state = container.read(searchProvider);
        expect(state.videos.map((v) => v.id), ['v1', 'v2', 'v3']);
        expect(state.nextCursor, isNull);
        expect(state.hasMore, isFalse);
        expect(state.isLoadingMore, isFalse);
      },
    );

    test('loadMore is a no-op once on the last page', () async {
      when(
        () => api.searchVideos(),
      ).thenAnswer((_) async => VideoPage(items: [video('v1')], total: 1));
      final container = createContainer();
      container.read(searchProvider);
      await settle();

      await container.read(searchProvider.notifier).loadMore();

      // Only the initial recent load hit the API — no cursor page was fetched.
      verify(() => api.searchVideos()).called(1);
    });
  });
}
