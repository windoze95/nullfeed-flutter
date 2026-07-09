import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nullfeed/config/constants.dart';
import 'package:nullfeed/models/active_session_scope.dart';
import 'package:nullfeed/providers/offline_provider.dart';
import 'package:nullfeed/providers/session_scope_provider.dart';
import 'package:nullfeed/services/api_service.dart';
import 'package:nullfeed/services/offline_service.dart';
import 'package:nullfeed/services/storage_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late Directory hiveDir;
  late Directory documentsDir;
  late MockApiService api;
  late ActiveSessionScope profileA;
  late ActiveSessionScope profileB;
  late ActiveSessionScope serverB;
  final services = <OfflineService>[];

  OfflineService serviceFor(ActiveSessionScope scope) {
    final service = OfflineService(
      apiService: api,
      scope: scope,
      documentsDirectory: () async => documentsDir,
    );
    services.add(service);
    return service;
  }

  MapEntry<dynamic, Map<String, dynamic>> storedEntryFor(
    ActiveSessionScope scope,
  ) {
    final box = Hive.box(AppConstants.offlineBox);
    for (final key in box.keys) {
      final value = box.get(key);
      if (value is! Map) continue;
      final entry = value.cast<String, dynamic>();
      if (entry['owner_scope'] == scope.cacheKeyPrefix) {
        return MapEntry(key, entry);
      }
    }
    throw StateError('No stored entry for $scope');
  }

  setUp(() async {
    hiveDir = await setUpTestHive();
    documentsDir = Directory('${hiveDir.path}/documents');
    await documentsDir.create(recursive: true);
    api = MockApiService();
    profileA = ActiveSessionScope(
      serverUrl: 'HTTP://SERVER-A:80/',
      userId: 'profile-1',
    );
    profileB = ActiveSessionScope(
      serverUrl: 'http://server-a',
      userId: 'profile-2',
    );
    serverB = ActiveSessionScope(
      serverUrl: 'https://server-b.example',
      userId: 'profile-1',
    );
    when(
      () => api.getVideoStreamUrl(any()),
    ).thenThrow(const ApiException(message: 'offline'));
  });

  tearDown(() async {
    for (final service in services) {
      service.dispose();
    }
    services.clear();
    await tearDownTestHive(hiveDir);
  });

  test(
    'metadata and physical paths are isolated by profile and server',
    () async {
      final a = serviceFor(profileA);
      final b = serviceFor(profileB);
      final otherServer = serviceFor(serverB);

      await a.downloadToDevice('same-video', title: 'A copy');

      expect(a.getOfflineVideos(), hasLength(1));
      expect(b.getOfflineVideos(), isEmpty);
      expect(otherServer.getOfflineVideos(), isEmpty);

      await b.downloadToDevice('same-video', title: 'B copy');
      await otherServer.downloadToDevice('same-video', title: 'Server B copy');

      final aEntry = a.getOfflineVideos().single;
      final bEntry = b.getOfflineVideos().single;
      final serverBEntry = otherServer.getOfflineVideos().single;
      final aPath = aEntry['local_path'] as String;
      final bPath = bEntry['local_path'] as String;
      final serverBPath = serverBEntry['local_path'] as String;

      expect(aEntry['owner_scope'], profileA.cacheKeyPrefix);
      expect(bEntry['owner_scope'], profileB.cacheKeyPrefix);
      expect(serverBEntry['owner_scope'], serverB.cacheKeyPrefix);
      expect({aPath, bPath, serverBPath}, hasLength(3));

      // Promote only A's failed fixture to a complete physical save. Identical
      // video ids in the other scopes must not resolve A's file.
      final storedA = storedEntryFor(profileA);
      await File(aPath).writeAsBytes([1, 2, 3]);
      await Hive.box(AppConstants.offlineBox).put(storedA.key, {
        ...storedA.value,
        'status': 'complete',
        'file_size_bytes': 3,
        'watch_position': 42,
      });

      expect(a.isAvailableOffline('same-video'), isTrue);
      expect(a.getLocalPath('same-video'), aPath);
      expect(a.getWatchPosition('same-video'), 42);
      expect(a.getTotalOfflineSize(), 3);
      expect(b.isAvailableOffline('same-video'), isFalse);
      expect(otherServer.getLocalPath('same-video'), isNull);

      await b.removeOfflineVideo('same-video');
      expect(a.isAvailableOffline('same-video'), isTrue);
      expect(await File(aPath).exists(), isTrue);

      await a.removeOfflineVideo('same-video');
      expect(await File(aPath).exists(), isFalse);
      expect(otherServer.getOfflineVideos(), hasLength(1));
    },
  );

  test(
    'equivalent normalized server URLs share the same owner scope',
    () async {
      final first = serviceFor(profileA);
      final equivalent = serviceFor(
        ActiveSessionScope(serverUrl: 'server-a', userId: 'profile-1'),
      );

      await first.downloadToDevice('v1');

      expect(equivalent.scope, profileA);
      expect(equivalent.getOfflineVideos(), hasLength(1));
    },
  );

  test('legacy unowned metadata is ignored by every scope', () async {
    final legacyPath = '${documentsDir.path}/offline/legacy.mp4';
    await Hive.box(AppConstants.offlineBox).put('legacy-video', {
      'video_id': 'legacy-video',
      'status': 'complete',
      'local_path': legacyPath,
      'file_size_bytes': 99,
      'watch_position': 90,
    });

    for (final scope in [profileA, profileB, serverB]) {
      final service = serviceFor(scope);
      expect(service.loadOfflineVideos(), isEmpty);
      expect(service.isAvailableOffline('legacy-video'), isFalse);
      expect(service.getLocalPath('legacy-video'), isNull);
      expect(service.getWatchPosition('legacy-video'), 0);
      expect(service.getTotalOfflineSize(), 0);
    }
  });

  test(
    'auto-offline channel preferences are scoped and ignore legacy keys',
    () async {
      await Hive.box(
        AppConstants.settingsBox,
      ).put(AppConstants.autoOfflineChannelsKey, ['legacy-channel']);
      final a = StorageService(scope: profileA);
      final b = StorageService(scope: profileB);
      final otherServer = StorageService(scope: serverB);
      final signedOut = StorageService();

      await a.setAutoOffline('channel-1', true);

      expect(a.getAutoOfflineChannels(), {'channel-1'});
      expect(b.getAutoOfflineChannels(), isEmpty);
      expect(otherServer.getAutoOfflineChannels(), isEmpty);
      expect(signedOut.getAutoOfflineChannels(), isEmpty);
      expect(a.isAutoOfflineEnabled('legacy-channel'), isFalse);

      await b.setAutoOffline('channel-2', true);
      await signedOut.setAutoOffline('signed-out-channel', true);
      expect(a.getAutoOfflineChannels(), {'channel-1'});
      expect(b.getAutoOfflineChannels(), {'channel-2'});
      expect(
        Hive.box(
          AppConstants.settingsBox,
        ).get(AppConstants.autoOfflineChannelsKey),
        ['legacy-channel'],
      );
    },
  );

  test('providers clear on scope changes and reject stale progress', () async {
    await serviceFor(profileA).downloadToDevice('profile-a-video');
    final container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    container
        .read(activeSessionScopeProvider.notifier)
        .activate(serverUrl: profileA.serverUrl, userId: profileA.userId);
    expect(container.read(offlineVideosProvider), hasLength(1));
    container
        .read(offlineProgressProvider.notifier)
        .setProgress(profileA, 'profile-a-video', 0.4);
    expect(container.read(offlineProgressProvider), {'profile-a-video': 0.4});
    final oldService = container.read(offlineServiceProvider);

    container
        .read(activeSessionScopeProvider.notifier)
        .activate(serverUrl: profileB.serverUrl, userId: profileB.userId);

    expect(container.read(offlineVideosProvider), isEmpty);
    expect(container.read(offlineProgressProvider), isEmpty);
    expect(container.read(offlineServiceProvider), isNot(same(oldService)));
    expect(oldService.getOfflineVideos(), isEmpty, reason: 'disposed scope');

    container
        .read(offlineProgressProvider.notifier)
        .setProgress(profileA, 'profile-a-video', 0.9);
    expect(container.read(offlineProgressProvider), isEmpty);
    container
        .read(offlineProgressProvider.notifier)
        .setProgress(profileB, 'profile-b-video', 0.2);
    expect(container.read(offlineProgressProvider), {'profile-b-video': 0.2});

    container.read(activeSessionScopeProvider.notifier).clear();
    expect(container.read(offlineVideosProvider), isEmpty);
    expect(container.read(offlineProgressProvider), isEmpty);
  });

  test('disposing an old scope drops a late download result', () async {
    final ticket = Completer<String>();
    when(
      () => api.getVideoStreamUrl('slow-video'),
    ).thenAnswer((_) => ticket.future);
    final progress = <double?>[];
    final service = OfflineService(
      apiService: api,
      scope: profileA,
      documentsDirectory: () async => documentsDir,
      onProgress: (_, value) => progress.add(value),
    );
    services.add(service);

    final download = service.downloadToDevice('slow-video');
    while (progress.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(progress, [0.0]);

    service.dispose();
    ticket.complete('http://unused.test/video');
    await download;

    expect(
      Hive.box(AppConstants.offlineBox).values.where((value) {
        if (value is! Map) return false;
        return value['owner_scope'] == profileA.cacheKeyPrefix;
      }),
      isEmpty,
    );
    expect(progress, [0.0], reason: 'disposed scope emits no late callbacks');
  });
}
