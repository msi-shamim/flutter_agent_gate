import 'package:agent_gate/agent_gate.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gate_outcome.dart';

/// `AsyncNotifier` that runs gate decisions on demand.
///
/// State: `AsyncValue<GateOutcome?>`
/// * `AsyncData(null)`     — idle (initial / after [reset])
/// * `AsyncLoading`        — a decision is in flight
/// * `AsyncData(outcome)`  — decided (a fallback is *still* data; see
///                           `GateOutcome.isFallback`)
///
/// It never enters `AsyncError` from a decision, because `AgentGate.decide`
/// guarantees a fallback. Contributors: keep it that way — the whole point
/// of AgentGate is that navigation never breaks on a model hiccup.
///
/// Concurrency: a sequence guard makes the *latest* call win, so a slow
/// earlier decision cannot overwrite a newer one.
class GateNotifier extends AsyncNotifier<GateOutcome?> {
  /// Creates the notifier. [agentGate] defaults to the global instance and is
  /// injectable for tests.
  GateNotifier({AgentGate? agentGate})
    : _gate = agentGate ?? AgentGate.instance;

  final AgentGate _gate;
  int _seq = 0;

  @override
  Future<GateOutcome?> build() async => null;

  /// Decide only. Returns the outcome (also emitted as state).
  Future<GateOutcome> decide(
    Gate gate, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    final my = ++_seq;
    state = const AsyncLoading<GateOutcome?>();
    final decision = await _gate.decide(gate, extra: extra);
    final outcome = GateOutcome(
      gate: gate,
      decision: decision,
      candidate: gate.candidate(decision.candidateId) ?? gate.fallbackCandidate,
    );
    if (my == _seq) state = AsyncData<GateOutcome?>(outcome);
    return outcome;
  }

  /// Decide **and** navigate through `AgentGate.adapter`.
  ///
  /// [context] is only needed by context-bound adapters (`NavigatorAdapter`,
  /// `GoRouterAdapter` without an explicit router). Prefer [GateListener] if
  /// you want navigation to be a widget-layer side effect instead.
  Future<GateOutcome> navigate(
    Gate gate, {
    BuildContext? context,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    final my = ++_seq;
    state = const AsyncLoading<GateOutcome?>();
    final r = await _gate.navigate(gate, context: context, extra: extra);
    final outcome = GateOutcome(
      gate: gate,
      decision: r.decision,
      candidate: r.candidate,
    );
    if (my == _seq) state = AsyncData<GateOutcome?>(outcome);
    return outcome;
  }

  /// Back to idle (e.g. after the listener navigated).
  void reset() {
    _seq++;
    state = const AsyncData<GateOutcome?>(null);
  }
}
