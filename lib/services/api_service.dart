import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/constants.dart';
import '../models/user.dart';
import '../models/channel.dart';
import '../models/video.dart';
import '../models/feed.dart';
import '../models/recommendation.dart';
import '../models/youtube_import.dart';
import 'storage_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return ApiService(storage: storage);
});

/// User-presentable error thrown by every [ApiService] method.
///
/// Wraps [DioException] so providers and screens can show [message] instead
/// of raw exception dumps.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool isConnectionError;

  const ApiException({
    required this.message,
    this.statusCode,
    this.isConnectionError = false,
  });

  factory ApiException.fromDioException(DioException error) {
    final statusCode = error.response?.statusCode;
    final isConnectionError = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError => true,
      _ => false,
    };

    String? detail;
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      detail = data['detail'] as String;
    }

    final message =
        detail ??
        (isConnectionError
            ? 'Could not reach the server. Check your connection.'
            : statusCode != null
            ? 'Request failed ($statusCode)'
            : 'Something went wrong. Please try again.');

    return ApiException(
      message: message,
      statusCode: statusCode,
      isConnectionError: isConnectionError,
    );
  }

  @override
  String toString() => message;
}

class ApiService {
  final StorageService storage;
  late final Dio _dio;

  ApiService({required this.storage}) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Respect per-request token overrides (e.g. the picker's in-memory
          // management token) — only fall back to the stored session.
          if (!options.headers.containsKey('X-User-Token')) {
            final token = storage.getSessionToken();
            if (token != null) {
              options.headers['X-User-Token'] = token;
            }
          }
          handler.next(options);
        },
        onError: (error, handler) {
          handler.next(error);
        },
      ),
    );
  }

  String get _baseUrl => storage.getServerUrl() ?? 'http://localhost:8484';

  /// Generous timeout for endpoints that shell out to yt-dlp server-side.
  static const _slowReceiveTimeout = Duration(seconds: 90);

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // Auth
  Future<List<User>> getProfiles() => _guard(() async {
    final response = await _dio.post('$_baseUrl${AppConstants.authProfiles}');
    return (response.data as List)
        .map((json) => User.fromJson(json as Map<String, dynamic>))
        .toList();
  });

  Future<({User user, String token})> selectProfile(
    String userId, {
    String? pin,
  }) => _guard(() async {
    final response = await _dio.post(
      '$_baseUrl${AppConstants.authSelect}',
      data: {'user_id': userId, if (pin != null) 'pin': pin},
    );
    final data = response.data as Map<String, dynamic>;
    final user = User.fromJson(data['user'] as Map<String, dynamic>);
    final token = data['token'] as String;
    return (user: user, token: token);
  });

  Future<User> createProfile({
    String? displayName,
    String? avatarUrl,
    String? pin,
    String? youtubeHandle,
  }) => _guard(() async {
    final response = await _dio.post(
      '$_baseUrl${AppConstants.authCreate}',
      data: {
        if (displayName != null) 'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (pin != null) 'pin': pin,
        if (youtubeHandle != null) 'youtube_handle': youtubeHandle,
      },
      // Creating from a handle resolves the channel server-side (yt-dlp).
      options: youtubeHandle != null
          ? Options(receiveTimeout: _slowReceiveTimeout)
          : null,
    );
    return User.fromJson(response.data as Map<String, dynamic>);
  });

  Future<User> getMe() => _guard(() async {
    final response = await _dio.get('$_baseUrl${AppConstants.authMe}');
    return User.fromJson(response.data as Map<String, dynamic>);
  });

  Future<void> logout({String? tokenOverride}) => _guard(() async {
    await _dio.post(
      '$_baseUrl${AppConstants.authLogout}',
      options: _withToken(tokenOverride),
    );
  });

  Future<User> updateProfile(
    String userId, {
    String? displayName,
    String? avatarUrl,
    String? pin,
    bool removePin = false,
    String? tokenOverride,
  }) => _guard(() async {
    final response = await _dio.patch(
      '$_baseUrl${AppConstants.authProfile(userId)}',
      data: {
        if (displayName != null) 'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (pin != null) 'pin': pin,
        if (removePin) 'remove_pin': true,
      },
      options: _withToken(tokenOverride),
    );
    return User.fromJson(response.data as Map<String, dynamic>);
  });

  Future<void> deleteProfile(String userId, {String? tokenOverride}) =>
      _guard(() async {
        await _dio.delete(
          '$_baseUrl${AppConstants.authProfile(userId)}',
          options: _withToken(tokenOverride),
        );
      });

  /// Per-request auth override used by pre-login profile management so the
  /// temporary token never touches persistent storage.
  Options? _withToken(String? tokenOverride) => tokenOverride == null
      ? null
      : Options(headers: {'X-User-Token': tokenOverride});

  // YouTube import
  Future<YoutubeProfile> resolveYoutubeHandle(String handle) =>
      _guard(() async {
        final response = await _dio.post(
          '$_baseUrl${AppConstants.youtubeResolve}',
          data: {'handle': handle},
          options: Options(receiveTimeout: _slowReceiveTimeout),
        );
        return YoutubeProfile.fromJson(response.data as Map<String, dynamic>);
      });

  Future<List<ChannelSuggestion>> getYoutubeSuggestions(String handle) =>
      _guard(() async {
        final response = await _dio.post(
          '$_baseUrl${AppConstants.youtubeSuggestions}',
          data: {'handle': handle},
          options: Options(receiveTimeout: _slowReceiveTimeout),
        );
        final data = response.data as Map<String, dynamic>;
        return (data['suggestions'] as List? ?? [])
            .map(
              (json) =>
                  ChannelSuggestion.fromJson(json as Map<String, dynamic>),
            )
            .toList();
      });

  // Channels
  Future<List<Channel>> getChannels() => _guard(() async {
    final response = await _dio.get('$_baseUrl${AppConstants.channels}');
    return (response.data as List)
        .map((json) => Channel.fromJson(json as Map<String, dynamic>))
        .toList();
  });

  Future<Channel> getChannel(String id) => _guard(() async {
    final response = await _dio.get(
      '$_baseUrl${AppConstants.channelDetail(id)}',
    );
    return Channel.fromJson(response.data as Map<String, dynamic>);
  });

  Future<List<Video>> getChannelVideos(String channelId) => _guard(() async {
    final response = await _dio.get(
      '$_baseUrl${AppConstants.channelVideos(channelId)}',
    );
    final data = response.data;
    // Backend returns paginated response {items: [...], total, page, per_page}
    final List items = data is Map
        ? (data['items'] as List? ?? [])
        : (data as List);
    return items
        .map((json) => Video.fromJson(json as Map<String, dynamic>))
        .toList();
  });

  Future<void> subscribeToChannel(
    String youtubeUrl, {
    String trackingMode = 'FUTURE_ONLY',
  }) => _guard(() async {
    await _dio.post(
      '$_baseUrl${AppConstants.channelSubscribe}',
      data: {'url': youtubeUrl, 'tracking_mode': trackingMode},
    );
  });

  Future<List<BulkSubscribeResult>> subscribeBulk(
    List<ChannelSuggestion> items,
  ) => _guard(() async {
    final response = await _dio.post(
      '$_baseUrl${AppConstants.channelSubscribeBulk}',
      data: {
        'items': [
          for (final item in items)
            {'youtube_channel_id': item.youtubeChannelId, 'name': item.name},
        ],
      },
      options: Options(receiveTimeout: _slowReceiveTimeout),
    );
    final data = response.data as Map<String, dynamic>;
    return (data['results'] as List? ?? [])
        .map(
          (json) => BulkSubscribeResult.fromJson(json as Map<String, dynamic>),
        )
        .toList();
  });

  /// Polls one channel for new uploads synchronously (server runs a single
  /// yt-dlp call). Used by pull-to-refresh on the channel screen.
  Future<void> pollChannel(String channelId) => _guard(() async {
    await _dio.post(
      '$_baseUrl${AppConstants.channelPoll(channelId)}',
      options: Options(receiveTimeout: _slowReceiveTimeout),
    );
  });

  /// Kicks off a background poll of all channels (fire-and-forget on the
  /// server). Used by pull-to-refresh on home/library.
  Future<void> pollAllChannels() => _guard(() async {
    await _dio.post('$_baseUrl${AppConstants.channelPollAll}');
  });

  Future<Channel> refreshChannelImages(String channelId) => _guard(() async {
    final response = await _dio.post(
      '$_baseUrl${AppConstants.channelRefreshImages(channelId)}',
    );
    return Channel.fromJson(response.data as Map<String, dynamic>);
  });

  Future<void> unsubscribeFromChannel(String channelId) => _guard(() async {
    await _dio.delete('$_baseUrl${AppConstants.channelUnsubscribe(channelId)}');
  });

  // Downloads
  Future<List<Video>> getActiveDownloads() => _guard(() async {
    final response = await _dio.get('$_baseUrl${AppConstants.activeDownloads}');
    return (response.data as List)
        .map((json) => Video.fromJson(json as Map<String, dynamic>))
        .toList();
  });

  // Videos
  Future<Video> getVideo(String id) => _guard(() async {
    final response = await _dio.get('$_baseUrl${AppConstants.videoDetail(id)}');
    return Video.fromJson(response.data as Map<String, dynamic>);
  });

  String getVideoStreamUrl(String id) {
    final token = storage.getSessionToken();
    final base = '$_baseUrl${AppConstants.videoStream(id)}';
    return token != null ? '$base?token=$token' : base;
  }

  Future<void> updateProgress(String videoId, int positionSeconds) =>
      _guard(() async {
        await _dio.put(
          '$_baseUrl${AppConstants.videoProgress(videoId)}',
          data: {'position_seconds': positionSeconds},
        );
      });

  Future<void> deleteVideo(String videoId) => _guard(() async {
    await _dio.delete('$_baseUrl${AppConstants.videoDetail(videoId)}');
  });

  Future<void> downloadVideo(String videoId, {String? quality}) =>
      _guard(() async {
        await _dio.post(
          '$_baseUrl${AppConstants.videoDownload(videoId)}',
          data: quality != null ? {'quality': quality} : null,
        );
      });

  Future<void> cancelDownload(String videoId) => _guard(() async {
    await _dio.post('$_baseUrl${AppConstants.videoCancel(videoId)}');
  });

  Future<void> requestPreview(String videoId) => _guard(() async {
    await _dio.post('$_baseUrl${AppConstants.videoPreview(videoId)}');
  });

  String getPreviewStreamUrl(String id) {
    final token = storage.getSessionToken();
    final base = '$_baseUrl${AppConstants.videoPreviewStream(id)}';
    return token != null ? '$base?token=$token' : base;
  }

  // Feed
  Future<List<FeedItem>> getContinueWatching() => _guard(() async {
    final response = await _dio.get(
      '$_baseUrl${AppConstants.feedContinueWatching}',
    );
    return (response.data as List)
        .map((json) => FeedItem.fromJson(json as Map<String, dynamic>))
        .toList();
  });

  Future<List<FeedItem>> getNewEpisodes() => _guard(() async {
    final response = await _dio.get('$_baseUrl${AppConstants.feedNewEpisodes}');
    return (response.data as List)
        .map((json) => FeedItem.fromJson(json as Map<String, dynamic>))
        .toList();
  });

  Future<List<FeedItem>> getRecentlyAdded() => _guard(() async {
    final response = await _dio.get(
      '$_baseUrl${AppConstants.feedRecentlyAdded}',
    );
    return (response.data as List)
        .map((json) => FeedItem.fromJson(json as Map<String, dynamic>))
        .toList();
  });

  // Discover
  Future<List<Recommendation>> getRecommendations() => _guard(() async {
    final response = await _dio.get('$_baseUrl${AppConstants.discover}');
    return (response.data as List)
        .map((json) => Recommendation.fromJson(json as Map<String, dynamic>))
        .toList();
  });

  Future<void> dismissRecommendation(String id) => _guard(() async {
    await _dio.post('$_baseUrl${AppConstants.discoverDismiss(id)}');
  });

  Future<void> refreshRecommendations() => _guard(() async {
    await _dio.post('$_baseUrl${AppConstants.discoverRefresh}');
  });

  // Health
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get('$_baseUrl${AppConstants.health}');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
