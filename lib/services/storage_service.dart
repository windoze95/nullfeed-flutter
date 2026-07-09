import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../config/constants.dart';
import '../models/active_session_scope.dart';
import '../providers/session_scope_provider.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(scope: ref.watch(activeSessionScopeProvider));
});

class StorageService {
  StorageService({ActiveSessionScope? scope}) : _scope = scope;

  /// Captured at construction so a delayed callback from an old session can
  /// never write preferences into whichever profile happens to be active now.
  final ActiveSessionScope? _scope;

  Box get _settings => Hive.box(AppConstants.settingsBox);
  Box get _session => Hive.box(AppConstants.sessionBox);

  // Server URL
  String? getServerUrl() => _settings.get(AppConstants.serverUrlKey) as String?;

  Future<void> setServerUrl(String url) async {
    await _settings.put(AppConstants.serverUrlKey, url);
  }

  // Selected User
  String? getSelectedUserId() =>
      _session.get(AppConstants.selectedUserIdKey) as String?;

  Future<void> setSelectedUserId(String? userId) async {
    if (userId == null) {
      await _session.delete(AppConstants.selectedUserIdKey);
    } else {
      await _session.put(AppConstants.selectedUserIdKey, userId);
    }
  }

  // Session Token
  String? getSessionToken() => _session.get('session_token') as String?;

  Future<void> setSessionToken(String? token) async {
    if (token == null) {
      await _session.delete('session_token');
    } else {
      await _session.put('session_token', token);
    }
  }

  // Device id (stable per install; identifies this device for push
  // registration). Lives in the settings box so it survives sign-out.
  String? getDeviceId() => _settings.get(AppConstants.deviceIdKey) as String?;

  Future<void> setDeviceId(String id) async {
    await _settings.put(AppConstants.deviceIdKey, id);
  }

  // Quality preference
  String getPreferredQuality() =>
      _settings.get(AppConstants.preferredQualityKey, defaultValue: '1080p')
          as String;

  Future<void> setPreferredQuality(String quality) async {
    await _settings.put(AppConstants.preferredQualityKey, quality);
  }

  // Clear session
  Future<void> clearSession() async {
    await _session.clear();
  }

  // Auto-offline channel preferences
  String? get _autoOfflineChannelsKey {
    final scope = _scope;
    if (scope == null) return null;
    return '${AppConstants.autoOfflineChannelsKey}::${scope.cacheKeyPrefix}';
  }

  Set<String> getAutoOfflineChannels() {
    final key = _autoOfflineChannelsKey;
    if (key == null) return const <String>{};
    final list = _settings.get(key, defaultValue: <String>[]);
    return Set<String>.from(list as List);
  }

  Future<void> setAutoOffline(String channelId, bool enabled) async {
    final key = _autoOfflineChannelsKey;
    if (key == null) return;
    final channels = getAutoOfflineChannels();
    if (enabled) {
      channels.add(channelId);
    } else {
      channels.remove(channelId);
    }
    await _settings.put(key, channels.toList());
  }

  bool isAutoOfflineEnabled(String channelId) {
    return getAutoOfflineChannels().contains(channelId);
  }

  // Clear all data
  Future<void> clearAll() async {
    await _settings.clear();
    await _session.clear();
  }
}
