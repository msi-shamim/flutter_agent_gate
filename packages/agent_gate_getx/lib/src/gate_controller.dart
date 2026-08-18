import 'package:agent_gate/agent_gate.dart';
import 'package:get/get.dart';

/// A `GetxController` wrapper around `AgentGate` for teams that keep
/// navigation decisions in controllers and bind UI with `Obx`.
///
/// ```dart
/// final c = Get.put(GateController());
/// ...
/// Obx(() => c.isDeciding.value ? const AgentLoadingView() : const SizedBox());
/// ...
/// await c.navigate(checkoutGate, extra: {'total': cart.total});
/// ```
///
/// It does not add logic of its own — every call goes through
/// `AgentGate.instance`, so behaviour, audit and fallbacks are identical to
/// the core. It only mirrors state reactively.
class GateController extends GetxController {
  /// True while a decision is in flight.
  final RxBool isDeciding = false.obs;

  /// The last decision made through this controller (null before the first).
  final Rxn<GateDecision> lastDecision = Rxn<GateDecision>();

  /// The candidate chosen by the last decision.
  final Rxn<GateCandidate> lastCandidate = Rxn<GateCandidate>();

  /// Decide only (no navigation). Useful to drive `Obx` UI yourself.
  Future<GateDecision> decide(
    Gate gate, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    isDeciding.value = true;
    try {
      final d = await AgentGate.instance.decide(gate, extra: extra);
      lastDecision.value = d;
      lastCandidate.value = gate.candidate(d.candidateId);
      return d;
    } finally {
      isDeciding.value = false;
    }
  }

  /// Decide and navigate through the configured adapter (normally
  /// [GetxAdapter]). Context-free by design — GetX does not need one.
  Future<GateResult> navigate(
    Gate gate, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    isDeciding.value = true;
    try {
      final r = await AgentGate.instance.navigate(gate, extra: extra);
      lastDecision.value = r.decision;
      lastCandidate.value = r.candidate;
      return r;
    } finally {
      isDeciding.value = false;
    }
  }
}
