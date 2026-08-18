import 'package:agent_gate/agent_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gate_notifier.dart';
import 'gate_outcome.dart';

/// One-shot decision for a gate, as an `AsyncValue<GateDecision>`.
///
/// ```dart
/// ref.watch(gateDecisionProvider(checkoutGate)).when(
///   loading: () => const AgentLoadingView(),
///   error: (e, _) => Text('$e'),        // never happens for decisions, but AsyncValue requires it
///   data: (d) => checkoutGate.candidate(d.candidateId)!.builder!(context),
/// );
/// ```
///
/// Family key is the [Gate] *instance* (identity equality — declare gates as
/// top-level finals, as recommended in the core README). `autoDispose` so a
/// fresh decision is made each time the consuming widget is (re)built after
/// being disposed; use `ref.keepAlive()` in a wrapper provider if you want
/// to pin one.
///
/// To pass per-navigation `extra`, use [gateDecisionWithExtraProvider].
final gateDecisionProvider =
    FutureProvider.autoDispose.family<GateDecision, Gate>(
  (ref, gate) => AgentGate.instance.decide(gate),
);

/// Key for [gateDecisionWithExtraProvider]. Equality is by gate id + a
/// stable JSON-ish rendering of `extra`, so identical requests share a
/// provider instance.
class GateArgs {
  /// Creates the key.
  const GateArgs(this.gate, [this.extra = const <String, Object?>{}]);

  /// The gate.
  final Gate gate;

  /// Extra decider context.
  final Map<String, Object?> extra;

  @override
  bool operator ==(Object other) =>
      other is GateArgs &&
      other.gate.id == gate.id &&
      _key(other.extra) == _key(extra);

  @override
  int get hashCode => Object.hash(gate.id, _key(extra));

  static String _key(Map<String, Object?> m) {
    final entries = m.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => '${e.key}=${e.value}').join('&');
  }
}

/// Like [gateDecisionProvider] but with per-navigation `extra` context.
final gateDecisionWithExtraProvider =
    FutureProvider.autoDispose.family<GateDecision, GateArgs>(
  (ref, args) => AgentGate.instance.decide(args.gate, extra: args.extra),
);

/// The on-demand notifier. Keep-alive so the last outcome survives widget
/// rebuilds; call `reset()` after navigating if you want a clean slate.
final gateNotifierProvider =
    AsyncNotifierProvider<GateNotifier, GateOutcome?>(GateNotifier.new);
