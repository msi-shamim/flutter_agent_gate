import 'package:agent_gate/agent_gate.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Signature to derive per-navigation `extra` context (app data for the
/// decider) from the router state — query params, path params, `state.extra`.
typedef GateStateContext = Map<String, Object?> Function(GoRouterState state);

/// Declarative helpers that turn a [Gate] into GoRouter pieces.
///
/// Both helpers are thin on purpose: all decision logic stays in
/// `AgentGate.instance.decide`, so behaviour is identical whichever
/// integration style you pick and the core tests cover it.
abstract final class GateRoute {
  /// A `GoRoute` whose page *is* the gate: `GatePage` decides inline and
  /// renders the chosen candidate's `builder`. Requires candidates to have
  /// `builder`s (not just `route`s).
  ///
  /// ```dart
  /// GateRoute.page(path: '/checkout', gate: checkoutGate,
  ///   contextFromState: (s) => {'coupon': s.uri.queryParameters['coupon']}),
  /// ```
  static GoRoute page({
    required String path,
    required Gate gate,
    String? name,
    GateStateContext? contextFromState,
    Widget? loading,
    List<RouteBase> routes = const <RouteBase>[],
    GoRouterRedirect? redirect,
    GlobalKey<NavigatorState>? parentNavigatorKey,
  }) {
    return GoRoute(
      path: path,
      name: name,
      routes: routes,
      redirect: redirect,
      parentNavigatorKey: parentNavigatorKey,
      builder: (context, state) => GatePage(
        gate: gate,
        extra: contextFromState?.call(state) ?? const <String, Object?>{},
        loading: loading,
      ),
    );
  }

  /// A `GoRoute` that acts purely as a **redirect middleware**: navigating to
  /// [path] triggers a decision and GoRouter is redirected to the chosen
  /// candidate's `route`. Nothing is ever built at [path].
  ///
  /// Prefer this when your destinations are real routes elsewhere in the
  /// tree and you want deep-links (`/checkout`) to resolve intelligently.
  ///
  /// Trade-off: GoRouter shows no UI while a redirect future is pending, so
  /// the previous page stays on screen. Use a `GateConfig` with a short
  /// timeout, or `AgentGate.prefetch` earlier so the answer is cached.
  static GoRoute redirect({
    required String path,
    required Gate gate,
    String? name,
    GateStateContext? contextFromState,
  }) {
    return GoRoute(
      path: path,
      name: name,
      redirect: gateRedirect(gate, contextFromState: contextFromState),
      // GoRouter requires a builder or a redirect that always redirects.
      // We always redirect; this builder is unreachable but keeps the
      // assertion happy on older go_router versions.
      builder: (_, _) => const SizedBox.shrink(),
    );
  }
}

/// A [GoRouterRedirect] that resolves to the chosen candidate's route.
///
/// Guarantees:
/// * Always resolves — `AgentGate.decide` never throws (fallback on failure).
/// * If the chosen candidate has no `route`, falls back to the gate's
///   fallback candidate's route; if *that* is missing too, returns null so
///   GoRouter proceeds to the current location instead of crashing.
/// * Loop-safe: returns null when the target equals the current location.
GoRouterRedirect gateRedirect(Gate gate, {GateStateContext? contextFromState}) {
  return (BuildContext context, GoRouterState state) async {
    final extra = contextFromState?.call(state) ?? const <String, Object?>{};
    final decision = await AgentGate.instance.decide(gate, extra: extra);
    final chosen =
        gate.candidate(decision.candidateId) ?? gate.fallbackCandidate;
    final route = chosen.route ?? gate.fallbackCandidate.route;
    if (route == null || route == state.matchedLocation) return null;
    return route;
  };
}
