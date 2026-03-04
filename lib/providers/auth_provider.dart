import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class AuthState {
  final List<User> profiles;
  final User? currentUser;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.profiles = const [],
    this.currentUser,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    List<User>? profiles,
    User? currentUser,
    bool? isLoading,
    String? error,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      profiles: profiles ?? this.profiles,
      currentUser: clearUser ? null : (currentUser ?? this.currentUser),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _api;
  final StorageService _storage;

  AuthNotifier(this._api, this._storage) : super(const AuthState()) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final userId = _storage.getSelectedUserId();
    if (userId != null) {
      try {
        state = state.copyWith(isLoading: true);
        // Re-select profile to get a fresh session token
        final result = await _api.selectProfile(userId);
        await _storage.setSessionToken(result.token);
        final profiles = await _api.getProfiles();
        state = AuthState(profiles: profiles, currentUser: result.user);
      } catch (_) {
        await _storage.setSelectedUserId(null);
        await _storage.setSessionToken(null);
        state = const AuthState();
      }
    }
  }

  Future<void> loadProfiles() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final profiles = await _api.getProfiles();
      state = state.copyWith(profiles: profiles, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load profiles: $e',
      );
    }
  }

  Future<void> selectProfile(String userId, {String? pin}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await _api.selectProfile(userId, pin: pin);
      await _storage.setSelectedUserId(result.user.id);
      await _storage.setSessionToken(result.token);
      state = state.copyWith(currentUser: result.user, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to select profile: $e',
      );
    }
  }

  Future<void> createProfile({
    required String displayName,
    String? avatarUrl,
    String? pin,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _api.createProfile(
        displayName: displayName,
        avatarUrl: avatarUrl,
        pin: pin,
      );
      // After creating, select the profile to get a session token
      final result = await _api.selectProfile(user.id, pin: pin);
      await _storage.setSelectedUserId(result.user.id);
      await _storage.setSessionToken(result.token);
      state = state.copyWith(
        profiles: [...state.profiles, result.user],
        currentUser: result.user,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to create profile: $e',
      );
    }
  }

  Future<void> signOut() async {
    await _storage.setSessionToken(null);
    await _storage.clearSession();
    state = state.copyWith(clearUser: true);
  }
}

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(apiServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  return AuthNotifier(api, storage);
});
