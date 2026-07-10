// Throwaway store-screenshot driver. Runs the real app against the local
// demo server and asks a host-side helper (capture_server.py) to grab the
// simulator framebuffer between navigation steps. Not for CI.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nullfeed/app.dart';
import 'package:nullfeed/config/constants.dart';

Future<void> _capture(String name) async {
  await Future<void>.delayed(const Duration(milliseconds: 900));
  final client = HttpClient();
  try {
    final req =
        await client.getUrl(Uri.parse('http://localhost:8765/capture/$name'));
    final resp = await req.close();
    await resp.drain<void>();
  } finally {
    client.close();
  }
}

Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<bool> _waitForAny(WidgetTester tester, List<String> texts,
    {Duration timeout = const Duration(seconds: 25)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    for (final t in texts) {
      if (find.text(t).evaluate().isNotEmpty) return true;
    }
  }
  return false;
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text).first;
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(f, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('store screenshots', (tester) async {
    await Hive.initFlutter();
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.sessionBox);
    await Hive.openBox(AppConstants.offlineBox);
    await Hive.openBox(AppConstants.catalogCacheBox);
    await Hive.box(AppConstants.settingsBox)
        .put(AppConstants.serverUrlKey, 'http://localhost:8484');

    runApp(const ProviderScope(child: NullFeedApp()));
    await _pumpFor(tester, const Duration(seconds: 2));

    // 1. Profile picker
    expect(await _waitForAny(tester, ['Demo User']), isTrue,
        reason: 'profile picker should list Demo User');
    await _pumpFor(tester, const Duration(seconds: 2));
    await _capture('profile_picker');

    // 2. Home
    await _tapText(tester, 'Demo User');
    expect(
        await _waitForAny(
            tester, ['Continue watching', 'New from your channels']),
        isTrue,
        reason: 'home feed should load');
    await _pumpFor(tester, const Duration(seconds: 6)); // thumbnails
    await _capture('home');

    // 3. Library (Channels tab)
    await _tapText(tester, 'Channels');
    expect(await _waitForAny(tester, ['Blender Studio']), isTrue,
        reason: 'library should list channels');
    await _pumpFor(tester, const Duration(seconds: 4));
    await _capture('library');

    // 4. Discover (Explore tab)
    await _tapText(tester, 'Explore');
    await _waitForAny(
        tester, ['Khan Academy', 'CrashCourse', 'TED', 'Blender Foundation'],
        timeout: const Duration(seconds: 20));
    await _pumpFor(tester, const Duration(seconds: 5));
    await _capture('discover');

    // 5. Channel detail
    await _tapText(tester, 'Channels');
    await _pumpFor(tester, const Duration(seconds: 2));
    await _tapText(tester, 'Blender Studio');
    expect(await _waitForAny(tester, ['Tears of Steel', 'Big Buck Bunny']),
        isTrue,
        reason: 'channel detail should list videos');
    await _pumpFor(tester, const Duration(seconds: 4));
    await _capture('channel_detail');

    // 6. Player
    await _tapText(tester, 'Tears of Steel');
    await _pumpFor(tester, const Duration(seconds: 3));
    // A picker/action sheet may sit between the tile and the player.
    if (find.text('Play now').evaluate().isNotEmpty) {
      await _tapText(tester, 'Play now');
    } else if (find.text('Resume').evaluate().isNotEmpty) {
      await _tapText(tester, 'Resume');
    }
    await _pumpFor(tester, const Duration(seconds: 12)); // playback + controls hide
    await _capture('player_clean');
    final view = tester.view;
    await tester.tapAt(Offset(view.physicalSize.width / view.devicePixelRatio / 2,
        view.physicalSize.height / view.devicePixelRatio / 2));
    await _pumpFor(tester, const Duration(milliseconds: 900));
    await _capture('player');
    await _pumpFor(tester, const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
