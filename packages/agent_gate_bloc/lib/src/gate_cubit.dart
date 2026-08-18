import 'package:agent_gate/agent_gate.dart';
import 'package:bloc/bloc.dart';

import 'gate_state.dart';

/// Cubit that runs gate decisions and exposes them as [GateState].
///
/// ```dart
/// BlocProvider(create: (_) => GateCubit(), child: ...)
/// context.read<GateCubit>().decide(checkoutGate, extra: {'total': 211});
/// ```
///
/// Design notes for contributors:
/// * We do **not** navigate here. A Cubit has no `BuildContext` and should not
///   own UI side-effects; [GateBlocListener] (widget layer) does that.
/// * `decide` swallows nothing and throws nothing: `AgentGate.decide` already
///   guarantees a decision (fallback on failure), so the only terminal state
///   is `GateDecided`.
/// * Concurrent calls: the last one wins. A `_seq` guard prevents a slow
///   earlier decision from overwriting a newer one.
class GateCubit extends Cubit<GateState> {
  /// Creates the cubit in [GateIdle].
  GateCubit({AgentGate? agentGate})
    : _gate = agentGate ?? AgentGate.instance,
      super(const GateIdle());

  final AgentGate _gate;
  int _seq = 0;

  /// Runs a decision for [gate] and emits the resulting states.
  /// Returns the final [GateDecided] for convenience (awaitable).
  Future<GateDecided> decide(
    Gate gate, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    final my = ++_seq;
    emit(GateDeciding(gate, extra: extra));
    final decision = await _gate.decide(gate, extra: extra);
    final candidate =
        gate.candidate(decision.candidateId) ?? gate.fallbackCandidate;
    final decided = GateDecided(
      gate: gate,
      decision: decision,
      candidate: candidate,
    );
    // Only emit if no newer decide() started meanwhile and we're still open.
    if (my == _seq && !isClosed) emit(decided);
    return decided;
  }

  /// Back to [GateIdle] (e.g. after the listener navigated).
  void reset() {
    _seq++;
    emit(const GateIdle());
  }
}
