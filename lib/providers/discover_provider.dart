import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/recommendation.dart';
import '../services/api_service.dart';

class DiscoverNotifier extends Notifier<AsyncValue<List<Recommendation>>> {
  @override
  AsyncValue<List<Recommendation>> build() {
    load();
    return const AsyncValue.loading();
  }

  ApiService get _api => ref.read(apiServiceProvider);

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final recs = await _api.getRecommendations();
      state = AsyncValue.data(recs);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> dismiss(String id) async {
    try {
      await _api.dismissRecommendation(id);
      state.whenData((recs) {
        state = AsyncValue.data(recs.where((r) => r.id != id).toList());
      });
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      await _api.refreshRecommendations();
      final recs = await _api.getRecommendations();
      state = AsyncValue.data(recs);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final discoverProvider =
    NotifierProvider<DiscoverNotifier, AsyncValue<List<Recommendation>>>(
      DiscoverNotifier.new,
    );
