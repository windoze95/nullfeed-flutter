import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../config/theme.dart';
import '../models/youtube_import.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/profile_avatar.dart';

/// Full-screen profile creation flow.
///
/// Supports a plain name+PIN profile as well as the YouTube import wizard:
/// handle lookup -> identity preview -> suggested-channels multi-select ->
/// optional PIN -> create + select + bulk subscribe -> navigate home.
class AddProfileScreen extends ConsumerStatefulWidget {
  const AddProfileScreen({super.key});

  @override
  ConsumerState<AddProfileScreen> createState() => _AddProfileScreenState();
}

class _AddProfileScreenState extends ConsumerState<AddProfileScreen> {
  static final _pinPattern = RegExp(r'^\d{4,8}$');

  final _nameController = TextEditingController();
  final _handleController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();

  /// True once the user typed in the name field, so a later lookup does not
  /// clobber their edits.
  bool _nameEdited = false;

  YoutubeProfile? _resolvedProfile;
  bool _resolving = false;
  String? _resolveError;

  List<ChannelSuggestion>? _suggestions;
  bool _loadingSuggestions = false;
  String? _suggestionsError;
  Set<String> _selectedSuggestionIds = {};

  bool _creating = false;
  String? _busyStatus;
  String? _createError;
  String? _createdUserId;

  ApiService get _api => ref.read(apiServiceProvider);
  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    super.dispose();
  }

  Future<void> _lookupHandle() async {
    final handle = _handleController.text.trim();
    if (handle.isEmpty || _resolving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _resolving = true;
      _resolveError = null;
      _resolvedProfile = null;
      _suggestions = null;
      _suggestionsError = null;
      _selectedSuggestionIds = {};
    });
    try {
      final profile = await _api.resolveYoutubeHandle(handle);
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _resolvedProfile = profile;
        if (!_nameEdited || _nameController.text.trim().isEmpty) {
          _nameController.text = profile.name;
          _nameEdited = false;
        }
      });
      await _loadSuggestions();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _resolveError = e.message;
      });
    }
  }

  Future<void> _loadSuggestions() async {
    final profile = _resolvedProfile;
    if (profile == null) return;
    setState(() {
      _loadingSuggestions = true;
      _suggestionsError = null;
    });
    try {
      final suggestions = await _api.getYoutubeSuggestions(profile.handle);
      if (!mounted) return;
      setState(() {
        _loadingSuggestions = false;
        _suggestions = suggestions;
        // These are inferred from public featured links/playlists, not an
        // authoritative subscription list. Never opt the user into all of
        // them by default.
        _selectedSuggestionIds = {};
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSuggestions = false;
        _suggestionsError = e.message;
      });
    }
  }

  void _clearImport() {
    setState(() {
      _resolvedProfile = null;
      _resolveError = null;
      _suggestions = null;
      _suggestionsError = null;
      _selectedSuggestionIds = {};
      if (!_nameEdited) _nameController.clear();
    });
  }

  String? _validate() {
    final name = _nameController.text.trim();
    if (_resolvedProfile == null && name.isEmpty) {
      return 'Enter a name or import a profile from YouTube';
    }
    if (name.length > 50) {
      return 'Name must be 50 characters or fewer';
    }
    final pin = _pinController.text;
    if (pin.isNotEmpty) {
      if (!_pinPattern.hasMatch(pin)) {
        return 'PIN must be 4-8 digits';
      }
      if (pin != _pinConfirmController.text) {
        return 'PINs do not match';
      }
    }
    return null;
  }

  Future<void> _create() async {
    if (_creating) return;
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _createError = validationError);
      return;
    }
    FocusScope.of(context).unfocus();
    final name = _nameController.text.trim();
    final pin = _pinController.text.isEmpty ? null : _pinController.text;
    final resolved = _resolvedProfile;
    // Captured up front so the flow completes even if this screen is popped
    // mid-creation (e.g. via a back swipe).
    final api = _api;
    final storage = _storage;
    final authNotifier = ref.read(authStateProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _creating = true;
      _createError = null;
      _busyStatus = 'Creating profile…';
    });
    try {
      final userId =
          _createdUserId ??
          (resolved != null
                  ? await api.createProfile(
                      youtubeHandle: resolved.handle,
                      displayName: name.isEmpty ? null : name,
                      pin: pin,
                    )
                  : await api.createProfile(displayName: name, pin: pin))
              .id;
      // If selecting or subscribing fails after creation, retry the remaining
      // work against this profile instead of creating a duplicate.
      _createdUserId = userId;

      // Select the new profile so a session token exists for bulk subscribe.
      final result = await api.selectProfile(userId, pin: pin);
      await storage.setSelectedUserId(result.user.id);
      await storage.setSessionToken(result.token);

      final checked = [
        for (final suggestion in _suggestions ?? const <ChannelSuggestion>[])
          if (_selectedSuggestionIds.contains(suggestion.youtubeChannelId))
            suggestion,
      ];
      String? followMessage;
      if (checked.isNotEmpty) {
        if (mounted) {
          setState(() => _busyStatus = 'Following ${checked.length} channels…');
        }
        followMessage = await _subscribeToChecked(api, checked);
      }

      if (followMessage != null) {
        messenger.showSnackBar(SnackBar(content: Text(followMessage)));
      }

      // Flip auth state to signed-in (validates the stored token via getMe);
      // the router's redirect then takes over.
      await authNotifier.retryRestore();
      if (!mounted) return;
      if (ref.read(authStateProvider).currentUser != null) {
        context.go('/home');
      } else {
        // Restore failed (network blip): land back on the picker, which
        // shows the session-restore retry banner.
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _busyStatus = null;
        _createError = e.message;
      });
    }
  }

  /// Bulk-subscribes to [checked] and returns a non-blocking summary message.
  Future<String?> _subscribeToChecked(
    ApiService api,
    List<ChannelSuggestion> checked,
  ) async {
    try {
      final results = await api.subscribeBulk(checked);
      final failed = results.where((result) => result.status == 'error').length;
      final followed = results.length - failed;
      if (failed == 0) {
        return 'Followed $followed channels';
      }
      return 'Followed $followed channels, $failed failed';
    } on ApiException catch (e) {
      return 'Profile created, but following channels failed: ${e.message}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_creating,
      child: Scaffold(
        appBar: AppBar(title: const Text('Add Profile')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                controller: _nameController,
                enabled: !_creating,
                maxLength: 50,
                onChanged: (_) => _nameEdited = true,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  counterText: '',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Import from YouTube (optional)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Look up a YouTube profile to copy its name and avatar, and '
                'optionally choose from related public channels.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _handleController,
                      enabled: !_creating && !_resolving,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        hintText: '@handle or channel URL',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      onSubmitted: (_) => _lookupHandle(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _creating || _resolving ? null : _lookupHandle,
                    child: _resolving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Lookup'),
                  ),
                ],
              ),
              if (_resolveError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _resolveError!,
                  style: const TextStyle(
                    color: NullFeedTheme.errorColor,
                    fontSize: 13,
                  ),
                ),
              ],
              if (_resolvedProfile != null) ...[
                const SizedBox(height: 16),
                _IdentityPreviewCard(
                  profile: _resolvedProfile!,
                  onClear: _creating ? null : _clearImport,
                ),
                const SizedBox(height: 16),
                _buildSuggestionsSection(context),
              ],
              const SizedBox(height: 32),
              Text(
                'PIN (optional)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Require a 4-8 digit PIN to open this profile.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _PinField(
                      controller: _pinController,
                      enabled: !_creating,
                      hint: 'PIN',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PinField(
                      controller: _pinConfirmController,
                      enabled: !_creating,
                      hint: 'Confirm PIN',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              if (_createError != null) ...[
                Text(
                  _createError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: NullFeedTheme.errorColor,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              ElevatedButton(
                onPressed: _creating ? null : _create,
                child: _creating
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text(_busyStatus ?? 'Creating profile…'),
                        ],
                      )
                    : const Text('Create Profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsSection(BuildContext context) {
    if (_loadingSuggestions) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text(
            'Looking for related public channels…',
            style: TextStyle(color: NullFeedTheme.textSecondary),
          ),
        ],
      );
    }
    if (_suggestionsError != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              _suggestionsError!,
              style: const TextStyle(
                color: NullFeedTheme.errorColor,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: _creating ? null : _loadSuggestions,
            child: const Text('Retry'),
          ),
        ],
      );
    }
    final suggestions = _suggestions;
    if (suggestions == null) return const SizedBox.shrink();
    if (suggestions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NullFeedTheme.cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'No public channels found — you can add channels later in '
          'Library.',
          style: TextStyle(color: NullFeedTheme.textSecondary),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Related public channels',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '${_selectedSuggestionIds.length} of ${suggestions.length} '
              'selected',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'These come from public featured links and playlists—not a private '
          'YouTube subscription list. Nothing is selected automatically.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: NullFeedTheme.cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (final suggestion in suggestions)
                CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: NullFeedTheme.primaryColor,
                  value: _selectedSuggestionIds.contains(
                    suggestion.youtubeChannelId,
                  ),
                  onChanged: _creating
                      ? null
                      : (checked) {
                          setState(() {
                            if (checked ?? false) {
                              _selectedSuggestionIds.add(
                                suggestion.youtubeChannelId,
                              );
                            } else {
                              _selectedSuggestionIds.remove(
                                suggestion.youtubeChannelId,
                              );
                            }
                          });
                        },
                  title: Text(
                    suggestion.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _sourceLabel(suggestion.source),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _sourceLabel(String source) {
    return switch (source) {
      'featured' => 'Featured channel',
      'playlists' => 'From public playlists',
      _ => source,
    };
  }
}

class _IdentityPreviewCard extends StatelessWidget {
  final YoutubeProfile profile;
  final VoidCallback? onClear;

  const _IdentityPreviewCard({required this.profile, this.onClear});

  static String _formatFollowers(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M subscribers';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K subscribers';
    }
    return '$count subscribers';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NullFeedTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ProfileAvatar(
            name: profile.name,
            avatarUrl: profile.avatarUrl,
            size: 56,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  profile.handle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (profile.followerCount != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatFollowers(profile.followerCount!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onClear,
            tooltip: 'Remove import',
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final String hint;

  const _PinField({
    required this.controller,
    required this.enabled,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 8,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(hintText: hint, counterText: ''),
    );
  }
}
