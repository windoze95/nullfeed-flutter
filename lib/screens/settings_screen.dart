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

                  // About section
                  const _SectionHeader(title: 'About'),
                  Card(
                    child: Column(
                      children: [
                        const ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('NullFeed'),
                          subtitle: Text('Version 1.0.0'),
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
