import 'package:flutter/foundation.dart';

/// Identifies the authenticated data boundary for one NullFeed session.
///
/// Both pieces are required: profile ids are only meaningful within a server,
/// so keying state or cached data by profile id alone can surface another
/// server's data when ids collide.
@immutable
class ActiveSessionScope {
  final String serverUrl;
  final String userId;

  ActiveSessionScope({required String serverUrl, required this.userId})
    : serverUrl = normalizeServerUrl(serverUrl);

  /// Returns a scope only when both inputs identify a usable session.
  static ActiveSessionScope? tryCreate({
    required String? serverUrl,
    required String? userId,
  }) {
    final trimmedUserId = userId?.trim() ?? '';
    final trimmedServerUrl = serverUrl?.trim() ?? '';
    if (trimmedUserId.isEmpty || trimmedServerUrl.isEmpty) return null;
    return ActiveSessionScope(
      serverUrl: trimmedServerUrl,
      userId: trimmedUserId,
    );
  }

  /// Canonical form used for equality and persistent cache keys.
  ///
  /// Missing schemes default to HTTP, host/scheme casing is normalized,
  /// default ports and trailing slashes are removed, and query/fragment data is
  /// discarded because it is not part of a NullFeed server base URL.
  static String normalizeServerUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) return value;
    if (!value.contains('://')) value = 'http://$value';

    final parsed = Uri.tryParse(value);
    if (parsed == null || parsed.host.isEmpty) {
      while (value.endsWith('/')) {
        value = value.substring(0, value.length - 1);
      }
      return value;
    }

    final scheme = parsed.scheme.toLowerCase();
    final isDefaultPort =
        (scheme == 'http' && parsed.hasPort && parsed.port == 80) ||
        (scheme == 'https' && parsed.hasPort && parsed.port == 443);
    var path = parsed.path;
    while (path.endsWith('/') && path.isNotEmpty) {
      path = path.substring(0, path.length - 1);
    }

    return Uri(
      scheme: scheme,
      userInfo: parsed.userInfo,
      host: parsed.host.toLowerCase(),
      port: parsed.hasPort && !isDefaultPort ? parsed.port : null,
      path: path,
    ).toString();
  }

  /// Versioned prefix ensures legacy profile-only entries are cache misses.
  String get cacheKeyPrefix =>
      'v2::${Uri.encodeComponent(serverUrl)}::${Uri.encodeComponent(userId)}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveSessionScope &&
          other.serverUrl == serverUrl &&
          other.userId == userId;

  @override
  int get hashCode => Object.hash(serverUrl, userId);

  @override
  String toString() => 'ActiveSessionScope($serverUrl, $userId)';
}
