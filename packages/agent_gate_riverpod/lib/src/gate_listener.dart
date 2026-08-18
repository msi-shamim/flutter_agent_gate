import 'package:agent_gate/agent_gate.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gate_notifier.dart';
import 'gate_outcome.dart';
import 'providers.dart';

/// Called when a new outcome lands.
typedef GateOutcomeCallback = void Function(
  BuildContext context,
  WidgetRef ref,
  GateOutcome outcome,
);

/// Widget-layer side-effect handler for [GateNotifier].
///
/// Listens to [provider] (default: [gateNotifierProvider]); on every *new*
/// [GateOutcome] it navigates via `AgentGate.instance.adapter` — or calls
/// [onDecided] instead — and layers the loading UI over [child] while a
/// decision is in flight. Plain widget composition, no overlays, so it works
/// inside nested navigators and tests.
///
/// ```dart
/// GateListener(
///   onNavigated: (ctx, ref, o) => ref.read(gateNotifierProvider.notifier).reset(),
///   child: CartView(),
/// )
/// // …
/// ref.read(gateNotifierProvider.notifier).decide(checkoutGate);
/// ```
class GateListener extends ConsumerWidget {
  /// Creates the listener.
  const GateListener({
    super.key,
    required this.child,
    this.provider,
    this.onDecided,
    this.onNavigated,
    this.showLoading = true,
    this.navigateOnFallback = true,
  });

  /// The subtree (usually the page A UI).
  final Widget child;

  /// Which notifier to listen to. Defaults to [gateNotifierProvider].
  final AsyncNotifierProvider<GateNotifier, GateOutcome?>? provider;

  /// Custom navigation; if null the global adapter is used.
  final GateOutcomeCallback? onDecided;

  /// Called after navigation was triggered — typical place to `reset()`.
  final GateOutcomeCallback? onNavigated;

  /// Overlay the loading UI while deciding.
  final bool showLoading;

  /// If false, fallback outcomes are not navigated automatically (they still
  /// reach [onDecided] when provided).
  final bool navigateOnFallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = provider ?? gateNotifierProvider;

    ref.listen<AsyncValue<GateOutcome?>>(p, (prev, next) {
      // Riverpod keeps the previous data inside AsyncLoading (`.value` is
      // still set while loading). So "a decision just landed" means: next is
      // data (not loading) AND either prev was loading or prev held a
      // different outcome. This also correctly re-fires when the user goes
      // back to page A and gets the *same* answer again (prev was loading).
      if (next.isLoading) return;
      final o = next.value;
      if (o == null) return;
      final landed = prev == null || prev.isLoading || prev.value != o;
      if (!landed) return;
      if (onDecided != null) {
        onDecided!(context, ref, o);
      } else if (navigateOnFallback || !o.isFallback) {
        // Not awaited on purpose — push futures complete on pop.
        AgentGate.instance.adapter.navigate(context, o.candidate, o.decision);
      }
      onNavigated?.call(context, ref, o);
    });

    final isLoading = ref.watch(p.select((s) => s.isLoading));
    if (!showLoading || !isLoading) return child;
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        child,
        Positioned.fill(
          child: AbsorbPointer(
            child: AgentGate.instance.loadingBuilder?.call(context, null) ??
                const AgentLoadingView(),
          ),
        ),
      ],
    );
  }
}
