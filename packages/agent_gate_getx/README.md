# agent_gate_getx

[GetX](https://pub.dev/packages/get) integration for
[`agent_gate`](https://pub.dev/packages/agent_gate) — the AI-agnostic
behavioural routing middleware for Flutter.

```yaml
dependencies:
  agent_gate: ^0.1.0
  agent_gate_getx: ^0.1.0
  get: ^4.7.0
```

## Imperative — `GetxAdapter` (context-free)

```dart
AgentGate.configure(
  decider: HttpDecider(endpoint: Uri.parse('https://api.example.com/gate')),
  adapter: const GetxAdapter(),                     // mode: to | off | offAll
);

// From a controller, service, or button — no BuildContext:
await AgentGate.instance.navigate(checkoutGate, extra: {'total': cart.total});
```

Candidates with a `route` are navigated by name (`Get.toNamed` …); candidates
with only a `builder` go through `Get.to`. The destination can read why it was
chosen:

```dart
final why = GateArguments.current?.decision.reason;
```

## Inline — `GateGetPage`

```dart
GetMaterialApp(getPages: [
  GateGetPage(name: '/checkout', gate: checkoutGate,
      contextFromRoute: (params, args) => {'coupon': params['coupon']}),
]);
```

Navigating to `/checkout` shows the loading view, decides, and renders the
chosen candidate's `builder` in place.

## Reactive — `GateController`

```dart
final c = Get.put(GateController());
Obx(() => c.isDeciding.value ? const AgentLoadingView() : const SizedBox());
await c.navigate(checkoutGate);
c.lastDecision.value?.reason;
```

## Router middleware — `GateMiddleware` (Navigator 2 / `GetMaterialApp.router`)

```dart
GetPage(
  name: '/checkout',
  page: () => const SizedBox.shrink(),
  middlewares: [GateMiddleware(checkoutGate)],
),
GetPage(name: '/checkout/express',  page: () => const ExpressPage()),
GetPage(name: '/checkout/standard', page: () => const StandardPage()),
```

Implements the async `redirectDelegate`; GetX's synchronous `redirect` cannot
await a decision, so classic `Get.toNamed` apps should use `GetxAdapter` or
`GateGetPage`.

## Tracking pages

`GetMaterialApp(navigatorObservers: [GateNavigatorObserver()])` feeds
`enterPage`/`exitPage` from route names automatically.

## License

MIT © MSI Shamim / Increments Inc.
