import 'package:agent_gate/agent_gate.dart';
import 'package:get/get.dart';

/// Derives decider context from the incoming `GetNavConfig`.
typedef GateNavContext = Map<String, Object?> Function(GetNavConfig route);

/// GetX **router** middleware (Navigator 2 / `GetMaterialApp.router`) that
/// resolves a gate route to the chosen candidate's route.
///
/// GetX offers two redirect hooks:
/// * `redirect(String?)` — synchronous, used by classic `Get.toNamed`
///   navigation. A decision needs a network round-trip, so it cannot be
///   answered here; we leave it untouched (returns null → no redirect).
/// * `redirectDelegate(GetNavConfig)` — asynchronous, used by
///   `GetMaterialApp.router` / `Get.rootDelegate`. That is what this
///   middleware implements.
///
/// If your app uses classic navigation, use [GetxAdapter] (imperative) or
/// [GateGetPage] (inline) instead — both work without Navigator 2.
///
/// ```dart
/// GetPage(
///   name: '/checkout',
///   page: () => const SizedBox.shrink(),           // never shown
///   middlewares: [GateMiddleware(checkoutGate)],
/// ),
/// ```
class GateMiddleware extends GetMiddleware {
  /// Creates the middleware. Lower [priority] runs first (GetX semantics).
  GateMiddleware(this.gate, {this.contextFromRoute, super.priority});

  /// The gate to resolve.
  final Gate gate;

  /// Optional context derived from the incoming route.
  final GateNavContext? contextFromRoute;

  @override
  Future<GetNavConfig?> redirectDelegate(GetNavConfig route) async {
    final extra = contextFromRoute?.call(route) ?? const <String, Object?>{};
    final decision = await AgentGate.instance.decide(gate, extra: extra);
    final chosen =
        gate.candidate(decision.candidateId) ?? gate.fallbackCandidate;
    final target = chosen.route ?? gate.fallbackCandidate.route;
    // Loop-safety: don't redirect to where we already are.
    if (target == null || target == route.uri.toString()) return route;
    return GetNavConfig.fromRoute(target) ?? route;
  }
}
