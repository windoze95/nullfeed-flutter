// Picks the right "Get cookies.txt LOCALLY" extension store link for the
// current browser (web only) and opens it.
//
// Browser extensions are installed in a desktop browser — which is exactly
// where the web app runs — so this is a web-only affordance. On native (iOS)
// the stub returns null / a no-op and the UI just shows the instructions.
export 'browser_link_stub.dart'
    if (dart.library.js_interop) 'browser_link_web.dart';
