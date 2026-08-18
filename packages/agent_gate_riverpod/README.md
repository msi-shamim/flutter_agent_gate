# agent_gate_riverpod

[Riverpod 3](https://pub.dev/packages/flutter_riverpod) integration for
[`agent_gate`](https://pub.dev/packages/agent_gate) — the AI-agnostic
behavioural routing middleware for Flutter.

Riverpod has no router, so this package is deliberately small: it maps
AgentGate onto providers and a listener widget. Navigation itself goes through
whichever `AgentGate.adapter` you configured (Navigator, GoRouter, GetX…).

```yaml
dependencies:
  agent_gate: ^0.1.0
  agent_gate_riverpod: ^0.1.0
  flutter_riverpod: ^3.0.0
```

## Declarative — `gateDecisionProvider`

Decide when a widget builds and render the chosen candidate inline:

```dart
class CheckoutGateScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(gateDecisionProvider(checkoutGate)).when(
      loading: () => const AgentLoadingView(),
      error: (e, _) => Text('$e'),   // decisions never error (fallback), but AsyncValue needs it
      data: (d) => checkoutGate.candidate(d.candidateId)!.builder!(context),
    );
  }
}
```

Need per-navigation context? `ref.watch(gateDecisionWithExtraProvider(GateArgs(checkoutGate, {'coupon': code})))`.

## Imperative — `GateNotifier` + `GateListener`

Decision is state; navigation is a widget-layer side effect:

```dart
GateListener(
  onNavigated: (ctx, ref, o) => ref.read(gateNotifierProvider.notifier).reset(),
  child: CartView(),
)

// on "Checkout" tap:
ref.read(gateNotifierProvider.notifier).decide(checkoutGate, extra: {'total': cart.total});
```

State is `AsyncValue<GateOutcome?>`: `null` = idle, loading = deciding, data =
decided (`GateOutcome.isFallback` tells you the AI didn't decide). It never
enters the error state from a decision.

Options on `GateListener`: `onDecided` (custom navigation), `navigateOnFallback`,
`showLoading`, `provider` (your own `AsyncNotifierProvider<GateNotifier, …>`).

Or navigate directly: `ref.read(gateNotifierProvider.notifier).navigate(gate, context: context)`.

## License

MIT © MSI Shamim / Increments Inc.
