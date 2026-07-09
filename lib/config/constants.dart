class AppConstants {
  AppConstants._();

  static const String appName = 'NullFeed';
  static const String defaultServerPort = '8484';
  static const String serverUrlHint = 'http://192.168.1.50:8484';

  // Hive box names
  static const String settingsBox = 'settings';
  static const String sessionBox = 'session';
  static const String offlineBox = 'offline_videos';

  /// Last-good catalog snapshot (channel list, home feed, per-channel video
  /// lists) persisted so the app stays browsable offline. Entries are scoped
  /// by the active profile — see [CatalogCacheService].
  static const String catalogCacheBox = 'catalog_cache';

  // Hive keys
  static const String serverUrlKey = 'server_url';
  static const String selectedUserIdKey = 'selected_user_id';
  static const String preferredQualityKey = 'preferred_quality';
  static const String autoOfflineChannelsKey = 'auto_offline_channels';

  /// Stable per-install identifier sent with the APNs token so the backend can
  /// upsert (and later remove) this device's push registration. Lives in the
  /// settings box so it survives sign-out — it identifies the device, not the
  /// session.
  static const String deviceIdKey = 'device_id';

  // API paths
  static const String apiBase = '/api';
  static const String authProfiles = '$apiBase/auth/profiles';
  static const String authSelect = '$apiBase/auth/select';
  static const String authCreate = '$apiBase/auth/create';
  static const String authMe = '$apiBase/auth/me';
  static const String authLogout = '$apiBase/auth/logout';

  /// Mints a short-lived ticket authorizing a single WebSocket connection, so
  /// the long-lived session token never appears in the `/ws` URL.
  static const String wsTicket = '$apiBase/auth/ws-ticket';
  static const String youtubeResolve = '$apiBase/youtube/resolve';
  static const String youtubeSuggestions = '$apiBase/youtube/suggestions';
  static const String settingsYoutubeCookies =
      '$apiBase/settings/youtube-cookies';
  static const String channels = '$apiBase/channels';
  static const String channelSubscribe = '$apiBase/channels/subscribe';
  static const String channelSubscribeBulk = '$apiBase/channels/subscribe-bulk';
  static const String channelPollAll = '$apiBase/channels/poll';
  static const String videos = '$apiBase/videos';
  static const String activeDownloads = '$apiBase/videos/downloads';
  static const String videosPrewarm = '$apiBase/videos/prewarm';
  static const String queue = '$apiBase/queue';
  static const String feedHome = '$apiBase/feed/home';
  static const String feedContinueWatching = '$apiBase/feed/continue-watching';
  static const String feedNewEpisodes = '$apiBase/feed/new-episodes';
  static const String feedRecentlyAdded = '$apiBase/feed/recently-added';
  static const String discover = '$apiBase/discover';
  static const String discoverRefresh = '$apiBase/discover/refresh';
  static const String health = '$apiBase/health';

  /// Registers (POST) or removes (DELETE) this device's APNs push token. Auth
  /// is the usual `X-User-Token` header, so the registration is scoped to the
  /// signed-in profile.
  static const String pushRegister = '$apiBase/push/register';

  static String authProfile(String id) => '$apiBase/auth/profiles/$id';
  static String channelDetail(String id) => '$apiBase/channels/$id';
  static String channelVideos(String id) => '$apiBase/channels/$id/videos';
  static String channelContentFilter(String id) =>
      '$apiBase/channels/$id/content-filter';
  static String channelPoll(String id) => '$apiBase/channels/$id/poll';
  static String channelRefreshImages(String id) =>
      '$apiBase/channels/$id/refresh-images';
  static String channelUnsubscribe(String id) =>
      '$apiBase/channels/$id/unsubscribe';
  static String videoDetail(String id) => '$apiBase/videos/$id';

  /// Mints a short-lived ticket authorizing playback of [id], used in place of
  /// the session token on both [videoStream] and [videoPreviewStream] URLs.
  static String videoPlaybackTicket(String id) =>
      '$apiBase/videos/$id/playback-ticket';
  static String videoStream(String id) => '$apiBase/videos/$id/stream';
  static String videoInstantStream(String id) =>
      '$apiBase/videos/$id/instant-stream';
  static String videoAdSegments(String id) => '$apiBase/videos/$id/ad-segments';
  static String videoProgress(String id) => '$apiBase/videos/$id/progress';
  static String videoDownload(String id) => '$apiBase/videos/$id/download';
  static String videoCancel(String id) => '$apiBase/videos/$id/cancel';
  static String videoCache(String id) => '$apiBase/videos/$id/cache';
  static String videoPreview(String id) => '$apiBase/videos/$id/preview';
  static String videoPreviewStream(String id) =>
      '$apiBase/videos/$id/preview-stream';
  static String videoQueue(String id) => '$apiBase/videos/$id/queue';
  static String discoverDismiss(String id) => '$apiBase/discover/$id/dismiss';
  static String websocket(String userId) => '/ws/$userId';

  // Playback
  static const int progressSaveIntervalSeconds = 10;
  static const int skipForwardSeconds = 10;
  static const int skipBackwardSeconds = 10;

  /// Hold-to-seek: holding a skip control scrubs continuously. The rate starts
  /// at [holdSeekInitialRate] video-seconds per held second and ramps linearly
  /// by [holdSeekRampPerSecond] each second, capped at [holdSeekMaxRate].
  static const double holdSeekInitialRate = 8;
  static const double holdSeekRampPerSecond = 12;
  static const double holdSeekMaxRate = 120;

  /// How often the hold-to-seek ticker advances the target position.
  static const int holdSeekTickMs = 100;

  /// How long to wait for a server-side preview/HQ render before giving up and
  /// showing a graceful "taking longer than expected" message instead of an
  /// indefinite spinner.
  static const int previewMaxWaitSeconds = 180;

  /// Cap on how long a single playback source may take to initialize. If a
  /// stream (especially the proxied instant-stream) stalls while loading, the
  /// player abandons it instead of spinning forever — for the cold-press path
  /// that means falling back to a preview; for others, a graceful error.
  static const int playbackInitTimeoutSeconds = 25;

  /// Max videos one /prewarm call asks the backend to pre-generate previews for.
  static const int prewarmBatchSize = 12;

  /// While playing a preview and waiting for the HQ download, how often to
  /// poll the video's status as a WebSocket fallback — the download_complete
  /// event fires exactly once, so a dropped connection would otherwise leave
  /// the player on the preview for the whole session.
  static const int hqPollIntervalSeconds = 20;

  // UI
  static const double cardAspectRatio = 16 / 9;
  static const double channelCardWidth = 280.0;
  static const double videoCardWidth = 320.0;
  // A 320pt 16:9 thumbnail is 180pt tall before title, channel, and progress
  // metadata. The previous 200pt rail clipped its own cards.
  static const double contentRowHeight = 258.0;
}
