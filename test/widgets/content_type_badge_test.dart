import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nullfeed/config/theme.dart';
import 'package:nullfeed/models/video.dart';
import 'package:nullfeed/providers/offline_provider.dart';
import 'package:nullfeed/widgets/content_type_badge.dart';
import 'package:nullfeed/widgets/unplayable_badge.dart';
import 'package:nullfeed/widgets/video_card.dart';
import 'package:nullfeed/widgets/video_list_tile.dart';

Video makeVideo({
  VideoStatus status = VideoStatus.cataloged,
  ContentType? contentType,
  UnplayableReason? unplayableReason,
  String? previewStatus,
}) {
  // youtubeVideoId left blank so the tiles render their placeholder instead of
  // reaching out for a network thumbnail during the test.
  return Video(
    id: 'v1',
    youtubeVideoId: '',
    channelId: 'c1',
    title: 'A Clip',
    status: status,
    previewStatus: previewStatus,
    contentType: contentType,
    unplayableReason: unplayableReason,
  );
}

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
  testWidgets('badge shows the type label and icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ContentTypeBadge(type: ContentType.live)),
      ),
    );

    expect(find.text('Live'), findsOneWidget);
    expect(find.byIcon(Icons.sensors), findsOneWidget);
  });

  testWidgets('video card badges a Short', (tester) async {
    await pumpTile(
      tester,
      VideoCard(video: makeVideo(contentType: ContentType.short)),
    );

    expect(find.byType(ContentTypeBadge), findsOneWidget);
    expect(find.text('Short'), findsOneWidget);
  });

  testWidgets('regular videos are not badged', (tester) async {
    await pumpTile(
      tester,
      VideoCard(video: makeVideo(contentType: ContentType.regular)),
    );

    expect(find.byType(ContentTypeBadge), findsNothing);
  });

  testWidgets('the unplayable banner wins over the content-type badge', (
    tester,
  ) async {
    // A not-yet-playable members-only Short: the unplayable banner shows and the
    // content-type pill is suppressed (they share the corner).
    await pumpTile(
      tester,
      VideoCard(
        video: makeVideo(
          contentType: ContentType.short,
          unplayableReason: UnplayableReason.membersOnly,
        ),
      ),
    );

    expect(find.byType(UnplayableBadge), findsOneWidget);
    expect(find.byType(ContentTypeBadge), findsNothing);
  });

  testWidgets('list tile badges compactly', (tester) async {
    await pumpTile(
      tester,
      VideoListTile(
        video: makeVideo(contentType: ContentType.premiere),
        onTap: () {},
      ),
    );

    final badge = tester.widget<ContentTypeBadge>(
      find.byType(ContentTypeBadge),
    );
    expect(badge.compact, isTrue);
    expect(find.text('Premiere'), findsOneWidget);
  });
}
