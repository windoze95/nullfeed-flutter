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
