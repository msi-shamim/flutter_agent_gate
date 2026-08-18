/// Riverpod (3.x) integration for `agent_gate`.
///
/// Riverpod has no router of its own, so this package is intentionally
/// small — it maps AgentGate onto Riverpod idioms:
///
/// * [gateDecisionProvider] — `FutureProvider.family<GateDecision, Gate>`:
///   `ref.watch(gateDecisionProvider(checkoutGate))` gives you an
///   `AsyncValue<GateDecision>`; render loading / data as you like.
/// * [GateNotifier] / [gateNotifierProvider] — an `AsyncNotifier` with
///   `decide`, `navigate` and `reset`, whose state is
///   `AsyncValue<GateOutcome?>` (`null` = idle, loading = deciding, data =
///   decided). Use it when the decision should be triggered by user action
///   rather than by a widget being built.
/// * [GateListener] — a `ConsumerWidget` that reacts to a new outcome by
///   navigating through the configured `AgentGate.adapter` (or a callback),
///   layering the loading UI while a decision is in flight.
///
/// All decision logic stays in `AgentGate.instance` so audit, fallbacks,
/// allow-lists and consent behave exactly like the core.
library;

export 'src/gate_listener.dart';
export 'src/gate_notifier.dart';
export 'src/gate_outcome.dart';
export 'src/providers.dart';
