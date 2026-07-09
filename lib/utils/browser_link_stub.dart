/// Native (non-web) fallback: there's no host browser to detect or open into.
String? detectedBrowserName() => null;

String cookieExtensionUrl() =>
    'https://github.com/kairi003/Get-cookies.txt-LOCALLY';

void openInNewTab(String url) {}

/// Native clients cannot infer a NullFeed server from an app origin.
String? currentBrowserOrigin() => null;
