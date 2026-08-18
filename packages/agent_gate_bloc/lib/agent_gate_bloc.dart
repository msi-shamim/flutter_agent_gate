/// Bloc / Cubit integration for `agent_gate`.
///
/// Philosophy: in Bloc architectures the *decision* is state and the
/// *navigation* is a side-effect performed by the widget layer in a listener.
/// This package therefore gives you:
///
/// * [GateState] — a sealed state family: `GateIdle`, `GateDeciding`,
///   `GateDecided`. Fully `Equatable`, easy to `BlocBuilder` on.
/// * [GateCubit] — `decide(gate)` → emits `GateDeciding` then `GateDecided`.
///   Never throws (fallback is still a `GateDecided`).
/// * [GateBloc] — the event-driven twin (`GateDecideRequested`, `GateReset`)
///   for teams that standardise on Blocs over Cubits.
/// * [GateBlocListener] — a `BlocListener` that reacts to `GateDecided` by
///   navigating through the configured `AgentGate.adapter` (or a custom
///   callback), and optionally shows the loading UI while `GateDeciding`.
///
/// Everything routes through `AgentGate.instance.decide`, so audit,
/// fallbacks, allow-lists and consent behave exactly like the core.
library;

export 'src/gate_bloc.dart';
export 'src/gate_bloc_listener.dart';
export 'src/gate_cubit.dart';
export 'src/gate_state.dart';
