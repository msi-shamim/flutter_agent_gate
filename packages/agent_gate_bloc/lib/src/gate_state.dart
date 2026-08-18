import 'package:agent_gate/agent_gate.dart';
import 'package:equatable/equatable.dart';

/// State family for [GateCubit] / [GateBloc].
///
/// Sealed so `switch` statements are exhaustive; `Equatable` so Bloc's
/// equality-based de-duplication works and tests can compare states.
sealed class GateState extends Equatable {
  const GateState();

  @override
  List<Object?> get props => const <Object?>[];
}

/// No decision in progress or made yet.
final class GateIdle extends GateState {
  /// Creates the state.
  const GateIdle();
}

/// A decision is in flight for [gate].
final class GateDeciding extends GateState {
  /// Creates the state.
  const GateDeciding(this.gate, {this.extra = const <String, Object?>{}});

  /// The gate being decided.
  final Gate gate;

  /// Extra app context that was passed.
  final Map<String, Object?> extra;

  @override
  List<Object?> get props => <Object?>[gate.id, extra];
}

/// A decision was made. Always reached — a fallback is still a decision
/// (`decision.source == DecisionSource.fallback`).
final class GateDecided extends GateState {
  /// Creates the state.
  const GateDecided({
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
  List<Object?> get props => <Object?>[
    gate.id,
    decision.candidateId,
    decision.source,
    candidate.id,
  ];
}
