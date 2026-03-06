import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/channel.dart';
import '../models/video.dart';
import '../services/api_service.dart';

class ChannelsNotifier extends Notifier<AsyncValue<List<Channel>>> {
  @override
  AsyncValue<List<Channel>> build() {
    load();
    return const AsyncValue.loading();
  }

  ApiService get _api => ref.read(apiServiceProvider);

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final channels = await _api.getChannels();
      state = AsyncValue.data(channels);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> subscribe(
    String youtubeUrl, {
    String trackingMode = 'FUTURE_ONLY',
  }) async {
    try {
      await _api.subscribeToChannel(youtubeUrl, trackingMode: trackingMode);
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

final channelsProvider =
    NotifierProvider<ChannelsNotifier, AsyncValue<List<Channel>>>(
      ChannelsNotifier.new,
    );

final channelDetailProvider = FutureProvider.family<Channel, String>((
  ref,
  channelId,
) async {
  final api = ref.watch(apiServiceProvider);
  return api.getChannel(channelId);
});

final channelVideosProvider = FutureProvider.family<List<Video>, String>((
  ref,
  channelId,
) async {
  final api = ref.watch(apiServiceProvider);
  return api.getChannelVideos(channelId);
});
