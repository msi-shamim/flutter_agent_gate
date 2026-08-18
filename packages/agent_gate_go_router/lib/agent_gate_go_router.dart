/// GoRouter integration for `agent_gate`.
///
/// Three ways to use AgentGate with GoRouter, from most to least explicit:
///
/// 1. **Imperative** — [GoRouterAdapter] as the global adapter, then
///    `AgentGate.instance.navigate(gate, context: context)`. Shows the loading
///    overlay, then calls `context.go/push(candidate.route)`.
/// 2. **Declarative page** — [GateRoute] builds a `GoRoute` whose page is a
///    `GatePage`: the AI-chosen candidate renders *inside* that route.
/// 3. **Redirect middleware** — [gateRedirect] plugs into `GoRoute.redirect`
///    so the router itself resolves `/checkout` to `/checkout/express` before
///    anything is built. No overlay (GoRouter blocks navigation while the
///    redirect future is pending) — keep timeouts short here.
///
/// The chosen decision is forwarded as `state.extra` ([GateExtra]) so the
/// destination page can read *why* it was chosen; see [GoRouterStateGate].
library;

export 'src/gate_extra.dart';
export 'src/gate_route.dart';
export 'src/go_router_adapter.dart';
