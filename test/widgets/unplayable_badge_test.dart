import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nullfeed/config/theme.dart';
import 'package:nullfeed/models/video.dart';
import 'package:nullfeed/providers/offline_provider.dart';
import 'package:nullfeed/widgets/unplayable_badge.dart';
import 'package:nullfeed/widgets/video_card.dart';
import 'package:nullfeed/widgets/video_list_tile.dart';

Video makeVideo({
  VideoStatus status = VideoStatus.cataloged,
  UnplayableReason? unplayableReason,
  String? previewStatus,
}) {
  // youtubeVideoId left blank so the tiles render their offline placeholder
  // instead of reaching out for a network thumbnail during the test.
  return Video(
    id: 'v1',
    youtubeVideoId: '',
    channelId: 'c1',
    title: 'Exclusive Episode',
    status: status,
    previewStatus: previewStatus,
    unplayableReason: unplayableReason,
  );
}

/// Pumps [child] with the offline status for v1 overridden so no Hive setup is
/// needed.
Future<void> pumpTile(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [offlineStatusProvider('v1').overrideWithValue(null)],
      child: MaterialApp(
        theme: NullFeedTheme.darkTheme,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('badge shows the reason label and icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UnplayableBadge(reason: UnplayableReason.membersOnly),
        ),
      ),
    );

    expect(find.text('Members only'), findsOneWidget);
    expect(find.byIcon(Icons.card_membership), findsOneWidget);
  });

  testWidgets('video card banners an unplayable video', (tester) async {
    await pumpTile(
      tester,
      VideoCard(
        video: makeVideo(unplayableReason: UnplayableReason.ageRestricted),
      ),
    );

    expect(find.byType(UnplayableBadge), findsOneWidget);
    expect(find.text('Age-restricted'), findsOneWidget);
  });

  testWidgets('video card hides the banner once a playable file exists', (
    tester,
  ) async {
    // A stale label on a downloaded (or preview-ready) video is ignored — the
    // local file plays regardless of what YouTube refuses.
    await pumpTile(
      tester,
      VideoCard(
        video: makeVideo(
          status: VideoStatus.complete,
          unplayableReason: UnplayableReason.ageRestricted,
        ),
      ),
    );

    expect(find.byType(UnplayableBadge), findsNothing);
  });

  testWidgets('list tile banners an unplayable video compactly', (
    tester,
  ) async {
    await pumpTile(
      tester,
      VideoListTile(
        video: makeVideo(unplayableReason: UnplayableReason.membersOnly),
        onTap: () {},
      ),
    );

    final badge = tester.widget<UnplayableBadge>(find.byType(UnplayableBadge));
    expect(badge.compact, isTrue);
    expect(find.text('Members only'), findsOneWidget);
  });

  testWidgets('tile semantics mention the reason', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpTile(
      tester,
      VideoListTile(
        video: makeVideo(unplayableReason: UnplayableReason.premium),
        onTap: () {},
      ),
    );

    expect(
      find.bySemanticsLabel(RegExp('Exclusive Episode.*Premium')),
      findsOneWidget,
    );
    handle.dispose();
  });
}
