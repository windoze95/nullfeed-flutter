import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../config/theme.dart';
import '../widgets/adaptive_layout.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _serverUrlController;

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
    final api = ref.read(apiServiceProvider);
    final reachable = await api.checkHealth();
    if (mounted) {
      ref.read(settingsProvider.notifier).setServerReachable(reachable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final authState = ref.watch(authStateProvider);
    final isTv = AdaptiveLayout.isTv(context);
    final padding = AdaptiveLayout.contentPadding(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          if (!isTv)
            const SliverAppBar(
              floating: true,
              title: Text('Settings'),
              backgroundColor: NullFeedTheme.backgroundColor,
            )
          else
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isTv ? 800 : double.infinity,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Profile section
                      const _SectionHeader(title: 'Profile'),
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: NullFeedTheme.primaryColor
                                .withValues(alpha: 0.2),
                            child: Text(
                              authState.currentUser?.displayName.isNotEmpty ==
                                      true
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
                            onPressed: () =>
                                ref.read(authStateProvider.notifier).signOut(),
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
                                  hintText: 'http://192.168.1.100:8484',
                                  suffixIcon: Icon(
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
                                    onPressed: _checkServer,
                                    child: const Text('Test Connection'),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    onPressed: () {
                                      final url = _serverUrlController.text
                                          .trim();
                                      if (url.isNotEmpty) {
                                        ref
                                            .read(settingsProvider.notifier)
                                            .setServerUrl(url);
                                        _checkServer();
                                      }
                                    },
                                    child: const Text('Save'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                settings.isServerReachable
                                    ? 'Connected'
                                    : 'Unable to reach server',
                                style: TextStyle(
                                  color: settings.isServerReachable
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
