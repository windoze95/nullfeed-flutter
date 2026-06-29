import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/channel_provider.dart';
import '../providers/discover_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/video_provider.dart';
import '../providers/websocket_provider.dart';
import '../services/api_service.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../utils/browser_link.dart';
import '../widgets/adaptive_layout.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _serverUrlController;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _serverUrlController = TextEditingController(
      text: settings.serverUrl ?? '',
    );
    _checkServer();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _checkServer() async {
    if (mounted) setState(() => _isTesting = true);
    final api = ref.read(apiServiceProvider);
    final reachable = await api.checkHealth();
    if (!mounted) return;
    ref.read(settingsProvider.notifier).setServerReachable(reachable);
    setState(() => _isTesting = false);
  }

  Future<void> _testConnection() async {
    await _checkServer();
    if (!mounted) return;
    final reachable = ref.read(settingsProvider).isServerReachable;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reachable ? 'Server is reachable' : 'Could not reach the server',
        ),
      ),
    );
  }

  Future<void> _saveServerUrl() async {
    final url = _serverUrlController.text.trim();
    if (url.isEmpty) return;

    await ref.read(settingsProvider.notifier).setServerUrl(url);
    if (!mounted) return;

    // Reconnect the WebSocket and refetch everything against the new server.
    ref.invalidate(webSocketConnectionProvider);
    ref.invalidate(channelsProvider);
    ref.invalidate(channelDetailProvider);
    ref.invalidate(channelVideosProvider);
    ref.invalidate(videoDetailProvider);
    ref.invalidate(homeFeedProvider);
    ref.invalidate(continueWatchingProvider);
    ref.invalidate(newEpisodesProvider);
    ref.invalidate(recentlyAddedProvider);
    ref.invalidate(discoverProvider);

    await _testConnection();
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NullFeedTheme.cardColor,
        title: const Text('Switch profile?'),
        content: const Text('You will be signed out of this profile.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign Out'),
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

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            floating: true,
            title: Text('Settings'),
            backgroundColor: NullFeedTheme.backgroundColor,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile section
                  const _SectionHeader(title: 'Profile'),
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: NullFeedTheme.primaryColor.withValues(
                          alpha: 0.2,
                        ),
                        child: Text(
                          authState.currentUser?.displayName.isNotEmpty == true
                              ? authState.currentUser!.displayName[0]
                                    .toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: NullFeedTheme.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        authState.currentUser?.displayName ?? 'Unknown',
                      ),
                      subtitle: Text(
                        authState.currentUser?.isAdmin == true
                            ? 'Administrator'
                            : 'User',
                      ),
                      trailing: OutlinedButton(
                        onPressed: _confirmSignOut,
                        child: const Text('Switch Profile'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Server section
                  const _SectionHeader(title: 'Server Connection'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _serverUrlController,
                            decoration: InputDecoration(
                              labelText: 'Server URL',
                              hintText: AppConstants.serverUrlHint,
                              suffixIcon: _isTesting
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      settings.isServerReachable
                                          ? Icons.check_circle
                                          : Icons.error,
                                      color: settings.isServerReachable
                                          ? NullFeedTheme.successColor
                                          : NullFeedTheme.errorColor,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              OutlinedButton(
                                onPressed: _isTesting ? null : _testConnection,
                                child: _isTesting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Test Connection'),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: _isTesting ? null : _saveServerUrl,
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isTesting
                                ? 'Testing connection…'
                                : settings.isServerReachable
                                ? 'Connected'
                                : 'Unable to reach server',
                            style: TextStyle(
                              color: _isTesting
                                  ? NullFeedTheme.textMuted
                                  : settings.isServerReachable
                                  ? NullFeedTheme.successColor
                                  : NullFeedTheme.errorColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Quality section
                  const _SectionHeader(title: 'Download Quality'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: RadioGroup<String>(
                        groupValue: settings.preferredQuality,
                        onChanged: (value) {
                          if (value != null) {
                            ref
                                .read(settingsProvider.notifier)
                                .setPreferredQuality(value);
                          }
                        },
                        child: Column(
                          children: qualityOptions
                              .map(
                                (quality) => RadioListTile<String>(
                                  title: Text(quality),
                                  value: quality,
                                  activeColor: NullFeedTheme.primaryColor,
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Used when you start a download from a channel page.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: NullFeedTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // YouTube account (admin only) — enables age-restricted videos
                  // for everyone on this server.
                  if (authState.currentUser?.isAdmin == true) ...[
                    const _SectionHeader(title: 'YouTube Account'),
                    const _YoutubeCookiesSection(),
                    const SizedBox(height: 24),
                  ],

                  // About section
                  const _SectionHeader(title: 'About'),
                  Card(
                    child: Column(
                      children: [
                        const ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('NullFeed'),
                          subtitle: Text('Version 0.1.0'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.code),
                          title: const Text('Server URL'),
                          subtitle: Text(
                            settings.serverUrl ?? 'Not configured',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
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
