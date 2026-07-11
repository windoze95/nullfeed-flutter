import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../models/ai_providers.dart';
import '../services/api_service.dart';
import '../utils/browser_link.dart';

/// Admin panel for the Discover AI providers: API keys (Anthropic / Gemini /
/// OpenAI), the embed + rank provider selection, and the ChatGPT sign-in that
/// backs the subscription-based rank provider. Values are stored server-side;
/// keys are write-only (never read back).
class AiProvidersSection extends ConsumerStatefulWidget {
  const AiProvidersSection({super.key});

  @override
  ConsumerState<AiProvidersSection> createState() => _AiProvidersSectionState();
}

class _AiProvidersSectionState extends ConsumerState<AiProvidersSection> {
  static const _keyProviders = ['anthropic', 'gemini', 'openai'];
  static const _labels = {
    'anthropic': 'Anthropic',
    'gemini': 'Google Gemini',
    'openai': 'OpenAI',
    'chatgpt': 'ChatGPT sign-in',
  };

  AiProvidersStatus? _status;
  bool _loading = true;

  ApiService get _api => ref.read(apiServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _api.getAiProviders();
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

  void _apply(AiProvidersStatus s) {
    if (mounted) setState(() => _status = s);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final status = _status;
    if (status == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text("Couldn't load AI provider settings."),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final provider in _keyProviders) ...[
          _ProviderKeyCard(
            provider: provider,
            label: _labels[provider]!,
            status: status.keys[provider],
            onSaved: _apply,
          ),
          const SizedBox(height: 12),
        ],
        _ChatGptSignInCard(
          available: status.availability['chatgpt'] ?? false,
          onChanged: _load,
        ),
        const SizedBox(height: 16),
        _SelectionCard(
          role: 'embed',
          title: 'Embedding provider',
          description:
              'Turns your subscriptions into vectors for candidate matching. '
              'Needs a Gemini or OpenAI key.',
          selection: status.embed,
          onSaved: _apply,
        ),
        const SizedBox(height: 12),
        _SelectionCard(
          role: 'rank',
          title: 'Ranking provider',
          description:
              'Picks and explains the final recommendations. Can use any key '
              'above, or the ChatGPT sign-in.',
          selection: status.rank,
          onSaved: _apply,
        ),
      ],
    );
  }
}

class _ProviderKeyCard extends ConsumerStatefulWidget {
  const _ProviderKeyCard({
    required this.provider,
    required this.label,
    required this.status,
    required this.onSaved,
  });

  final String provider;
  final String label;
  final AiKeyStatus? status;
  final ValueChanged<AiProvidersStatus> onSaved;

  @override
  ConsumerState<_ProviderKeyCard> createState() => _ProviderKeyCardState();
}

class _ProviderKeyCardState extends ConsumerState<_ProviderKeyCard> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  ApiService get _api => ref.read(apiServiceProvider);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await _api.setAiKey(widget.provider, key);
      if (!mounted) return;
      _controller.clear();
      setState(() => _busy = false);
      widget.onSaved(s);
      _snack('${widget.label} key saved');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    try {
      final s = await _api.clearAiKey(widget.provider);
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onSaved(s);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final configured = status?.configured == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  configured
                      ? Icons.check_circle_outline_rounded
                      : Icons.circle_outlined,
                  size: 18,
                  color: configured
                      ? NullFeedTheme.accentColor
                      : NullFeedTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                if (configured) _keyBadge(status!),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              obscureText: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                hintText: configured ? 'Paste a new key to replace' : 'API key',
                border: const OutlineInputBorder(),
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
                if (configured && status?.source == 'runtime') ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _busy ? null : _clear,
                    child: const Text(
                      'Clear',
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

  Widget _keyBadge(AiKeyStatus status) {
    final env = status.source == 'env';
    final label = status.last4 != null
        ? '••${status.last4}'
        : (env ? 'from env' : 'set');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: NullFeedTheme.elevatedSurfaceColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        env ? '$label · env' : label,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: NullFeedTheme.textMuted,
        ),
      ),
    );
  }
}

class _SelectionCard extends ConsumerStatefulWidget {
  const _SelectionCard({
    required this.role,
    required this.title,
    required this.description,
    required this.selection,
    required this.onSaved,
  });

  final String role;
  final String title;
  final String description;
  final AiSelection selection;
  final ValueChanged<AiProvidersStatus> onSaved;

  @override
  ConsumerState<_SelectionCard> createState() => _SelectionCardState();
}

class _SelectionCardState extends ConsumerState<_SelectionCard> {
  bool _busy = false;

  ApiService get _api => ref.read(apiServiceProvider);

  Future<void> _select(String provider) async {
    setState(() => _busy = true);
    try {
      // Changing the provider clears any stale model override.
      final s = await _api.setAiSelection(widget.role, provider: provider);
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onSaved(s);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selection;
    final effective = sel.effectiveProvider;
    // "" is the auto-detect option; render it as a leading entry.
    final items = ['', ...sel.options];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              widget.description,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: NullFeedTheme.textMuted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in items)
                  ChoiceChip(
                    label: Text(option.isEmpty ? 'Auto' : option),
                    selected: sel.provider == option,
                    onSelected: _busy ? null : (_) => _select(option),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  effective != null
                      ? Icons.bolt_rounded
                      : Icons.error_outline_rounded,
                  size: 16,
                  color: effective != null
                      ? NullFeedTheme.accentColor
                      : NullFeedTheme.errorColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    effective != null
                        ? 'Using $effective (${sel.effectiveModel})'
                              '${sel.provider.isEmpty ? ' · auto' : ''}'
                        : 'None available — add a key or sign in',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: NullFeedTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatGptSignInCard extends ConsumerStatefulWidget {
  const _ChatGptSignInCard({required this.available, required this.onChanged});

  final bool available;

  /// Called after a state change (connected / signed out) so the parent can
  /// refresh availability + effective-provider labels.
  final Future<void> Function() onChanged;

  @override
  ConsumerState<_ChatGptSignInCard> createState() => _ChatGptSignInCardState();
}

class _ChatGptSignInCardState extends ConsumerState<_ChatGptSignInCard> {
  ChatgptLoginStatus? _status;
  Timer? _poller;
  String? _userCode;
  String? _verificationUrl;
  bool _busy = false;
  String? _error;

  ApiService get _api => ref.read(apiServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _api.getChatgptLogin();
      if (!mounted) return;
      setState(() {
        _status = s;
        if (s.pending) {
          _userCode = s.userCode;
          _verificationUrl = s.verificationUrl;
          _startPolling();
        }
      });
    } catch (_) {
      /* leave as unknown */
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api.startChatgptLogin();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _userCode = r.userCode;
        _verificationUrl = r.verificationUrl;
      });
      if (r.verificationUrl != null) openInNewTab(r.verificationUrl!);
      _startPolling();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  Future<void> _poll() async {
    ChatgptPollResult r;
    try {
      r = await _api.pollChatgptLogin();
    } catch (_) {
      return; // transient; keep polling
    }
    if (!mounted) return;
    switch (r.status) {
      case 'connected':
        _poller?.cancel();
        setState(() {
          _userCode = null;
          _verificationUrl = null;
        });
        await _load();
        await widget.onChanged();
        break;
      case 'pending':
        setState(() {
          _userCode = r.userCode ?? _userCode;
          _verificationUrl = r.verificationUrl ?? _verificationUrl;
        });
        break;
      case 'expired':
      case 'error':
      case 'idle':
        _poller?.cancel();
        setState(() {
          _userCode = null;
          _verificationUrl = null;
          _error = r.detail;
        });
        break;
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await _api.clearChatgptLogin();
      _poller?.cancel();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _userCode = null;
        _verificationUrl = null;
      });
      await _load();
      await widget.onChanged();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final connected = status?.connected == true;
    final signingIn = _userCode != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  connected
                      ? Icons.check_circle_outline_rounded
                      : Icons.circle_outlined,
                  size: 18,
                  color: connected
                      ? NullFeedTheme.accentColor
                      : NullFeedTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  'ChatGPT subscription',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                if (status?.needsReauth == true)
                  const Text(
                    'reconnect',
                    style: TextStyle(
                      color: NullFeedTheme.errorColor,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Rank Discover on a ChatGPT Plus/Pro plan instead of an OpenAI '
              'key. Enable device authorization in ChatGPT → Settings → '
              'Security first. Shares your plan\'s Codex usage limits.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: NullFeedTheme.textMuted),
            ),
            if (signingIn) ...[const SizedBox(height: 12), _codePanel()],
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
                if (!connected && !signingIn)
                  FilledButton(
                    onPressed: _busy ? null : _connect,
                    child: _busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: NullFeedTheme.textSecondary,
                            ),
                          )
                        : const Text('Connect'),
                  ),
                if (signingIn)
                  const Text(
                    'Waiting for approval…',
                    style: TextStyle(
                      color: NullFeedTheme.textMuted,
                      fontSize: 13,
                    ),
                  ),
                if (connected)
                  TextButton(
                    onPressed: _busy ? null : _disconnect,
                    child: const Text(
                      'Sign out',
                      style: TextStyle(color: NullFeedTheme.errorColor),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _codePanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NullFeedTheme.elevatedSurfaceColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter this code at the ChatGPT page:'),
          const SizedBox(height: 6),
          SelectableText(
            _userCode ?? '',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 22,
              letterSpacing: 2,
              color: NullFeedTheme.textPrimary,
            ),
          ),
          if (_verificationUrl != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openInNewTab(_verificationUrl!),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Open the sign-in page'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
