import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../config/constants.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

class StorageService {
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
  Set<String> getAutoOfflineChannels() {
    final list = _settings.get(
      AppConstants.autoOfflineChannelsKey,
      defaultValue: <String>[],
    );
    return Set<String>.from(list as List);
  }

  void setAutoOffline(String channelId, bool enabled) {
    final channels = getAutoOfflineChannels();
    if (enabled) {
      channels.add(channelId);
    } else {
      channels.remove(channelId);
    }
    _settings.put(AppConstants.autoOfflineChannelsKey, channels.toList());
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
