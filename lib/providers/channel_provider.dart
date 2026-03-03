import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/channel.dart';
import '../models/video.dart';
import '../services/api_service.dart';

final channelsProvider =
    StateNotifierProvider<ChannelsNotifier, AsyncValue<List<Channel>>>((ref) {
  final api = ref.watch(apiServiceProvider);
  return ChannelsNotifier(api);
});

class ChannelsNotifier extends StateNotifier<AsyncValue<List<Channel>>> {
  final ApiService _api;

  ChannelsNotifier(this._api) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final channels = await _api.getChannels();
      state = AsyncValue.data(channels);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> subscribe(String youtubeUrl) async {
    try {
      await _api.subscribeToChannel(youtubeUrl);
      await load();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> unsubscribe(String channelId) async {
    try {
      await _api.unsubscribeFromChannel(channelId);
      await load();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final channelDetailProvider =
    FutureProvider.family<Channel, String>((ref, channelId) async {
  final api = ref.watch(apiServiceProvider);
  return api.getChannel(channelId);
});

final channelVideosProvider =
    FutureProvider.family<List<Video>, String>((ref, channelId) async {
  final api = ref.watch(apiServiceProvider);
  return api.getChannelVideos(channelId);
});
