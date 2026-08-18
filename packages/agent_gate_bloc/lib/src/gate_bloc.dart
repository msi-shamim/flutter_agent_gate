import 'package:agent_gate/agent_gate.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'gate_state.dart';

/// Events for [GateBloc].
sealed class GateEvent extends Equatable {
  const GateEvent();
  @override
  List<Object?> get props => const <Object?>[];
}

/// Ask the bloc to decide [gate].
final class GateDecideRequested extends GateEvent {
  /// Creates the event.
  const GateDecideRequested(this.gate, {this.extra = const <String, Object?>{}});

  /// The gate.
  final Gate gate;

  /// Extra decider context.
  final Map<String, Object?> extra;

  @override
  List<Object?> get props => <Object?>[gate.id, extra];
}

/// Return to [GateIdle].
final class GateReset extends GateEvent {
  /// Creates the event.
  const GateReset();
}

/// Event-driven twin of [GateCubit], for codebases that standardise on Blocs.
///
/// Event ordering: Bloc's *default* transformer is `concurrent`, which would
/// let a `GateReset` overtake an in-flight decision. We therefore register
/// **all** events on one sequential handler so they are processed strictly
/// in arrival order — a double-tapped "Continue" yields two decisions and
/// the second stays on screen; a `GateReset` sent after a decide always
/// lands after it. Pass [transformer] (e.g. `restartable()` from
/// `bloc_concurrency`) to change that policy.
class GateBloc extends Bloc<GateEvent, GateState> {
  /// Creates the bloc in [GateIdle].
  GateBloc({
    AgentGate? agentGate,
    EventTransformer<GateEvent>? transformer,
  })  : _gate = agentGate ?? AgentGate.instance,
        super(const GateIdle()) {
    on<GateEvent>(
      (e, emit) => switch (e) {
        GateDecideRequested() => _onDecide(e, emit),
        GateReset() => Future<void>.sync(() => emit(const GateIdle())),
      },
      transformer: transformer ?? _sequential,
    );
  }

  /// Sequential transformer without pulling in `bloc_concurrency`.
  static Stream<GateEvent> _sequential(
    Stream<GateEvent> events,
    EventMapper<GateEvent> mapper,
  ) =>
      events.asyncExpand(mapper);

  final AgentGate _gate;

  Future<void> _onDecide(
    GateDecideRequested e,
    Emitter<GateState> emit,
  ) async {
    emit(GateDeciding(e.gate, extra: e.extra));
    final decision = await _gate.decide(e.gate, extra: e.extra);
    final candidate =
        e.gate.candidate(decision.candidateId) ?? e.gate.fallbackCandidate;
    emit(GateDecided(gate: e.gate, decision: decision, candidate: candidate));
  }
}
