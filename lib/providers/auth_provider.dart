import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_globals.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import 'websocket_provider.dart';

class AuthState {
  final List<User> profiles;
  final User? currentUser;
  final bool isLoading;
  final String? error;

  /// True when a stored session could not be validated due to a network or
  /// server error (NOT a 401). The session is kept so the UI can offer retry
  /// instead of silently logging out.
  final bool restoreFailed;

  const AuthState({
    this.profiles = const [],
    this.currentUser,
    this.isLoading = false,
    this.error,
    this.restoreFailed = false,
  });

  AuthState copyWith({
    List<User>? profiles,
    User? currentUser,
    bool? isLoading,
    String? error,
    bool? restoreFailed,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      profiles: profiles ?? this.profiles,
      currentUser: clearUser ? null : (currentUser ?? this.currentUser),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      restoreFailed: restoreFailed ?? this.restoreFailed,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Let the API layer hand a dead-session 401 back to us so any screen can
    // recover gracefully instead of dead-ending.
    _api.onUnauthorized = _onApiUnauthorized;
    // Deferred so the synchronous part of _restoreSession (which writes
    // `state`) runs after build() returns and the provider is initialized.
    Future.microtask(_restoreSession);
    return const AuthState();
  }

  ApiService get _api => ref.read(apiServiceProvider);
  StorageService get _storage => ref.read(storageServiceProvider);

  String _describe(Object error, String fallback) =>
      error is ApiException ? error.message : fallback;

  Future<void> _restoreSession() async {
    final token = _storage.getSessionToken();
    if (token == null) return;
    state = state.copyWith(isLoading: true, restoreFailed: false);
    try {
      // Validate the stored session instead of re-selecting (which would
      // bypass PIN protection).
      final user = await _api.getMe();
      if (_restoreSuperseded(token)) return;
      state = AuthState(profiles: state.profiles, currentUser: user);
    } on ApiException catch (e) {
      if (_restoreSuperseded(token)) return;
      if (e.statusCode == 401) {
        // Session is gone server-side: clear it and show the picker.
        await _storage.setSelectedUserId(null);
        await _storage.setSessionToken(null);
        state = const AuthState();
      } else {
        // Network/server error: keep the session and let the UI offer retry.
        state = state.copyWith(isLoading: false, restoreFailed: true);
      }
    } catch (_) {
      if (_restoreSuperseded(token)) return;
      state = state.copyWith(isLoading: false, restoreFailed: true);
    }
  }

  /// True when the user signed in manually (or the stored token changed)
  /// while the restore round-trip was in flight — a stale result must not
  /// clobber the fresh session.
  bool _restoreSuperseded(String token) =>
      state.currentUser != null || _storage.getSessionToken() != token;

  /// Retries validating a stored session after [AuthState.restoreFailed].
  Future<void> retryRestore() => _restoreSession();

  Future<void> loadProfiles() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final profiles = await _api.getProfiles();
      state = state.copyWith(profiles: profiles, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _describe(e, 'Failed to load profiles'),
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
        error: _describe(e, 'Failed to select profile'),
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
      await _selectNewProfile(user, pin: pin);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _describe(e, 'Failed to create profile'),
      );
    }
  }

  /// Creates a profile from a YouTube handle. The backend resolves the
  /// channel, defaults the display name to it, and caches the avatar.
  Future<void> createProfileFromYoutube({
    required String handle,
    String? displayName,
    String? pin,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _api.createProfile(
        displayName: displayName,
        pin: pin,
        youtubeHandle: handle,
      );
      await _selectNewProfile(user, pin: pin);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _describe(e, 'Failed to create profile'),
      );
    }
  }

  Future<void> _selectNewProfile(User user, {String? pin}) async {
    // After creating, select the profile to get a session token.
    final result = await _api.selectProfile(user.id, pin: pin);
    await _storage.setSelectedUserId(result.user.id);
    await _storage.setSessionToken(result.token);
    state = state.copyWith(
      profiles: [...state.profiles, result.user],
      currentUser: result.user,
      isLoading: false,
    );
  }

  Future<void> updateProfile(
    String userId, {
    String? displayName,
    String? avatarUrl,
    String? pin,
    bool removePin = false,
    String? tokenOverride,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final updated = await _api.updateProfile(
        userId,
        displayName: displayName,
        avatarUrl: avatarUrl,
        pin: pin,
        removePin: removePin,
        tokenOverride: tokenOverride,
      );
      final profiles = [
        for (final profile in state.profiles)
          if (profile.id == userId) updated else profile,
      ];
      state = state.copyWith(
        profiles: profiles,
        currentUser: state.currentUser?.id == userId
            ? updated
            : state.currentUser,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _describe(e, 'Failed to update profile'),
      );
    }
  }

  Future<void> deleteProfile(String userId, {String? tokenOverride}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _api.deleteProfile(userId, tokenOverride: tokenOverride);
      final profiles = state.profiles
          .where((profile) => profile.id != userId)
          .toList();
      if (state.currentUser?.id == userId) {
        ref.read(webSocketServiceProvider).disconnect();
        await _storage.clearSession();
        state = AuthState(profiles: profiles);
      } else {
        state = state.copyWith(profiles: profiles, isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _describe(e, 'Failed to delete profile'),
      );
    }
  }

  /// Wired to [ApiService.onUnauthorized]: resets to the picker and tells the
  /// user once, even if several requests 401 at the same time.
  void _onApiUnauthorized() {
    if (handleSessionExpired()) {
      showGlobalSnackBar('Session expired — sign in again');
    }
  }

  /// Tears down a signed-in session locally after the server rejected it
  /// (a 401 on a protected endpoint). Mirrors [signOut]'s local cleanup but
  /// skips the logout round-trip — the session is already gone. Returns true
  /// only when a signed-in session was actually cleared, so a burst of 401s
  /// resets (and notifies) exactly once.
  bool handleSessionExpired() {
    if (state.currentUser == null) return false;
    // Reset synchronously first so the router redirects and any concurrent
    // 401 sees the cleared state and bails.
    state = AuthState(profiles: state.profiles);
    ref.read(webSocketServiceProvider).disconnect();
    unawaited(_storage.clearSession());
    return true;
  }

  Future<void> signOut() async {
    try {
      // Best-effort: delete the session server-side.
      await _api.logout();
    } catch (_) {
      // Ignore — local sign-out proceeds regardless.
    }
    ref.read(webSocketServiceProvider).disconnect();
    await _storage.clearSession();
    state = AuthState(profiles: state.profiles);
  }
}

final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
