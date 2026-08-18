import 'package:agent_gate/agent_gate.dart';
import 'package:flutter/foundation.dart';

/// A completed decision, bundled with the gate and the resolved candidate.
///
/// Riverpod's `AsyncValue` already models idle/loading/error, so we only need
/// a value type for the *decided* case. Equality is by gate id + candidate id
/// + source so `ref.listen` fires once per distinct outcome.
@immutable
class GateOutcome {
  /// Creates an outcome.
  const GateOutcome({
    required this.gate,
    required this.decision,
    required this.candidate,
  });

  /// The gate that was decided.
  final Gate gate;

  /// The validated decision.
  final GateDecision decision;

  /// The chosen candidate.
  final GateCandidate candidate;

  /// True when the AI/rules did not decide and the fallback was used.
  bool get isFallback => decision.source == DecisionSource.fallback;

  @override
  bool operator ==(Object other) =>
      other is GateOutcome &&
      other.gate.id == gate.id &&
      other.decision.candidateId == decision.candidateId &&
      other.decision.source == decision.source;

  @override
  int get hashCode =>
      Object.hash(gate.id, decision.candidateId, decision.source);

  @override
  String toString() =>
      'GateOutcome(${gate.id} → ${candidate.id}, '
      '${decision.source.name})';
}
