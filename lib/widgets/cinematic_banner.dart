import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Displays ultra-wide channel art without treating a narrow banner like a
/// full-bleed photo. The source stays at its natural aspect ratio in the sharp
/// foreground while a deliberately soft copy supplies edge-to-edge color.
class CinematicBanner extends StatelessWidget {
  const CinematicBanner({
    super.key,
    required this.imageUrl,
    this.showSharpArtwork = true,
    this.scrim = true,
    this.alignment = Alignment.center,
  });

  final String? imageUrl;
  final bool showSharpArtwork;
  final bool scrim;
  final Alignment alignment;

  /// YouTube's image CDN encodes the requested width in the URL. yt-dlp can
  /// return a perfectly valid banner URL pinned to a small rendition; promote
  /// it before loading instead of upscaling those pixels in the UI.
  static String? highResolutionUrl(String? value) {
    if (value == null || value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    final host = uri?.host.toLowerCase() ?? '';
    if (!host.contains('ggpht.com') &&
        !host.contains('googleusercontent.com')) {
      return value;
    }
    var result = value.replaceFirst(RegExp(r'=w\d+'), '=w2560');
    result = result.replaceFirst(RegExp(r'=s\d+'), '=s2560');
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final url = highResolutionUrl(imageUrl);
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final logicalWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final targetWidth = (logicalWidth * dpr).round().clamp(640, 2560);

        if (url == null) return const _BannerFallback();
        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Transform.scale(
                scale: 1.12,
                child: CachedNetworkImage(
                  imageUrl: url,
                  memCacheWidth: (targetWidth / 2).round(),
                  imageBuilder: (context, provider) => Image(
                    image: provider,
                    fit: BoxFit.cover,
                    alignment: alignment,
                    filterQuality: FilterQuality.medium,
                  ),
                  placeholder: (_, __) => const _BannerFallback(),
                  errorWidget: (_, __, ___) => const _BannerFallback(),
                ),
              ),
            ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
            if (showSharpArtwork)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: CachedNetworkImage(
                  imageUrl: url,
                  memCacheWidth: targetWidth,
                  imageBuilder: (context, provider) => Image(
                    image: provider,
                    fit: BoxFit.contain,
                    alignment: alignment,
                    filterQuality: FilterQuality.high,
                  ),
                  placeholder: (_, __) => const SizedBox.shrink(),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  fadeInDuration: const Duration(milliseconds: 180),
                  fadeOutDuration: const Duration(milliseconds: 100),
                ),
              ),
            if (scrim)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x0A07090D),
                      Color(0x2207090D),
                      Color(0xE807090D),
                    ],
                    stops: [0, 0.52, 1],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BannerFallback extends StatelessWidget {
  const _BannerFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            NullFeedTheme.elevatedSurfaceColor,
            NullFeedTheme.cardColor,
            NullFeedTheme.violetDeepColor,
          ],
        ),
      ),
    );
  }
}
