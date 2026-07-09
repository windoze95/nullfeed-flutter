import 'package:web/web.dart' as web;

/// The host browser's friendly name, or null if it can't be identified.
String? detectedBrowserName() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  // Order matters: Edge's UA contains "chrome", and Chrome's contains "safari".
  if (ua.contains('firefox')) return 'Firefox';
  if (ua.contains('edg/')) return 'Edge';
  if (ua.contains('chrome') || ua.contains('chromium')) return 'Chrome';
  if (ua.contains('safari')) return 'Safari';
  return null;
}

/// Store link for "Get cookies.txt LOCALLY" matching the host browser.
String cookieExtensionUrl() {
  switch (detectedBrowserName()) {
    case 'Firefox':
      return 'https://addons.mozilla.org/en-US/firefox/addon/get-cookies-txt-locally/';
    case 'Safari':
      // Not available for Safari — the repo points to the supported browsers.
      return 'https://github.com/kairi003/Get-cookies.txt-LOCALLY';
    default:
      // Chrome, Edge (installs from the Chrome store), and other Chromium.
      return 'https://chromewebstore.google.com/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc';
  }
}

void openInNewTab(String url) {
  web.window.open(url, '_blank');
}

/// The Flutter web bundle is served by the NullFeed backend itself, so its
/// origin is the correct server address on first launch.
String? currentBrowserOrigin() {
  final origin = web.window.location.origin;
  return origin.isEmpty ? null : origin;
}
