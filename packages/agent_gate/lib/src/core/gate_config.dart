import 'package:meta/meta.dart';

import 'gate_profile.dart';

/// Tunables for a single gate or for the global default.
@immutable
class GateConfig {
  /// Creates a config. All fields have safe defaults.
  const GateConfig({
    this.profile = GateProfile.general,
    this.timeout = const Duration(seconds: 4),
    this.maxRetries = 1,
    this.retryDelay = const Duration(milliseconds: 300),
    this.minConfidence = 0.0,
    this.cacheTtl,
    this.allowedCandidateIds,
    this.redactKeys = const <String>{},
    this.requireConsent = true,
    this.showLoadingUi = true,
  });

  /// Sensible defaults for fraud / risk routing.
  const GateConfig.risk()
    : this(
        profile: GateProfile.risk,
        timeout: const Duration(seconds: 2),
        maxRetries: 0,
        minConfidence: 0.6,
      );

  /// Sensible defaults for recommendation routing.
  const GateConfig.recommendation()
    : this(
        profile: GateProfile.recommendation,
        timeout: const Duration(seconds: 6),
        cacheTtl: const Duration(minutes: 10),
      );

  /// Profile this gate runs under.
  final GateProfile profile;

  /// Hard ceiling for the whole decision (all retries included). When it
  /// elapses the fallback candidate is used. A navigation must never hang.
  final Duration timeout;

  /// Retries on transient decider errors (network, 5xx).
  final int maxRetries;

  /// Delay between retries.
  final Duration retryDelay;

  /// Decisions below this confidence are treated as "undecided" and go to
  /// the fallback. `0.0` disables the check.
  final double minConfidence;

  /// If set, identical requests (same gate + same context hash) reuse the
  /// previous decision for this long.
  final Duration? cacheTtl;

  /// Optional allow-list. Even if the AI returns another id, the gate will
  /// refuse it and fall back. Use this to keep AI inside the lines your
  /// compliance team drew.
  final Set<String>? allowedCandidateIds;

  /// Context keys removed before the payload leaves the device
  /// (e.g. `email`, `card_number`). Case-insensitive, matched at any depth.
  final Set<String> redactKeys;

  /// If `true` (default), behaviour signals are only attached when the
  /// consent controller says the user has consented.
  final bool requireConsent;

  /// Whether to show the built-in "agentic loading" UI while deciding.
  final bool showLoadingUi;

  /// Returns a copy with the given overrides.
  GateConfig copyWith({
    GateProfile? profile,
    Duration? timeout,
    int? maxRetries,
    Duration? retryDelay,
    double? minConfidence,
    Duration? cacheTtl,
    Set<String>? allowedCandidateIds,
    Set<String>? redactKeys,
    bool? requireConsent,
    bool? showLoadingUi,
  }) {
    return GateConfig(
      profile: profile ?? this.profile,
      timeout: timeout ?? this.timeout,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      minConfidence: minConfidence ?? this.minConfidence,
      cacheTtl: cacheTtl ?? this.cacheTtl,
      allowedCandidateIds: allowedCandidateIds ?? this.allowedCandidateIds,
      redactKeys: redactKeys ?? this.redactKeys,
      requireConsent: requireConsent ?? this.requireConsent,
      showLoadingUi: showLoadingUi ?? this.showLoadingUi,
    );
  }
}
