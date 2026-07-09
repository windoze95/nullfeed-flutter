import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/active_session_scope.dart';

/// Single source of truth for the authenticated server/profile data boundary.
///
/// User-domain providers watch this value. Activating another profile/server or
/// clearing the session therefore rebuilds them synchronously, before stale
/// state can be rendered under the new identity.
class ActiveSessionScopeNotifier extends Notifier<ActiveSessionScope?> {
  @override
  ActiveSessionScope? build() => null;

  void activate({required String serverUrl, required String userId}) {
    state = ActiveSessionScope.tryCreate(serverUrl: serverUrl, userId: userId);
  }

  void clear() {
    state = null;
  }
}

final activeSessionScopeProvider =
    NotifierProvider<ActiveSessionScopeNotifier, ActiveSessionScope?>(
      ActiveSessionScopeNotifier.new,
    );
