import 'package:flutter/widgets.dart';

import '../core/gate_candidate.dart';
import '../core/gate_decision.dart';

/// Signature the adapters use to perform navigation.
typedef GateNavigate = Future<Object?> Function(
  BuildContext? context,
  GateCandidate candidate,
  GateDecision decision,
);

/// Adapters translate a chosen [GateCandidate] into an actual navigation in
/// whatever routing / state-management stack the app uses.
///
/// AgentGate ships [NavigatorAdapter] (plain Flutter), [RouteNameAdapter]
/// (any named-route system: GoRouter, GetX, auto_route, Beamer…) and
/// [CallbackAdapter] (do it yourself — dispatch a Bloc event, set a
/// Riverpod provider, call `Get.toNamed`, …).
abstract interface class NavigationAdapter {
  /// Navigate to [candidate]. [context] may be null for context-free routers.
  Future<Object?> navigate(
    BuildContext? context,
    GateCandidate candidate,
    GateDecision decision,
  );
}

/// Uses `Navigator.of(context).push` with `candidate.builder`.
class NavigatorAdapter implements NavigationAdapter {
  /// Creates the adapter.
  const NavigatorAdapter({this.replace = false, this.rootNavigator = false});

  /// Use `pushReplacement` instead of `push`.
  final bool replace;

  /// Use the root navigator.
  final bool rootNavigator;

  @override
  Future<Object?> navigate(
    BuildContext? context,
    GateCandidate candidate,
    GateDecision decision,
  ) {
    if (context == null) {
      throw StateError('NavigatorAdapter requires a BuildContext');
    }
    final builder = candidate.builder;
    if (builder == null) {
      throw StateError('Candidate ${candidate.id} has no builder');
    }
    final nav = Navigator.of(context, rootNavigator: rootNavigator);
    final route = PageRouteBuilder<Object>(
      settings: RouteSettings(name: candidate.route ?? candidate.id),
      pageBuilder: (ctx, _, _) => builder(ctx),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 180),
    );
    return replace
        ? nav.pushReplacement<Object, Object>(route)
        : nav.push<Object>(route);
  }
}

/// Calls a developer function with the candidate's `route` string. Works for
/// GoRouter (`context.go(route)`), GetX (`Get.toNamed(route)`), auto_route,
/// Beamer, and any other name/path based router.
class RouteNameAdapter implements NavigationAdapter {
  /// Creates the adapter.
  const RouteNameAdapter(this.go);

  /// Called with the route string.
  final Future<Object?> Function(
    BuildContext? context,
    String route,
    GateCandidate candidate,
  )
  go;

  @override
  Future<Object?> navigate(
    BuildContext? context,
    GateCandidate candidate,
    GateDecision decision,
  ) {
    final route = candidate.route;
    if (route == null) {
      throw StateError('Candidate ${candidate.id} has no route');
    }
    return go(context, route, candidate);
  }
}

/// Fully custom — you receive the candidate and decision and do whatever
/// your architecture wants (Bloc event, Riverpod state, GetX controller…).
class CallbackAdapter implements NavigationAdapter {
  /// Creates the adapter.
  const CallbackAdapter(this.onNavigate);

  /// Your navigation function.
  final GateNavigate onNavigate;

  @override
  Future<Object?> navigate(
    BuildContext? context,
    GateCandidate candidate,
    GateDecision decision,
  ) => onNavigate(context, candidate, decision);
}
