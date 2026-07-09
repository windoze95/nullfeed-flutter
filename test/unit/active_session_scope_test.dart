import 'package:flutter_test/flutter_test.dart';
import 'package:nullfeed/models/active_session_scope.dart';

void main() {
  test('normalizes equivalent server URLs into the same scope', () {
    final a = ActiveSessionScope(serverUrl: 'EXAMPLE.com:80/', userId: 'u1');
    final b = ActiveSessionScope(serverUrl: 'http://example.com', userId: 'u1');

    expect(a, b);
    expect(a.serverUrl, 'http://example.com');
    expect(a.cacheKeyPrefix, startsWith('v2::'));
  });

  test('server and profile are both part of identity', () {
    final base = ActiveSessionScope(
      serverUrl: 'https://example.com/',
      userId: 'u1',
    );

    expect(
      base,
      isNot(
        ActiveSessionScope(serverUrl: 'https://other.example', userId: 'u1'),
      ),
    );
    expect(
      base,
      isNot(ActiveSessionScope(serverUrl: 'https://example.com', userId: 'u2')),
    );
  });

  test(
    'normalizes host casing, default ports, paths, and trailing slashes',
    () {
      expect(
        ActiveSessionScope.normalizeServerUrl(
          ' HTTPS://Example.COM:443/nullfeed///?ignored=yes#fragment ',
        ),
        'https://example.com/nullfeed',
      );
    },
  );
}
