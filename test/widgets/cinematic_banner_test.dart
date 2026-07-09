import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nullfeed/widgets/cinematic_banner.dart';

void main() {
  test('promotes YouTube CDN banner URLs to a high-resolution rendition', () {
    expect(
      CinematicBanner.highResolutionUrl(
        'https://yt3.googleusercontent.com/example=w1060-fcrop64=1,0000ffff-k-c0xffffffff-no-nd-rj',
      ),
      'https://yt3.googleusercontent.com/example=w2560-fcrop64=1,0000ffff-k-c0xffffffff-no-nd-rj',
    );
    expect(
      CinematicBanner.highResolutionUrl(
        'https://yt3.ggpht.com/example=s320-c-k-c0x00ffffff-no-rj',
      ),
      'https://yt3.ggpht.com/example=s2560-c-k-c0x00ffffff-no-rj',
    );
  });

  test('does not rewrite non-YouTube image hosts', () {
    const url = 'https://images.example.com/banner=w320.jpg';
    expect(CinematicBanner.highResolutionUrl(url), url);
  });

  testWidgets('renders a polished fallback when a channel has no banner', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 600,
          height: 200,
          child: CinematicBanner(imageUrl: null),
        ),
      ),
    );

    expect(find.byType(CinematicBanner), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
