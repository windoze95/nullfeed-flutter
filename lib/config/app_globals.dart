import 'package:flutter/material.dart';

/// App-wide [ScaffoldMessengerState] key.
///
/// Lets code that has no [BuildContext] — e.g. the API layer reacting to a
/// 401, or a Riverpod notifier — surface a SnackBar. Wired into [MaterialApp]
/// via `scaffoldMessengerKey`.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Shows [message] in a SnackBar via [scaffoldMessengerKey], replacing any
/// SnackBar already on screen. A no-op until the messenger is mounted.
void showGlobalSnackBar(String message) {
  scaffoldMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
