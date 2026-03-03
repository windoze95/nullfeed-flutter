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

  // Clear all data
  Future<void> clearAll() async {
    await _settings.clear();
    await _session.clear();
  }
}
