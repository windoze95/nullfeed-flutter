class AppConstants {
  AppConstants._();

  static const String appName = 'NullFeed';
  static const String defaultServerPort = '8484';

  // Hive box names
  static const String settingsBox = 'settings';
  static const String sessionBox = 'session';

  // Hive keys
  static const String serverUrlKey = 'server_url';
  static const String selectedUserIdKey = 'selected_user_id';
  static const String preferredQualityKey = 'preferred_quality';

  // API paths
  static const String apiBase = '/api';
  static const String authProfiles = '$apiBase/auth/profiles';
  static const String authSelect = '$apiBase/auth/select';
  static const String authCreate = '$apiBase/auth/create';
  static const String channels = '$apiBase/channels';
  static const String channelSubscribe = '$apiBase/channels/subscribe';
  static const String videos = '$apiBase/videos';
  static const String activeDownloads = '$apiBase/videos/downloads';
  static const String feedContinueWatching = '$apiBase/feed/continue-watching';
  static const String feedNewEpisodes = '$apiBase/feed/new-episodes';
  static const String feedRecentlyAdded = '$apiBase/feed/recently-added';
  static const String discover = '$apiBase/discover';
  static const String discoverRefresh = '$apiBase/discover/refresh';
  static const String health = '$apiBase/health';

  static String channelDetail(String id) => '$apiBase/channels/$id';
  static String channelVideos(String id) => '$apiBase/channels/$id/videos';
  static String channelUnsubscribe(String id) =>
      '$apiBase/channels/$id/unsubscribe';
  static String videoDetail(String id) => '$apiBase/videos/$id';
  static String videoStream(String id) => '$apiBase/videos/$id/stream';
  static String videoProgress(String id) => '$apiBase/videos/$id/progress';
  static String videoDownload(String id) => '$apiBase/videos/$id/download';
  static String videoCancel(String id) => '$apiBase/videos/$id/cancel';
  static String discoverDismiss(String id) => '$apiBase/discover/$id/dismiss';
  static String websocket(String userId) => '/ws/$userId';

  // Playback
  static const int progressSaveIntervalSeconds = 10;
  static const int skipForwardSeconds = 10;
  static const int skipBackwardSeconds = 10;

  // UI
  static const double cardAspectRatio = 16 / 9;
  static const double channelCardWidth = 280.0;
  static const double videoCardWidth = 320.0;
  static const double contentRowHeight = 200.0;
  static const double tvContentRowHeight = 300.0;
  static const double tvVideoCardWidth = 400.0;
  static const double tvChannelCardWidth = 360.0;
}
