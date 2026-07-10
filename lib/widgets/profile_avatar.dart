import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Rounded avatar that shows a network image when [avatarUrl] is set and
/// falls back to the first letter of [name] otherwise (or when loading the
/// image fails).
///
/// Relative URLs (e.g. `/data/thumbnails/avatars/<id>.jpg`) are resolved
/// against [serverBaseUrl]; absolute http(s) URLs are used as-is.
class ProfileAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final String? serverBaseUrl;
  final double size;

  /// Corner radius. Defaults to a circle ([size] / 2).
  final double? borderRadius;

  const ProfileAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.serverBaseUrl,
    this.size = 48,
    this.borderRadius,
  });

  /// Resolves [avatarUrl] against [serverBaseUrl] when it is a relative path.
  /// Returns null when there is no usable URL.
  static String? resolveUrl(String? avatarUrl, String? serverBaseUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty) return null;
    if (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://')) {
      return avatarUrl;
    }
    if (serverBaseUrl == null || serverBaseUrl.isEmpty) return null;
    var base = serverBaseUrl;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return avatarUrl.startsWith('/') ? '$base$avatarUrl' : '$base/$avatarUrl';
  }

  @override
  Widget build(BuildContext context) {
    final url = resolveUrl(avatarUrl, serverBaseUrl);

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: NullFeedTheme.primaryColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(borderRadius ?? size / 2),
      ),
      child: url == null
          ? _FallbackInitial(name: name, size: size)
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _FallbackInitial(name: name, size: size),
            ),
    );
  }
}

class _FallbackInitial extends StatelessWidget {
  final String name;
  final double size;

  const _FallbackInitial({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.bold,
          color: NullFeedTheme.accentColor,
        ),
      ),
    );
  }
}
