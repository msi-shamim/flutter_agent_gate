import 'package:agent_gate/agent_gate.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'gate_extra.dart';

/// How [GoRouterAdapter] should move to the chosen route.
enum GoRouterNavigationMode {
  /// `context.go(route)` — replaces the stack per GoRouter semantics.
  /// The usual choice for "the user is moving on".
  go,

  /// `context.push(route)` — stacks on top; the user can come back to page A.
  push,

  /// `context.pushReplacement(route)` — swaps page A for the destination so
  /// "back" skips the gate origin. Good for wizard-style flows.
  pushReplacement,

  /// `context.replace(route)` — like pushReplacement but keeps the same
  /// page key (no transition animation).
  replace,
}

/// Signature to customise the `extra` passed to GoRouter.
///
/// Receives the default [GateExtra]; return whatever your destination page
/// expects (e.g. merge with an app payload). Return `null` to pass nothing.
typedef GateExtraBuilder = Object? Function(GateExtra extra);

/// [NavigationAdapter] that drives a [GoRouter].
///
/// Resolution order for the router instance:
/// 1. [router] if supplied (recommended when you keep a global router — then
///    `AgentGate.navigate` works without a `BuildContext`).
/// 2. `GoRouter.of(context)` from the context passed to `navigate`.
///
/// The candidate's `route` string is used verbatim as a location path, or as
/// a route *name* when [useNamedRoutes] is true.
class GoRouterAdapter implements NavigationAdapter {
  /// Creates the adapter.
  const GoRouterAdapter({
    this.router,
    this.mode = GoRouterNavigationMode.go,
    this.useNamedRoutes = false,
    this.extraBuilder,
  });

  /// Explicit router; falls back to `GoRouter.of(context)`.
  final GoRouter? router;

  /// go / push / pushReplacement / replace.
  final GoRouterNavigationMode mode;

  /// When true, `candidate.route` is treated as a route *name*
  /// (`goNamed`/`pushNamed`) instead of a location path.
  final bool useNamedRoutes;

  /// Customises `extra`. Default: a [GateExtra].
  final GateExtraBuilder? extraBuilder;

  @override
  Future<Object?> navigate(
    BuildContext? context,
    GateCandidate candidate,
    GateDecision decision,
  ) {
    final route = candidate.route;
    if (route == null) {
      throw StateError(
        'GoRouterAdapter: candidate "${candidate.id}" has no `route`. '
        'Give every candidate a GoRouter location (e.g. "/checkout/express").',
      );
    }
    final r = router ?? (context != null ? GoRouter.of(context) : null);
    if (r == null) {
      throw StateError(
        'GoRouterAdapter: no router. Pass `router:` to the adapter or a '
        'BuildContext to AgentGate.navigate.',
      );
    }
    final defaultExtra = GateExtra(decision: decision, candidate: candidate);
    final extra =
        extraBuilder == null ? defaultExtra : extraBuilder!(defaultExtra);

    // NOTE: push* return a future that completes on pop; go/replace return
    // void. We normalise to Future<Object?> and AgentGate.navigate never
    // awaits it, so callers are not blocked for the lifetime of the
    // destination page.
    switch (mode) {
      case GoRouterNavigationMode.go:
        if (useNamedRoutes) {
          r.goNamed(route, extra: extra);
        } else {
          r.go(route, extra: extra);
        }
        return Future<Object?>.value(null);
      case GoRouterNavigationMode.push:
        return useNamedRoutes
            ? r.pushNamed<Object?>(route, extra: extra)
            : r.push<Object?>(route, extra: extra);
      case GoRouterNavigationMode.pushReplacement:
        return useNamedRoutes
            ? r.pushReplacementNamed<Object?>(route, extra: extra)
            : r.pushReplacement<Object?>(route, extra: extra);
      case GoRouterNavigationMode.replace:
        return useNamedRoutes
            ? r.replaceNamed<Object?>(route, extra: extra)
            : r.replace<Object?>(route, extra: extra);
    }
  }
}
