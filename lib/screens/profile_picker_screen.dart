import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../utils/browser_link.dart';
import '../widgets/pin_entry_dialog.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/app_ui.dart';
import 'add_profile_screen.dart';

class ProfilePickerScreen extends ConsumerStatefulWidget {
  const ProfilePickerScreen({super.key});

  @override
  ConsumerState<ProfilePickerScreen> createState() =>
      _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends ConsumerState<ProfilePickerScreen> {
  final _serverUrlController = TextEditingController();
  bool _showServerSetup = false;
  bool _checkingServer = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    if (settings.serverUrl == null || settings.serverUrl!.isEmpty) {
      _showServerSetup = true;
      final browserOrigin = currentBrowserOrigin();
      if (browserOrigin != null) {
        // Web is served by the backend, so asking users to discover and type
        // the very origin they are already visiting only adds failure points.
        _serverUrlController.text = browserOrigin;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _connectToServer();
        });
      }
    } else {
      _serverUrlController.text = settings.serverUrl!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(authStateProvider.notifier).loadProfiles();
      });
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------
  // Server setup
  // ---------------------------------------------------------------------

  /// Prepends `http://` when no scheme is given and strips trailing slashes.
  static String _normalizeServerUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Health-checks [url] directly (it is not saved to storage yet, so the
  /// shared [ApiService] cannot be used).
  static Future<bool> _checkServerHealth(String url) async {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final response = await dio.get<void>('$url${AppConstants.health}');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _connectToServer({bool skipHealthCheck = false}) async {
    final url = _normalizeServerUrl(_serverUrlController.text);
    if (url.isEmpty || _checkingServer) return;
    _serverUrlController.text = url;

    if (!skipHealthCheck) {
      setState(() {
        _checkingServer = true;
        _serverError = null;
      });
      final healthy = await _checkServerHealth(url);
      if (!mounted) return;
      if (!healthy) {
        setState(() {
          _checkingServer = false;
          _serverError = 'Could not reach a NullFeed server at $url';
        });
        return;
      }
    }

    await ref.read(settingsProvider.notifier).setServerUrl(url);
    if (!mounted) return;
    setState(() {
      _showServerSetup = false;
      _checkingServer = false;
      _serverError = null;
    });
    ref.read(authStateProvider.notifier).loadProfiles();
  }

  // ---------------------------------------------------------------------
  // Profile selection
  // ---------------------------------------------------------------------

  Future<void> _selectProfile(User profile) async {
    if (profile.hasPin) {
      await _selectWithPin(profile);
      return;
    }
    await ref.read(authStateProvider.notifier).selectProfile(profile.id);
    if (!mounted) return;
    final auth = ref.read(authStateProvider);
    if (auth.currentUser != null || auth.error == null) return;
    if (auth.error == 'PIN required') {
      // Local profile data was stale: the server says a PIN is set.
      await _selectWithPin(profile);
    } else {
      // Keep the grid; surface the error non-destructively.
      _showSnackBar(auth.error!);
    }
  }

  Future<void> _selectWithPin(User profile) async {
    await showDialog<String>(
      context: context,
      builder: (context) => PinEntryDialog(
        title: 'Enter PIN',
        subtitle: 'Enter the PIN for ${profile.displayName}',
        onSubmit: (pin) async {
          await ref
              .read(authStateProvider.notifier)
              .selectProfile(profile.id, pin: pin);
          final auth = ref.read(authStateProvider);
          if (auth.currentUser?.id == profile.id) return null;
          return auth.error ?? 'Incorrect PIN';
        },
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Profile management (edit / delete from the picker, pre-login)
  // ---------------------------------------------------------------------

  /// Obtains a session token for [profile] (prompting for its PIN when set)
  /// so edit/delete calls can authenticate without signing anyone in. The
  /// token lives only in memory and is passed per-request — it never touches
  /// the persistent session slot, so it cannot leak into the next launch or
  /// clobber a kept-but-unvalidated restorable session.
  Future<String?> _acquireManagementToken(User profile) async {
    final api = ref.read(apiServiceProvider);
    if (profile.hasPin) {
      String? acquired;
      await showDialog<String>(
        context: context,
        builder: (context) => PinEntryDialog(
          title: 'Enter PIN',
          subtitle:
              'Enter the PIN for ${profile.displayName} to manage this '
              'profile',
          confirmLabel: 'Continue',
          onSubmit: (pin) async {
            try {
              final result = await api.selectProfile(profile.id, pin: pin);
              acquired = result.token;
              return null;
            } on ApiException catch (e) {
              return e.message;
            }
          },
        ),
      );
      return acquired;
    }
    try {
      final result = await api.selectProfile(profile.id);
      return result.token;
    } on ApiException catch (e) {
      if (mounted) _showSnackBar(e.message);
      return null;
    }
  }

  Future<void> _releaseManagementToken(String token) async {
    try {
      await ref.read(apiServiceProvider).logout(tokenOverride: token);
    } catch (_) {
      // Best-effort: an unreleased token simply expires with the session
      // table; nothing is persisted client-side.
    }
  }

  void _showProfileOptions(User profile) {
    final serverUrl = ref.read(settingsProvider).serverUrl;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: ProfileAvatar(
                name: profile.displayName,
                avatarUrl: profile.avatarUrl,
                serverBaseUrl: serverUrl,
                size: 40,
              ),
              title: Text(profile.displayName),
              subtitle: profile.isAdmin ? const Text('Admin') : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Profile'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _editProfile(profile);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: NullFeedTheme.errorColor,
              ),
              title: const Text(
                'Delete Profile',
                style: TextStyle(color: NullFeedTheme.errorColor),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _deleteProfile(profile);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editProfile(User profile) async {
    final token = await _acquireManagementToken(profile);
    if (token == null || !mounted) {
      if (token != null) await _releaseManagementToken(token);
      return;
    }
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) =>
            _EditProfileSheet(profile: profile, managementToken: token),
      );
    } finally {
      await _releaseManagementToken(token);
    }
  }

  Future<void> _deleteProfile(User profile) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete profile?'),
            content: Text(
              'Delete ${profile.displayName}? Their subscriptions and watch '
              'history will be removed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: NullFeedTheme.errorColor,
                  foregroundColor: Theme.of(dialogContext).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    final token = await _acquireManagementToken(profile);
    if (token == null || !mounted) {
      if (token != null) await _releaseManagementToken(token);
      return;
    }
    try {
      await ref
          .read(authStateProvider.notifier)
          .deleteProfile(profile.id, tokenOverride: token);
      if (!mounted) return;
      final error = ref.read(authStateProvider).error;
      _showSnackBar(error ?? 'Deleted ${profile.displayName}');
    } finally {
      await _releaseManagementToken(token);
    }
  }

  void _openAddProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const AddProfileScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    if (_showServerSetup) {
      return _buildServerSetup(context);
    }

    return Scaffold(
      backgroundColor: NullFeedTheme.backgroundColor,
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const NullFeedMark(),
                    const SizedBox(height: 36),
                    const AppStatusPill(
                      label: 'PERSONAL SPACE',
                      icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Who\'s watching?',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'Choose a profile so watch history, suggestions, and '
                      'progress stay personal.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (authState.restoreFailed) ...[
                      const SizedBox(height: 24),
                      _RestoreFailedBanner(
                        onRetry: () =>
                            ref.read(authStateProvider.notifier).retryRestore(),
                      ),
                    ],
                    const SizedBox(height: 34),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child:
                          authState.isLoading && authState.profiles.isNotEmpty
                          ? const SizedBox(
                              key: ValueKey('loading'),
                              width: 220,
                              child: LinearProgressIndicator(minHeight: 3),
                            )
                          : const SizedBox(key: ValueKey('idle'), height: 3),
                    ),
                    const SizedBox(height: 18),
                    _buildProfilesArea(authState),
                    const SizedBox(height: 38),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _serverError = null;
                        _showServerSetup = true;
                      }),
                      icon: const Icon(Icons.dns_outlined, size: 18),
                      label: const Text('Server Settings'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfilesArea(AuthState authState) {
    if (authState.profiles.isEmpty) {
      if (authState.isLoading) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        );
      }
      if (authState.error != null) {
        return _ErrorCard(
          message: authState.error!,
          onRetry: () => ref.read(authStateProvider.notifier).loadProfiles(),
          onChangeServer: () => setState(() {
            _serverError = null;
            _showServerSetup = true;
          }),
        );
      }
    }

    final serverUrl = ref.read(settingsProvider).serverUrl;
    return Wrap(
      spacing: 24,
      runSpacing: 24,
      alignment: WrapAlignment.center,
      children: [
        ...authState.profiles.map(
          (profile) => _ProfileCard(
            profile: profile,
            serverBaseUrl: serverUrl,
            onTap: () => _selectProfile(profile),
            onShowOptions: () => _showProfileOptions(profile),
          ),
        ),
        _AddProfileCard(onTap: _openAddProfile),
      ],
    );
  }

  Widget _buildServerSetup(BuildContext context) {
    final hasExistingServer =
        (ref.read(settingsProvider).serverUrl ?? '').isNotEmpty;

    return Scaffold(
      backgroundColor: NullFeedTheme.backgroundColor,
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: NullFeedTheme.surfaceColor.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: NullFeedTheme.borderColor),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x52000000),
                        blurRadius: 42,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          NullFeedMark(compact: true),
                          AppStatusPill(label: 'STEP 1 OF 2'),
                        ],
                      ),
                      const SizedBox(height: 34),
                      Text(
                        'Connect to your server',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 9),
                      Text(
                        'NullFeed runs on hardware you control. Enter the '
                        'address you use to open it on this network.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _serverUrlController,
                        enabled: !_checkingServer,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Server address',
                          hintText: AppConstants.serverUrlHint,
                          helperText: 'Usually an IP address followed by :8484',
                          prefixIcon: Icon(Icons.dns_outlined),
                        ),
                        onSubmitted: (_) => _connectToServer(),
                      ),
                      if (_serverError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: NullFeedTheme.errorColor.withValues(
                              alpha: 0.08,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: NullFeedTheme.errorColor.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                          child: Text(
                            _serverError!,
                            style: const TextStyle(
                              color: NullFeedTheme.errorColor,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _checkingServer ? null : _connectToServer,
                          icon: _checkingServer
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                ),
                          label: const Text('Connect'),
                        ),
                      ),
                      if (_serverError != null)
                        Center(
                          child: TextButton(
                            onPressed: _checkingServer
                                ? null
                                : () => _connectToServer(skipHealthCheck: true),
                            child: const Text('Save anyway'),
                          ),
                        ),
                      if (hasExistingServer)
                        Center(
                          child: TextButton(
                            onPressed: _checkingServer
                                ? null
                                : () => setState(() {
                                    _serverUrlController.text =
                                        ref.read(settingsProvider).serverUrl ??
                                        '';
                                    _serverError = null;
                                    _showServerSetup = false;
                                  }),
                            child: const Text('Cancel'),
                          ),
                        ),
                      const SizedBox(height: 14),
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 16,
                            color: NullFeedTheme.textMuted,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your address stays on this device. Your media '
                              'and watch history stay on your server.',
                              style: TextStyle(
                                color: NullFeedTheme.textMuted,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Widgets
// -------------------------------------------------------------------------

class _RestoreFailedBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const _RestoreFailedBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: NullFeedTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Couldn\'t restore your session. Check the server and try '
              'again.',
              style: TextStyle(
                color: NullFeedTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onChangeServer;

  const _ErrorCard({
    required this.message,
    required this.onRetry,
    required this.onChangeServer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NullFeedTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size: 32,
            color: NullFeedTheme.errorColor,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(
                onPressed: onChangeServer,
                child: const Text('Change Server'),
              ),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final User profile;
  final String? serverBaseUrl;
  final VoidCallback onTap;
  final VoidCallback onShowOptions;

  const _ProfileCard({
    required this.profile,
    this.serverBaseUrl,
    required this.onTap,
    required this.onShowOptions,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 154,
      child: Semantics(
        button: true,
        label: 'Continue as ${profile.displayName}',
        child: Material(
          color: NullFeedTheme.cardColor.withValues(alpha: 0.86),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: NullFeedTheme.borderColor),
            borderRadius: BorderRadius.circular(22),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onShowOptions,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      ProfileAvatar(
                        name: profile.displayName,
                        avatarUrl: profile.avatarUrl,
                        serverBaseUrl: serverBaseUrl,
                        size: 128,
                        borderRadius: 17,
                      ),
                      if (profile.hasPin)
                        Positioned(
                          left: 7,
                          top: 7,
                          child: Container(
                            width: 29,
                            height: 29,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                            ),
                            child: const Icon(
                              Icons.lock,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Positioned(
                        right: 1,
                        top: 1,
                        child: IconButton(
                          onPressed: onShowOptions,
                          icon: const Icon(Icons.more_horiz_rounded, size: 19),
                          color: Colors.white,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.66,
                            ),
                          ),
                          tooltip: 'Profile actions',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: NullFeedTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    profile.hasPin ? 'PIN protected' : 'Tap to continue',
                    style: const TextStyle(
                      color: NullFeedTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddProfileCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AddProfileCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 154,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: NullFeedTheme.borderColor),
          borderRadius: BorderRadius.circular(22),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 128,
                  height: 128,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: NullFeedTheme.cardColor,
                      borderRadius: BorderRadius.all(Radius.circular(17)),
                    ),
                    child: Icon(
                      Icons.person_add_alt_1_rounded,
                      size: 40,
                      color: NullFeedTheme.primaryColor,
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Add Profile',
                  style: TextStyle(
                    color: NullFeedTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Create a personal space',
                  style: TextStyle(
                    color: NullFeedTheme.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet editor for an existing profile: rename, set/remove PIN, and
/// re-import the avatar from a YouTube handle. Requires a management token
/// to already be stored (see [_ProfilePickerScreenState._editProfile]).
class _EditProfileSheet extends ConsumerStatefulWidget {
  final User profile;
  final String managementToken;

  const _EditProfileSheet({
    required this.profile,
    required this.managementToken,
  });

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  static final _pinPattern = RegExp(r'^\d{4,8}$');

  late final TextEditingController _nameController = TextEditingController(
    text: widget.profile.displayName,
  );
  final _handleController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();

  String? _importedAvatarUrl;
  bool _importing = false;
  String? _importError;
  bool _removePin = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    super.dispose();
  }

  Future<void> _importAvatar() async {
    final handle = _handleController.text.trim();
    if (handle.isEmpty || _importing) return;
    setState(() {
      _importing = true;
      _importError = null;
    });
    try {
      final profile = await ref
          .read(apiServiceProvider)
          .resolveYoutubeHandle(handle);
      if (!mounted) return;
      setState(() {
        _importing = false;
        if (profile.avatarUrl == null) {
          _importError = 'That channel has no avatar image';
        } else {
          _importedAvatarUrl = profile.avatarUrl;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importError = e.message;
      });
    }
  }

  String? _validate() {
    final name = _nameController.text.trim();
    if (name.isEmpty || name.length > 50) {
      return 'Name must be 1-50 characters';
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

  Future<void> _save() async {
    if (_saving) return;
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    final name = _nameController.text.trim();
    final pin = _pinController.text;
    setState(() {
      _saving = true;
      _error = null;
    });
    final notifier = ref.read(authStateProvider.notifier);
    await notifier.updateProfile(
      widget.profile.id,
      displayName: name != widget.profile.displayName ? name : null,
      avatarUrl: _importedAvatarUrl,
      pin: pin.isEmpty ? null : pin,
      removePin: pin.isEmpty && _removePin,
      tokenOverride: widget.managementToken,
    );
    if (!mounted) return;
    final error = ref.read(authStateProvider).error;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final serverUrl = ref.read(settingsProvider).serverUrl;
    final hasNewPin = _pinController.text.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit Profile',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              Center(
                child: ProfileAvatar(
                  name: _nameController.text,
                  avatarUrl: _importedAvatarUrl ?? widget.profile.avatarUrl,
                  serverBaseUrl: serverUrl,
                  size: 72,
                  borderRadius: 16,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                enabled: !_saving,
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  counterText: '',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Import avatar from YouTube',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _handleController,
                      enabled: !_saving && !_importing,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        hintText: '@handle or channel URL',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      onSubmitted: (_) => _importAvatar(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saving || _importing ? null : _importAvatar,
                    child: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Import'),
                  ),
                ],
              ),
              if (_importError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _importError!,
                  style: const TextStyle(
                    color: NullFeedTheme.errorColor,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text('PIN', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (widget.profile.hasPin && !hasNewPin)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _removePin
                            ? 'PIN will be removed'
                            : 'This profile has a PIN',
                        style: const TextStyle(
                          color: NullFeedTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _removePin = !_removePin),
                      child: Text(_removePin ? 'Keep PIN' : 'Remove PIN'),
                    ),
                  ],
                ),
              if (!_removePin) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pinController,
                        enabled: !_saving,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 8,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: widget.profile.hasPin
                              ? 'New PIN (optional)'
                              : 'PIN (optional)',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _pinConfirmController,
                        enabled: !_saving,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 8,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          hintText: 'Confirm PIN',
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: NullFeedTheme.errorColor,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
