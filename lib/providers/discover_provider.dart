import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/recommendation.dart';
import '../services/api_service.dart';
import 'session_scope_provider.dart';

class DiscoverNotifier extends Notifier<AsyncValue<List<Recommendation>>> {
  int _requestId = 0;

  @override
  AsyncValue<List<Recommendation>> build() {
    final scope = ref.watch(activeSessionScopeProvider);
    _requestId++;
    if (scope == null) return const AsyncValue.loading();
    Future.microtask(load);
    return const AsyncValue.loading();
  }

  ApiService get _api => ref.read(apiServiceProvider);

  Future<void> load() async {
    final scope = ref.read(activeSessionScopeProvider);
    if (scope == null) {
      state = const AsyncValue.loading();
      return;
    }
    final requestId = ++_requestId;
    state = const AsyncValue.loading();
    try {
      final recs = await _api.getRecommendations();
      if (ref.mounted &&
          requestId == _requestId &&
          ref.read(activeSessionScopeProvider) == scope) {
        state = AsyncValue.data(recs);
      }
    } catch (e, st) {
      if (ref.mounted && requestId == _requestId) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> dismiss(String id) async {
    final scope = ref.read(activeSessionScopeProvider);
    if (scope == null) return;
    final requestId = ++_requestId;
    final previous = state.value;
    // Remove the card immediately, but keep the previous list so a per-card
    // failure never replaces the entire Explore screen with an error state.
    if (previous != null) {
      state = AsyncValue.data(previous.where((rec) => rec.id != id).toList());
    }
    try {
      await _api.dismissRecommendation(id);
    } on ApiException catch (e) {
      // The recommendation is already gone (e.g. cleared by the staleness
      // sweep, or by subscribing to it). The card's job is done — keep it
      // removed rather than resurrecting it and alarming the user.
      if (e.statusCode == 404) return;
      _rollback(requestId, scope, previous);
      rethrow;
    } catch (_) {
      _rollback(requestId, scope, previous);
      rethrow;
    }
  }

  void _rollback(int requestId, Object? scope, List<Recommendation>? previous) {
    if (ref.mounted &&
        requestId == _requestId &&
        ref.read(activeSessionScopeProvider) == scope &&
        previous != null) {
      state = AsyncValue.data(previous);
    }
  }

  Future<void> refresh() async {
    final scope = ref.read(activeSessionScopeProvider);
    if (scope == null) {
      state = const AsyncValue.loading();
      return;
    }
    final requestId = ++_requestId;
    state = const AsyncValue.loading();
    try {
      await _api.refreshRecommendations();
      final recs = await _api.getRecommendations();
      if (ref.mounted &&
          requestId == _requestId &&
          ref.read(activeSessionScopeProvider) == scope) {
        state = AsyncValue.data(recs);
      }
    } catch (e, st) {
      if (ref.mounted && requestId == _requestId) {
        state = AsyncValue.error(e, st);
      }
    }
  }
}

final discoverProvider =
    NotifierProvider<DiscoverNotifier, AsyncValue<List<Recommendation>>>(
      DiscoverNotifier.new,
    );
