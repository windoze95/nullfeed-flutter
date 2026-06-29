import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:nullfeed/config/theme.dart';
import 'package:nullfeed/models/channel.dart';
import 'package:nullfeed/models/video.dart';
import 'package:nullfeed/providers/offline_provider.dart';
import 'package:nullfeed/widgets/channel_card.dart';
import 'package:nullfeed/widgets/progress_bar.dart';
import 'package:nullfeed/widgets/video_card.dart';
import 'package:nullfeed/widgets/video_list_tile.dart';

Video makeVideo({
  String id = 'v1',
  String title = 'Big Buck Bunny',
  VideoStatus status = VideoStatus.complete,
  bool isWatched = false,
  DateTime? uploadedAt,
}) {
  // youtubeVideoId left blank so the cards render their offline placeholder
  // instead of reaching out for a network thumbnail during the test.
  return Video(
    id: id,
    youtubeVideoId: '',
    channelId: 'c1',
    title: title,
    status: status,
    isWatched: isWatched,
    uploadedAt: uploadedAt,
  );
}

Channel makeChannel({String id = 'c1', String name = 'Blender'}) {
  return Channel(id: id, youtubeChannelId: 'UC1', name: name, slug: 'blender');
}

/// Pumps [child] with the offline status for [videoId] overridden so no Hive
/// setup is needed.
Future<void> pumpWidget(
  WidgetTester tester,
  Widget child, {
  String? offlineStatus,
  String videoId = 'v1',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        offlineStatusProvider(videoId).overrideWithValue(offlineStatus),
      ],
      child: MaterialApp(
        theme: NullFeedTheme.darkTheme,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'seek bar exposes a slider with label, value and adjust actions',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NullFeedProgressBar(
                progress: 0.5,
                semanticLabel: 'Video position',
                onSeek: (_) {},
              ),
            ),
          ),
        ),
      );

      final finder = find.bySemanticsLabel('Video position');
      expect(finder, findsOneWidget);

      final node = tester.getSemantics(finder);
      final data = node.getSemanticsData();
      // Operable as a slider: role, value, and adjust actions (which are only
      // wired when onIncrease/onDecrease are provided).
      expect(data.flagsCollection.isSlider, isTrue);
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);
      expect(node.value, '50%');
      // +/-5% steps are reflected in the announced increase/decrease values.
      expect(node.increasedValue, '55%');
      expect(node.decreasedValue, '45%');

      handle.dispose();
    },
  );

  testWidgets('video card merges into one labelled play button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await pumpWidget(
      tester,
      VideoCard(
        video: makeVideo(title: 'Big Buck Bunny'),
        channel: makeChannel(name: 'Blender'),
      ),
    );

    // Title + channel collapse into a single play node...
    expect(find.bySemanticsLabel('Big Buck Bunny, Blender'), findsOneWidget);
    // ...with the channel link as its own separate node.
    expect(find.bySemanticsLabel('Go to Blender'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('video card play label includes the downloaded state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await pumpWidget(
      tester,
      VideoCard(
        video: makeVideo(title: 'Big Buck Bunny'),
        channel: makeChannel(name: 'Blender'),
      ),
      offlineStatus: 'complete',
    );

    expect(
      find.bySemanticsLabel('Big Buck Bunny, Blender, downloaded'),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('channel card exposes a label and a separate actions button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await pumpWidget(
      tester,
      ChannelCard(
        channel: makeChannel(name: 'Blender'),
        onTap: () {},
        onMenu: () {},
      ),
    );

    expect(find.bySemanticsLabel('Blender channel'), findsOneWidget);
    // The ⋯ button keeps its own operable node (tooltip-based label).
    expect(find.byTooltip('Channel actions'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('list tile merges title, date and offline state', (tester) async {
    final handle = tester.ensureSemantics();
    final uploaded = DateTime.utc(2026, 1, 2);

    await pumpWidget(
      tester,
      VideoListTile(
        video: makeVideo(
          title: 'Big Buck Bunny',
          status: VideoStatus.complete,
          uploadedAt: uploaded,
        ),
        onTap: () {},
      ),
      offlineStatus: 'complete',
    );

    final date = DateFormat.yMMMd().format(uploaded);
    expect(
      find.bySemanticsLabel('Big Buck Bunny, $date, saved offline'),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('list tile shows no caching status for an un-cached episode', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await pumpWidget(
      tester,
      VideoListTile(
        video: makeVideo(title: 'Clip', status: VideoStatus.cataloged),
        onTap: () {},
      ),
    );

    // Caching is invisible: no download/cancel/progress affordance, and the
    // semantic label carries no download state.
    expect(find.bySemanticsLabel('Clip'), findsOneWidget);
    expect(find.byTooltip('Cancel download'), findsNothing);
    expect(find.byTooltip('Download to server'), findsNothing);

    handle.dispose();
  });
}
