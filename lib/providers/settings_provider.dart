import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/storage_service.dart';

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

class SettingsNotifier extends StateNotifier<SettingsState> {
  final StorageService _storage;

  SettingsNotifier(this._storage)
      : super(SettingsState(
          serverUrl: _storage.getServerUrl(),
          preferredQuality: _storage.getPreferredQuality(),
        ));

  Future<void> setServerUrl(String url) async {
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

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return SettingsNotifier(storage);
});

final qualityOptions = ['720p', '1080p', '4k', 'best'];
