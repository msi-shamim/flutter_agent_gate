import 'package:meta/meta.dart';

/// Where a decision came from.
enum DecisionSource {
  /// The configured decider (your backend / AI) answered.
  agent,

  /// A cached previous answer was reused.
  cache,

  /// A rule matched before the agent was consulted.
  rule,

  /// The agent failed / timed out / returned junk; fallback used.
  fallback,
}

/// The outcome of a gate: which candidate to route to and why.
@immutable
class GateDecision {
  /// Creates a decision.
  const GateDecision({
    required this.candidateId,
    required this.source,
    this.confidence = 1.0,
    this.reason,
    this.model,
    this.latency,
    this.raw,
  });

  /// Convenience for a fallback decision.
  const GateDecision.fallback(String candidateId, {String? reason})
    : this(
        candidateId: candidateId,
        source: DecisionSource.fallback,
        confidence: 0,
        reason: reason,
      );

  /// Parses the canonical decider JSON `{candidate_id, confidence, reason}`.
  ///
  /// Also accepts `candidateId` / `id` for the id key so that most backends
  /// work without a shim.
  factory GateDecision.fromJson(
    Map<String, Object?> json, {
    DecisionSource source = DecisionSource.agent,
    String? model,
    Duration? latency,
  }) {
    final Object? id =
        json['candidate_id'] ?? json['candidateId'] ?? json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('decision missing "candidate_id"');
    }
    final Object? conf = json['confidence'];
    return GateDecision(
      candidateId: id,
      source: source,
      confidence: conf is num ? conf.toDouble().clamp(0.0, 1.0) : 1.0,
      reason: json['reason'] as String?,
      model: model ?? json['model'] as String?,
      latency: latency,
      raw: json,
    );
  }

  /// Chosen candidate id.
  final String candidateId;

  /// Where the decision came from.
  final DecisionSource source;

  /// 0..1 confidence supplied by the decider.
  final double confidence;

  /// Human-readable justification (surface it in the loading UI / audit log).
  final String? reason;

  /// Model / engine identifier for audit purposes.
  final String? model;

  /// How long the decision took end-to-end.
  final Duration? latency;

  /// Untouched decider payload.
  final Map<String, Object?>? raw;

  /// Serializes for audit logs.
  Map<String, Object?> toJson() => <String, Object?>{
    'candidate_id': candidateId,
    'source': source.name,
    'confidence': confidence,
    if (reason != null) 'reason': reason,
    if (model != null) 'model': model,
    if (latency != null) 'latency_ms': latency!.inMilliseconds,
  };

  /// Copy with overrides.
  GateDecision copyWith({
    String? candidateId,
    DecisionSource? source,
    double? confidence,
    String? reason,
    String? model,
    Duration? latency,
  }) => GateDecision(
    candidateId: candidateId ?? this.candidateId,
    source: source ?? this.source,
    confidence: confidence ?? this.confidence,
    reason: reason ?? this.reason,
    model: model ?? this.model,
    latency: latency ?? this.latency,
    raw: raw,
  );

  @override
  String toString() =>
      'GateDecision($candidateId, ${source.name}, ${confidence.toStringAsFixed(2)})';
}
