/// Admin-managed AI provider configuration (Discover pipeline).
///
/// Parsed from `GET /api/settings/ai-providers`. Keys are never returned by
/// the server — only their status (configured / source / masked last 4).
library;

/// Status of one provider API key.
class AiKeyStatus {
  const AiKeyStatus({
    required this.configured,
    required this.source,
    required this.last4,
  });

  /// Whether an effective key exists (runtime override or env fallback).
  final bool configured;

  /// Where the effective value comes from: `runtime`, `env`, or null.
  final String? source;

  /// Last 4 chars of the effective key, or null when hidden/short.
  final String? last4;

  factory AiKeyStatus.fromJson(Map<String, dynamic> json) => AiKeyStatus(
    configured: json['configured'] == true,
    source: json['source'] as String?,
    last4: json['last4'] as String?,
  );
}

/// The embed or rank provider selection plus what's actually live.
class AiSelection {
  const AiSelection({
    required this.provider,
    required this.model,
    required this.source,
    required this.effectiveProvider,
    required this.effectiveModel,
    required this.options,
  });

  /// The configured provider (`""` means auto-detect).
  final String provider;

  /// Optional model override (`""` means the provider default).
  final String model;

  /// `runtime` when pinned in-app, else `env`.
  final String source;

  /// The provider that will actually be used, or null when none is available.
  final String? effectiveProvider;
  final String? effectiveModel;

  /// Valid provider options for this role.
  final List<String> options;

  factory AiSelection.fromJson(Map<String, dynamic> json) {
    final effective = json['effective'] as Map<String, dynamic>?;
    return AiSelection(
      provider: (json['provider'] as String?) ?? '',
      model: (json['model'] as String?) ?? '',
      source: (json['source'] as String?) ?? 'env',
      effectiveProvider: effective?['provider'] as String?,
      effectiveModel: effective?['model'] as String?,
      options: [for (final o in (json['options'] as List? ?? const [])) '$o'],
    );
  }
}

/// Full AI-config view for the admin panel.
class AiProvidersStatus {
  const AiProvidersStatus({
    required this.keys,
    required this.embed,
    required this.rank,
    required this.availability,
  });

  /// Keyed by provider: anthropic / gemini / openai.
  final Map<String, AiKeyStatus> keys;
  final AiSelection embed;
  final AiSelection rank;

  /// Per-provider "usable right now", including `chatgpt` (sign-in based).
  final Map<String, bool> availability;

  factory AiProvidersStatus.fromJson(Map<String, dynamic> json) {
    final rawKeys = (json['keys'] as Map<String, dynamic>?) ?? const {};
    final rawAvail =
        (json['availability'] as Map<String, dynamic>?) ?? const {};
    return AiProvidersStatus(
      keys: {
        for (final e in rawKeys.entries)
          e.key: AiKeyStatus.fromJson(e.value as Map<String, dynamic>),
      },
      embed: AiSelection.fromJson(
        (json['embed'] as Map<String, dynamic>?) ?? const {},
      ),
      rank: AiSelection.fromJson(
        (json['rank'] as Map<String, dynamic>?) ?? const {},
      ),
      availability: {for (final e in rawAvail.entries) e.key: e.value == true},
    );
  }
}

/// Status of the ChatGPT (Codex OAuth) sign-in.
class ChatgptLoginStatus {
  const ChatgptLoginStatus({
    required this.connected,
    required this.needsReauth,
    required this.pending,
    required this.userCode,
    required this.verificationUrl,
  });

  final bool connected;
  final bool needsReauth;
  final bool pending;

  /// Device code to enter (only while a sign-in is pending).
  final String? userCode;
  final String? verificationUrl;

  factory ChatgptLoginStatus.fromJson(Map<String, dynamic> json) =>
      ChatgptLoginStatus(
        connected: json['connected'] == true,
        needsReauth: json['needs_reauth'] == true,
        pending: json['pending'] == true,
        userCode: json['user_code'] as String?,
        verificationUrl: json['verification_url'] as String?,
      );
}

/// One poll of the device sign-in.
class ChatgptPollResult {
  const ChatgptPollResult({
    required this.status,
    required this.detail,
    required this.userCode,
    required this.verificationUrl,
  });

  /// idle | pending | connected | expired | error
  final String status;
  final String? detail;
  final String? userCode;
  final String? verificationUrl;

  factory ChatgptPollResult.fromJson(Map<String, dynamic> json) =>
      ChatgptPollResult(
        status: (json['status'] as String?) ?? 'idle',
        detail: json['detail'] as String?,
        userCode: json['user_code'] as String?,
        verificationUrl: json['verification_url'] as String?,
      );
}
