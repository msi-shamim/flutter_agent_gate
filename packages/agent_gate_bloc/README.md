# agent_gate_bloc

[Bloc](https://pub.dev/packages/flutter_bloc) / Cubit integration for
[`agent_gate`](https://pub.dev/packages/agent_gate) — the AI-agnostic
behavioural routing middleware for Flutter.

**Philosophy:** in Bloc apps the *decision* is state and *navigation* is a
side-effect done by the widget layer. So:

- `GateCubit` / `GateBloc` run the decision and emit `GateIdle → GateDeciding → GateDecided`.
- `GateBlocListener` reacts to `GateDecided` by navigating through the globally
  configured `AgentGate.adapter` (Navigator, GoRouter, GetX — whichever you set),
  and layers the loading UI over your page while `GateDeciding`.

```yaml
dependencies:
  agent_gate: ^0.1.0
  agent_gate_bloc: ^0.1.0
  flutter_bloc: ^9.0.0
```

## Cubit

```dart
BlocProvider(
  create: (_) => GateCubit(),
  child: GateBlocListener<GateCubit>(
    onNavigated: (ctx, s) => ctx.read<GateCubit>().reset(),
    child: CartView(),
  ),
);

// somewhere in CartView:
context.read<GateCubit>().decide(checkoutGate, extra: {'total': cart.total});
```

`GateDecided` carries `gate`, `decision` (`candidateId`, `confidence`,
`reason`, `source`) and `candidate`; `isFallback` tells you the AI/rules did
not decide.

## Bloc

```dart
context.read<GateBloc>().add(GateDecideRequested(checkoutGate, extra: {...}));
context.read<GateBloc>().add(const GateReset());
```

Events are processed **sequentially** by default (Bloc's own default is
concurrent, which lets a reset overtake a decision). Pass `transformer:` to
change the policy.

## Custom navigation / error handling

```dart
GateBlocListener<GateCubit>(
  onDecided: (ctx, s) => s.isFallback
      ? showRetrySheet(ctx, s.decision.reason)
      : ctx.go(s.candidate.route!),
  child: CartView(),
)
```

or `navigateOnFallback: false` to keep the default navigation only for real
decisions.

## Building your own UI on the state

```dart
BlocBuilder<GateCubit, GateState>(builder: (_, s) => switch (s) {
  GateIdle() => const ContinueButton(),
  GateDeciding() => const AgentLoadingView(),
  GateDecided() => Text('Going to ${s.candidate.label}: ${s.decision.reason}'),
});
```

## License

MIT © MSI Shamim / Increments Inc.
