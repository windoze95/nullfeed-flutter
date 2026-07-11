import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/constants.dart';
import '../config/theme.dart';
import '../models/active_session_scope.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../utils/browser_link.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/ai_providers_section.dart';
import '../widgets/app_ui.dart';
import '../widgets/profile_avatar.dart';

typedef SettingsServerHealthCheck = Future<bool> Function(String serverUrl);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.healthCheck});

  /// Injectable only so the settings behavior can be tested without making a
  /// real network request. Production uses a short-lived Dio client against
  /// the draft address in the text field.
  final SettingsServerHealthCheck? healthCheck;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _serverUrlController;
  bool _isTesting = false;
  bool _isSaving = false;
  bool? _draftReachable;
  String? _testedUrl;
  String? _connectionMessage;
  late String _lastDraftText;
  int _testToken = 0;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _serverUrlController = TextEditingController(
      text: settings.serverUrl ?? '',
    );
    _lastDraftText = _serverUrlController.text;
    _serverUrlController.addListener(_draftDidChange);
    if (_serverUrlController.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_testConnection(showResult: false));
        }
      });
    }
  }

  @override
  void dispose() {
    _testToken++;
    _serverUrlController.removeListener(_draftDidChange);
    _serverUrlController.dispose();
    super.dispose();
  }

  String get _draftUrl =>
      ActiveSessionScope.normalizeServerUrl(_serverUrlController.text);

  static bool _isValidServerUrl(String value) {
    if (value.isEmpty || value.contains(RegExp(r'\s'))) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static Future<bool> _checkServerHealth(String serverUrl) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );
    try {
      final response = await dio.get<void>('$serverUrl${AppConstants.health}');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      dio.close(force: true);
    }
  }

  void _draftDidChange() {
    if (_serverUrlController.text == _lastDraftText) return;
    _lastDraftText = _serverUrlController.text;
    _testToken++;
    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _draftReachable = null;
      _testedUrl = null;
      _connectionMessage = null;
    });
  }

  Future<bool> _testConnection({bool showResult = true}) async {
    if (_isSaving) return false;
    final url = _draftUrl;
    if (!_isValidServerUrl(url)) {
      setState(() {
        _draftReachable = false;
        _testedUrl = null;
        _connectionMessage =
            'Enter a complete server address, such as '
            '${AppConstants.serverUrlHint}.';
      });
      if (showResult) _showMessage('Enter a valid server address.');
      return false;
    }

    if (_serverUrlController.text != url) {
      _serverUrlController.value = TextEditingValue(
        text: url,
        selection: TextSelection.collapsed(offset: url.length),
      );
    }

    final token = ++_testToken;
    setState(() {
      _isTesting = true;
      _draftReachable = null;
      _testedUrl = url;
      _connectionMessage = 'Checking $url…';
    });

    bool reachable;
    try {
      reachable = await (widget.healthCheck ?? _checkServerHealth)(url);
    } catch (_) {
      reachable = false;
    }
    if (!mounted || token != _testToken || url != _draftUrl) return false;

    setState(() {
      _isTesting = false;
      _draftReachable = reachable;
      _testedUrl = url;
      _connectionMessage = reachable
          ? 'Connection confirmed. This is a NullFeed server you can use.'
          : 'No NullFeed server responded at this address. Check the address '
                'and make sure the server is running.';
    });

    final savedUrl = ref.read(settingsProvider).serverUrl;
    if (savedUrl != null &&
        ActiveSessionScope.normalizeServerUrl(savedUrl) == url) {
      ref.read(settingsProvider.notifier).setServerReachable(reachable);
    }

    if (showResult) {
      _showMessage(
        reachable
            ? 'Connection confirmed for $url'
            : 'Could not connect to $url',
      );
    }
    return reachable;
  }

  Future<void> _saveServerUrl() async {
    if (_isTesting || _isSaving) return;
    final url = _draftUrl;
    final settings = ref.read(settingsProvider);
    final savedUrl = settings.serverUrl == null
        ? ''
        : ActiveSessionScope.normalizeServerUrl(settings.serverUrl!);
    if (!_isValidServerUrl(url)) {
      await _testConnection();
      return;
    }
    if (url == savedUrl) {
      _showMessage('This is already your current server.');
      return;
    }

    final alreadyTested = _testedUrl == url && _draftReachable == true;
    final reachable = alreadyTested
        ? true
        : await _testConnection(showResult: false);
    if (!mounted || !reachable) {
      if (mounted) {
        _showMessage('Test the new address successfully before switching.');
      }
      return;
    }

    final currentUser = ref.read(authStateProvider).currentUser;
    final confirmed = await _confirmServerSwitch(
      currentAddress: savedUrl,
      newAddress: url,
      profileName: currentUser?.displayName,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      // SettingsNotifier owns the safety-critical ordering: it signs out
      // against the old server first, clears the active session scope, and
      // only then persists this new address.
      await ref.read(settingsProvider.notifier).setServerUrl(url);
      if (!mounted) return;
      ref.read(settingsProvider.notifier).setServerReachable(true);
      setState(() {
        _isSaving = false;
        _draftReachable = true;
        _testedUrl = url;
        _connectionMessage =
            'Server switched. Choose a profile on this server to continue.';
      });
      _showMessage('Server switched. Choose a profile to continue.');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _connectionMessage = 'The server address could not be saved.';
      });
      _showMessage('Could not switch servers. Try again.');
    }
  }

  Future<bool?> _confirmServerSwitch({
    required String currentAddress,
    required String newAddress,
    required String? profileName,
  }) {
    final signedInCopy = profileName == null
        ? 'You will choose a profile on the new server.'
        : 'This signs $profileName out. You will choose a profile on the new '
              'server.';
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.swap_horiz_rounded,
          color: NullFeedTheme.warningColor,
        ),
        title: const Text('Switch NullFeed servers?'),
        content: Text(
          'You are switching from ${currentAddress.isEmpty ? 'the current server' : currentAddress} '
          'to $newAddress. $signedInCopy\n\nNothing is deleted from your '
          'current server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              profileName == null
                  ? 'Switch server'
                  : 'Switch server & sign out',
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Switch profile?'),
        content: const Text(
          'You will return to the profile picker. Your channels, watch history, '
          'and queue stay saved on this server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out & choose profile'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(authStateProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final authState = ref.watch(authStateProvider);
    final padding = AdaptiveLayout.contentPadding(context);
    final savedUrl = settings.serverUrl == null
        ? ''
        : ActiveSessionScope.normalizeServerUrl(settings.serverUrl!);
    final hasServerChange = _draftUrl != savedUrl;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(floating: true, title: Text('Settings')),
          const SliverToBoxAdapter(
            child: PageIntro(
              eyebrow: 'You',
              title: 'Profile, server, and access',
              description:
                  'See who is watching and where NullFeed connects. Important '
                  'changes are explained before they happen.',
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(padding, 4, padding, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeader(
                        icon: Icons.person_outline_rounded,
                        title: 'Who is watching',
                        description:
                            'Channels, watch history, and the queue are kept '
                            'separate for each profile.',
                      ),
                      _ProfileCard(
                        displayName:
                            authState.currentUser?.displayName ?? 'No profile',
                        avatarUrl: authState.currentUser?.avatarUrl,
                        serverBaseUrl: settings.serverUrl,
                        isAdmin: authState.currentUser?.isAdmin == true,
                        onSwitchProfile: _confirmSignOut,
                      ),
                      const SizedBox(height: 32),
                      const _SectionHeader(
                        icon: Icons.dns_outlined,
                        title: 'Your NullFeed server',
                        description:
                            'This is the server that stores your channels and '
                            'serves every video to this app.',
                      ),
                      _buildServerCard(
                        currentUrl: savedUrl,
                        hasServerChange: hasServerChange,
                      ),
                      if (authState.currentUser?.isAdmin == true) ...[
                        const SizedBox(height: 32),
                        const _SectionHeader(
                          icon: Icons.lock_open_rounded,
                          title: 'Restricted YouTube videos',
                          description:
                              'Administrators can provide YouTube cookies once '
                              'for every profile on this server.',
                        ),
                        const _YoutubeCookiesSection(),
                        const SizedBox(height: 32),
                        const _SectionHeader(
                          icon: Icons.auto_awesome_rounded,
                          title: 'AI providers',
                          description:
                              'Keys and provider choices for the Discover tab. '
                              'Set here to override the server environment; '
                              'clear to fall back to it.',
                        ),
                        const AiProvidersSection(),
                      ],
                      const SizedBox(height: 32),
                      const _SectionHeader(
                        icon: Icons.info_outline_rounded,
                        title: 'About NullFeed',
                        description:
                            'A quiet, self-hosted home for the channels you '
                            'choose.',
                      ),
                      const Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: NullFeedMark(
                                showWordmark: false,
                                compact: true,
                              ),
                              title: Text('NullFeed'),
                              subtitle: Text('Version 0.1.0'),
                            ),
                            Divider(),
                            ListTile(
                              leading: Icon(Icons.shield_outlined),
                              title: Text('Your server, your feed'),
                              subtitle: Text(
                                'NullFeed keeps playback and profile data on '
                                'the server you control.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerCard({
    required String currentUrl,
    required bool hasServerChange,
  }) {
    final status = switch ((_isTesting, _draftReachable)) {
      (true, _) => const AppStatusPill(
        label: 'Checking address',
        icon: Icons.sync_rounded,
        color: NullFeedTheme.textSecondary,
      ),
      (false, true) => const AppStatusPill(
        label: 'Connection confirmed',
        icon: Icons.check_circle_outline_rounded,
        color: NullFeedTheme.successColor,
      ),
      (false, false) => const AppStatusPill(
        label: 'Cannot connect',
        icon: Icons.error_outline_rounded,
        color: NullFeedTheme.errorColor,
      ),
      _ => const AppStatusPill(
        label: 'Not tested',
        icon: Icons.help_outline_rounded,
        color: NullFeedTheme.textMuted,
      ),
    };
    final statusColor = _draftReachable == false
        ? NullFeedTheme.errorColor
        : NullFeedTheme.textSecondary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Server address',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                status,
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Test the address in this field before saving it. The test does '
              'not change your current connection.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            TextField(
              key: const ValueKey('settings-server-url'),
              controller: _serverUrlController,
              enabled: !_isSaving,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_isTesting && !_isSaving) {
                  unawaited(_testConnection());
                }
              },
              decoration: InputDecoration(
                labelText: 'NullFeed server address',
                hintText: AppConstants.serverUrlHint,
                prefixIcon: const Icon(Icons.lan_outlined),
                suffixIcon: _isTesting
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _draftReachable == null
                    ? null
                    : Icon(
                        _draftReachable!
                            ? Icons.check_circle_rounded
                            : Icons.error_rounded,
                        // The "Connection confirmed" pill is this event's one
                        // green; the suffix check is a quiet echo.
                        color: _draftReachable!
                            ? NullFeedTheme.textSecondary
                            : NullFeedTheme.errorColor,
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('settings-test-connection'),
                  onPressed: _isTesting || _isSaving
                      ? null
                      : () => _testConnection(),
                  icon: const Icon(Icons.wifi_find_rounded, size: 18),
                  label: Text(
                    _isTesting ? 'Testing address…' : 'Test connection',
                  ),
                ),
                ElevatedButton.icon(
                  key: const ValueKey('settings-save-server'),
                  onPressed: _isTesting || _isSaving || !hasServerChange
                      ? null
                      : _saveServerUrl,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NullFeedTheme.textSecondary,
                          ),
                        )
                      : const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: Text(
                    _isSaving ? 'Switching server…' : 'Switch server',
                  ),
                ),
              ],
            ),
            if (_connectionMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                _connectionMessage!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: statusColor),
              ),
            ],
            if (hasServerChange) ...[
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: NullFeedTheme.warningColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: NullFeedTheme.warningColor.withValues(alpha: 0.24),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color: NullFeedTheme.warningColor,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Saving a different address switches servers and signs '
                        'you out. You will choose a profile on the new server.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 14),
            Text(
              'Currently connected to',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 5),
            SelectableText(
              currentUrl.isEmpty ? 'No server configured' : currentUrl,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: NullFeedTheme.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: NullFeedTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: NullFeedTheme.primaryColor.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(icon, color: NullFeedTheme.primaryColor, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.displayName,
    required this.avatarUrl,
    required this.serverBaseUrl,
    required this.isAdmin,
    required this.onSwitchProfile,
  });

  final String displayName;
  final String? avatarUrl;
  final String? serverBaseUrl;
  final bool isAdmin;
  final VoidCallback onSwitchProfile;

  @override
  Widget build(BuildContext context) {
    final identity = Row(
      children: [
        ProfileAvatar(
          name: displayName,
          avatarUrl: avatarUrl,
          serverBaseUrl: serverBaseUrl,
          size: 58,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(displayName, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 5),
              Text(
                isAdmin
                    ? 'Administrator · can manage server access'
                    : 'Viewer profile',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );

    final action = OutlinedButton.icon(
      onPressed: onSwitchProfile,
      icon: const Icon(Icons.switch_account_outlined, size: 18),
      label: const Text('Switch profile'),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [identity, const SizedBox(height: 18), action],
              );
            }
            return Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 18),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Admin panel to paste/refresh a YouTube cookies.txt so age-restricted /
/// members-only videos play. Set once; applies to every profile on the server.
class _YoutubeCookiesSection extends ConsumerStatefulWidget {
  const _YoutubeCookiesSection();

  @override
  ConsumerState<_YoutubeCookiesSection> createState() =>
      _YoutubeCookiesSectionState();
}

class _YoutubeCookiesSectionState
    extends ConsumerState<_YoutubeCookiesSection> {
  final _controller = TextEditingController();
  ({bool configured, bool stale, String? updatedAt, String? lastError})?
  _status;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(apiServiceProvider).getYoutubeCookiesStatus();
      if (mounted) {
        setState(() {
          _status = s;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await ref.read(apiServiceProvider).saveYoutubeCookies(text);
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _status = s;
        _busy = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('YouTube cookies saved')));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.clearYoutubeCookies();
      final s = await api.getYoutubeCookiesStatus();
      if (mounted) {
        setState(() {
          _status = s;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final browser = detectedBrowserName();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              _statusRow(status),
            const SizedBox(height: 12),
            Text(
              'Paste a cookies.txt from a browser signed in to YouTube (e.g. the '
              '"Get cookies.txt LOCALLY" extension) to play age-restricted '
              'videos. Set once — it applies to every profile on this server.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: NullFeedTheme.textMuted),
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => openInNewTab(cookieExtensionUrl()),
                  icon: const Icon(Icons.extension_outlined, size: 18),
                  label: Text(
                    browser == null
                        ? "Get the 'cookies.txt' extension"
                        : "Get the 'cookies.txt' extension for $browser",
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: '# Netscape HTTP Cookie File …',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  color: NullFeedTheme.errorColor,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NullFeedTheme.textSecondary,
                          ),
                        )
                      : const Text('Save'),
                ),
                if (status?.configured == true) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _busy ? null : _remove,
                    child: const Text(
                      'Remove',
                      style: TextStyle(color: NullFeedTheme.errorColor),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(
    ({bool configured, bool stale, String? updatedAt, String? lastError})? s,
  ) {
    if (s == null || !s.configured) {
      return const Row(
        children: [
          Icon(Icons.cancel_outlined, color: NullFeedTheme.textMuted, size: 18),
          SizedBox(width: 8),
          Text('Not connected'),
        ],
      );
    }
    if (s.stale) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: NullFeedTheme.errorColor,
                size: 18,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Cookies aren't working — re-export and paste fresh ones",
                ),
              ),
            ],
          ),
          if (s.lastError != null) ...[
            const SizedBox(height: 6),
            Text(
              s.lastError!,
              style: const TextStyle(
                color: NullFeedTheme.textMuted,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      );
    }
    return Row(
      children: [
        const Icon(
          Icons.check_circle,
          color: NullFeedTheme.successColor,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text('Connected${_formatUpdated(s.updatedAt)}')),
      ],
    );
  }

  String _formatUpdated(String? iso) {
    final dt = iso == null ? null : DateTime.tryParse(iso);
    if (dt == null) return '';
    return ' · updated ${dt.toLocal().toString().split('.').first}';
  }
}
