# agent_gate_go_router

[GoRouter](https://pub.dev/packages/go_router) integration for
[`agent_gate`](https://pub.dev/packages/agent_gate) — the AI-agnostic
behavioural routing middleware for Flutter.

The core package already works with GoRouter through `RouteNameAdapter`; this
package removes the boilerplate and adds the two things only a GoRouter-aware
package can offer: a **redirect middleware** and a typed **`extra`** payload.

```yaml
dependencies:
  agent_gate: ^0.1.0
  agent_gate_go_router: ^0.1.0
  go_router: ^17.0.0
```

## Three integration styles

### 1. Imperative — `GoRouterAdapter`

```dart
final router = GoRouter(routes: [...]);

AgentGate.configure(
  decider: HttpDecider(endpoint: Uri.parse('https://api.example.com/gate')),
  adapter: GoRouterAdapter(router: router),          // or const GoRouterAdapter() to use GoRouter.of(context)
);

// Anywhere — no BuildContext needed when the router was passed explicitly:
await AgentGate.instance.navigate(checkoutGate);
```

Options: `mode` (`go` · `push` · `pushReplacement` · `replace`),
`useNamedRoutes`, `extraBuilder`. Candidates need a `route` (path or name).

The destination receives a `GateExtra` so it can show *why* it was chosen:

```dart
GoRoute(path: '/checkout/assisted', builder: (context, state) {
  final why = state.gateDecision?.reason;      // extension on GoRouterState
  return AssistedCheckoutPage(banner: why);
});
```

### 2. Declarative page — `GateRoute.page`

The route *is* the gate; the AI-chosen candidate renders inline (candidates
need `builder`s):

```dart
GateRoute.page(
  path: '/checkout',
  gate: checkoutGate,
  contextFromState: (s) => {'coupon': s.uri.queryParameters['coupon']},
),
```

### 3. Redirect middleware — `GateRoute.redirect` / `gateRedirect`

Deep links resolve intelligently; nothing is built at the gate path:

```dart
GateRoute.redirect(path: '/checkout', gate: checkoutGate),
GoRoute(path: '/checkout/express',  builder: ...),
GoRoute(path: '/checkout/standard', builder: ...),
GoRoute(path: '/checkout/assisted', builder: ...),
```

or attach to any existing route: `GoRoute(path: '/checkout', redirect: gateRedirect(checkoutGate), ...)`.

> GoRouter shows nothing while a redirect is pending, so pair this with a
> short `GateConfig.timeout` or `AgentGate.prefetch(gate)` earlier in the flow.
> The redirect is loop-safe and always resolves (fallback on any failure).

## Tracking pages with GoRouter

Add the core observer so `enterPage` / `exitPage` happen automatically:

```dart
GoRouter(observers: [GateNavigatorObserver()], routes: [...])
```

## License

MIT © MSI Shamim / Increments Inc.
