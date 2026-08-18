import 'package:agent_gate/agent_gate.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// What [GoRouterAdapter] passes as `extra` when it navigates.
///
/// Why a dedicated class instead of passing the raw [GateDecision]?
/// GoRouter's `extra` is untyped (`Object?`); wrapping lets a destination
/// page distinguish "I was reached through a gate" from any other `extra`
/// the app might use, and lets us carry the candidate alongside the decision
/// without a second lookup. If the app already uses `extra` for its own
/// payload, `GoRouterAdapter.extraBuilder` can merge them.
@immutable
class GateExtra {
  /// Creates the payload.
  const GateExtra({required this.decision, required this.candidate});

  /// The (validated) decision that produced this navigation.
  final GateDecision decision;

  /// The candidate that was chosen.
  final GateCandidate candidate;

  @override
  String toString() => 'GateExtra(${candidate.id}, ${decision.source.name})';
}

/// Convenience accessors on [GoRouterState].
extension GoRouterStateGate on GoRouterState {
  /// The [GateExtra] if this route was reached through AgentGate, else null.
  GateExtra? get gateExtra => extra is GateExtra ? extra! as GateExtra : null;

  /// Shortcut for `gateExtra?.decision`.
  GateDecision? get gateDecision => gateExtra?.decision;
}
