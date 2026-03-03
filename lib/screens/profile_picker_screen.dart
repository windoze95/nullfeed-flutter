import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../config/theme.dart';

class ProfilePickerScreen extends ConsumerStatefulWidget {
  const ProfilePickerScreen({super.key});

  @override
  ConsumerState<ProfilePickerScreen> createState() =>
      _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends ConsumerState<ProfilePickerScreen> {
  final _serverUrlController = TextEditingController();
  bool _showServerSetup = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    if (settings.serverUrl == null || settings.serverUrl!.isEmpty) {
      _showServerSetup = true;
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

  Future<void> _connectToServer() async {
    final url = _serverUrlController.text.trim();
    if (url.isEmpty) return;

    await ref.read(settingsProvider.notifier).setServerUrl(url);
    setState(() => _showServerSetup = false);
    ref.read(authStateProvider.notifier).loadProfiles();
  }

  void _showCreateProfileDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NullFeedTheme.cardColor,
        title: const Text('Create Profile'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Display name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                ref
                    .read(authStateProvider.notifier)
                    .createProfile(displayName: name);
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    if (_showServerSetup) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.rss_feed,
                  size: 72,
                  color: NullFeedTheme.primaryColor,
                ),
                const SizedBox(height: 24),
                Text(
                  'NullFeed',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Connect to your server',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: 400,
                  child: TextField(
                    controller: _serverUrlController,
                    decoration: const InputDecoration(
                      hintText: 'http://192.168.1.100:8484',
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                    onSubmitted: (_) => _connectToServer(),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _connectToServer,
                  child: const Text('Connect'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.rss_feed,
                size: 56,
                color: NullFeedTheme.primaryColor,
              ),
              const SizedBox(height: 16),
              Text(
                'Who\'s watching?',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 48),
              if (authState.isLoading)
                const CircularProgressIndicator()
              else if (authState.error != null)
                Column(
                  children: [
                    Text(
                      authState.error!,
                      style: const TextStyle(color: NullFeedTheme.errorColor),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => setState(() => _showServerSetup = true),
                      child: const Text('Change Server'),
                    ),
                  ],
                )
              else
                Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  alignment: WrapAlignment.center,
                  children: [
                    ...authState.profiles.map(
                      (profile) => _ProfileCard(
                        name: profile.displayName,
                        avatarUrl: profile.avatarUrl,
                        onTap: () => ref
                            .read(authStateProvider.notifier)
                            .selectProfile(profile.id),
                      ),
                    ),
                    _ProfileCard(
                      name: 'Add Profile',
                      isAdd: true,
                      onTap: _showCreateProfileDialog,
                    ),
                  ],
                ),
              const SizedBox(height: 48),
              TextButton.icon(
                onPressed: () => setState(() => _showServerSetup = true),
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Server Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatefulWidget {
  final String name;
  final String? avatarUrl;
  final bool isAdd;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.name,
    this.avatarUrl,
    this.isAdd = false,
    required this.onTap,
  });

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform:
              _isHovered ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: widget.isAdd
                      ? NullFeedTheme.cardColor
                      : NullFeedTheme.primaryColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isHovered
                        ? NullFeedTheme.primaryColor
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: widget.isAdd
                    ? const Icon(
                        Icons.add,
                        size: 48,
                        color: NullFeedTheme.textMuted,
                      )
                    : Center(
                        child: Text(
                          widget.name.isNotEmpty
                              ? widget.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: NullFeedTheme.primaryColor,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.name,
                style: TextStyle(
                  color: _isHovered
                      ? NullFeedTheme.textPrimary
                      : NullFeedTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
