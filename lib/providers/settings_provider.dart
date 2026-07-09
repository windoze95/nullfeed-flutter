import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/active_session_scope.dart';
import '../services/storage_service.dart';
import 'auth_provider.dart';
import 'session_scope_provider.dart';

class SettingsState {
  final String? serverUrl;
  final String preferredQuality;
  final bool isServerReachable;

  const SettingsState({
    this.serverUrl,
    this.preferredQuality = '1080p',
    this.isServerReachable = false,
  });

  SettingsState copyWith({
    String? serverUrl,
    String? preferredQuality,
    bool? isServerReachable,
  }) {
    return SettingsState(
      serverUrl: serverUrl ?? this.serverUrl,
      preferredQuality: preferredQuality ?? this.preferredQuality,
      isServerReachable: isServerReachable ?? this.isServerReachable,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    final storage = ref.watch(storageServiceProvider);
    return SettingsState(
      serverUrl: storage.getServerUrl(),
      preferredQuality: storage.getPreferredQuality(),
    );
  }

  StorageService get _storage => ref.read(storageServiceProvider);

  Future<void> setServerUrl(String url) async {
    final activeScope = ref.read(activeSessionScopeProvider);
    final normalizedUrl = ActiveSessionScope.normalizeServerUrl(url);
    if (activeScope != null && activeScope.serverUrl != normalizedUrl) {
      // Tokens, profile ids, and every user-domain cache belong to the old
      // server. Sign out while that URL is still configured, then switch.
      await ref.read(authStateProvider.notifier).signOut();
    }
    await _storage.setServerUrl(url);
    state = state.copyWith(serverUrl: url);
  }

  Future<void> setPreferredQuality(String quality) async {
    await _storage.setPreferredQuality(quality);
    state = state.copyWith(preferredQuality: quality);
  }

  void setServerReachable(bool reachable) {
    state = state.copyWith(isServerReachable: reachable);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);

final qualityOptions = ['720p', '1080p', '4k', 'best'];
