import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/constants.dart';
import '../models/user.dart';
import '../models/channel.dart';
import '../models/video.dart';
import '../models/feed.dart';
import '../models/recommendation.dart';
import 'storage_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return ApiService(storage: storage);
});

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
          final token = storage.getSessionToken();
          if (token != null) {
            options.headers['X-User-Token'] = token;
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

  // Auth
  Future<List<User>> getProfiles() async {
    final response = await _dio.post('$_baseUrl${AppConstants.authProfiles}');
    return (response.data as List)
        .map((json) => User.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<({User user, String token})> selectProfile(
    String userId, {
    String? pin,
  }) async {
    final response = await _dio.post(
      '$_baseUrl${AppConstants.authSelect}',
      data: {'user_id': userId, if (pin != null) 'pin': pin},
    );
    final data = response.data as Map<String, dynamic>;
    final user = User.fromJson(data['user'] as Map<String, dynamic>);
    final token = data['token'] as String;
    return (user: user, token: token);
  }

  Future<User> createProfile({
    required String displayName,
    String? avatarUrl,
    String? pin,
  }) async {
    final response = await _dio.post(
      '$_baseUrl${AppConstants.authCreate}',
      data: {
        'display_name': displayName,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (pin != null) 'pin': pin,
      },
    );
    return User.fromJson(response.data as Map<String, dynamic>);
  }

  // Channels
  Future<List<Channel>> getChannels() async {
    final response = await _dio.get('$_baseUrl${AppConstants.channels}');
    return (response.data as List)
        .map((json) => Channel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Channel> getChannel(String id) async {
    final response = await _dio.get(
      '$_baseUrl${AppConstants.channelDetail(id)}',
    );
    return Channel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<Video>> getChannelVideos(String channelId) async {
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
  }

  Future<void> subscribeToChannel(
    String youtubeUrl, {
    String trackingMode = 'FUTURE_ONLY',
  }) async {
    await _dio.post(
      '$_baseUrl${AppConstants.channelSubscribe}',
      data: {'url': youtubeUrl, 'tracking_mode': trackingMode},
    );
  }

  Future<Channel> refreshChannelImages(String channelId) async {
    final response = await _dio.post(
      '$_baseUrl${AppConstants.channelRefreshImages(channelId)}',
    );
    return Channel.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> unsubscribeFromChannel(String channelId) async {
    await _dio.delete('$_baseUrl${AppConstants.channelUnsubscribe(channelId)}');
  }

  // Downloads
  Future<List<Video>> getActiveDownloads() async {
    final response = await _dio.get('$_baseUrl${AppConstants.activeDownloads}');
    return (response.data as List)
        .map((json) => Video.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // Videos
  Future<Video> getVideo(String id) async {
    final response = await _dio.get('$_baseUrl${AppConstants.videoDetail(id)}');
    return Video.fromJson(response.data as Map<String, dynamic>);
  }

  String getVideoStreamUrl(String id) {
    final token = storage.getSessionToken();
    final base = '$_baseUrl${AppConstants.videoStream(id)}';
    return token != null ? '$base?token=$token' : base;
  }

  Future<void> updateProgress(String videoId, int positionSeconds) async {
    await _dio.put(
      '$_baseUrl${AppConstants.videoProgress(videoId)}',
      data: {'position_seconds': positionSeconds},
    );
  }

  Future<void> deleteVideo(String videoId) async {
    await _dio.delete('$_baseUrl${AppConstants.videoDetail(videoId)}');
  }

  Future<void> downloadVideo(String videoId) async {
    await _dio.post('$_baseUrl${AppConstants.videoDownload(videoId)}');
  }

  Future<void> cancelDownload(String videoId) async {
    await _dio.post('$_baseUrl${AppConstants.videoCancel(videoId)}');
  }

  Future<void> requestPreview(String videoId) async {
    await _dio.post('$_baseUrl${AppConstants.videoPreview(videoId)}');
  }

  String getPreviewStreamUrl(String id) {
    final token = storage.getSessionToken();
    final base = '$_baseUrl${AppConstants.videoPreviewStream(id)}';
    return token != null ? '$base?token=$token' : base;
  }

  // Feed
  Future<List<FeedItem>> getContinueWatching() async {
    final response = await _dio.get(
      '$_baseUrl${AppConstants.feedContinueWatching}',
    );
    return (response.data as List)
        .map((json) => FeedItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<FeedItem>> getNewEpisodes() async {
    final response = await _dio.get('$_baseUrl${AppConstants.feedNewEpisodes}');
    return (response.data as List)
        .map((json) => FeedItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<FeedItem>> getRecentlyAdded() async {
    final response = await _dio.get(
      '$_baseUrl${AppConstants.feedRecentlyAdded}',
    );
    return (response.data as List)
        .map((json) => FeedItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // Discover
  Future<List<Recommendation>> getRecommendations() async {
    final response = await _dio.get('$_baseUrl${AppConstants.discover}');
    return (response.data as List)
        .map((json) => Recommendation.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> dismissRecommendation(String id) async {
    await _dio.post('$_baseUrl${AppConstants.discoverDismiss(id)}');
  }

  Future<void> refreshRecommendations() async {
    await _dio.post('$_baseUrl${AppConstants.discoverRefresh}');
  }

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
