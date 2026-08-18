# AgentGate for Flutter

**AI-agnostic behavioural routing middleware.** From page **A**, declare up to 1,000 candidate next pages **B0 … B999**. AgentGate collects consent-gated behaviour signals on-device, hands them to *your* backend or *your* AI, and routes the user to the one page that fits — with hard timeouts, deterministic fallbacks, allow-lists and a full audit trail.

```
   ┌──────────┐    behaviour + app context     ┌───────────────────────┐
   │  Page A  │ ─────────────────────────────▶ │  YOUR decider          │
   │ (cart,   │                                 │  · your backend API    │
   │ transfer,│  ◀──────────────────────────── │  · your rules          │
   │ search…) │   { candidate_id, confidence,   │  · your AI (OpenAI /   │
   └────┬─────┘     reason }                    │    Anthropic / Gemini /│
        │                                       │    local model …)      │
        │  AgentGate: validate → audit → route  └───────────────────────┘
        ▼
  ┌─────┴─────┬───────────┬───────────┬─ … ─┬───────────┐
  │    B0     │    B1     │    B2     │     │   B999    │
  │ express   │ standard  │ assisted  │     │ step-up   │
  │ checkout  │ checkout  │ checkout  │     │ auth      │
  └───────────┴───────────┴───────────┴─────┴───────────┘
```

> AgentGate does **not** ship a model, does **not** hold your API keys and does **not** decide anything on its own. It is the plumbing between "the user is leaving this page" and "the right next page is on screen", built for regulated, high-stakes apps.

---

## Table of contents

1. [Why AgentGate](#why-agentgate)
2. [Who it is for](#who-it-is-for) — banking, e-commerce, OTA/travel, insurance, telco, healthcare
3. [How it makes your work easier](#how-it-makes-your-work-easier)
4. [Install](#install)
5. [Five-minute quick start](#five-minute-quick-start)
6. [Core concepts](#core-concepts)
7. [Wiring your intelligence (deciders)](#wiring-your-intelligence-deciders)
   - Backend (recommended) · OpenAI · Anthropic · Gemini · Rules · Composite
8. [Behaviour tracking](#behaviour-tracking)
9. [State management & routers](#state-management--routers) — Navigator, GoRouter, GetX, Bloc, Riverpod, auto_route
10. [Risk vs. recommendation profiles](#risk-vs-recommendation-profiles)
11. [Security, privacy & compliance](#security-privacy--compliance)
12. [Audit & observability](#audit--observability)
13. [The wire protocol (`agent_gate/v1`)](#the-wire-protocol-agent_gatev1)
14. [Backend reference implementations](#backend-reference-implementations)
15. [Performance & cost](#performance--cost)
16. [FAQ](#faq)
17. [Roadmap](#roadmap)

---

## Why AgentGate

Every serious app has decision points where "which screen next?" depends on *who* the user is and *how* they are behaving right now:

| Situation | Today | With AgentGate |
|---|---|---|
| User taps **Pay** after three failed coupon attempts and a lot of back-and-forth | Same checkout for everyone → abandonment | Routed to *assisted* checkout with inline help |
| User on a bank transfer page edits the amount 9 times, goes back twice, new payee | Static rule: amount > X → OTP | Behaviour looks anomalous vs. baseline → step-up verification, even below the limit |
| Returning traveller on an OTA searches, hesitates 40 s on the fare screen | Generic results page | Routed to the "flexible fare / price-freeze" page |
| Insurance quote flow, user stalls on the medical questions | Drop-off | Routed to a "talk to an agent" page |

Building this yourself means: hand-rolled event tracking, an ad-hoc JSON payload, prompt engineering, JSON-parsing of model output, timeouts, fallbacks, retries, consent plumbing, redaction, audit logging, and then repeating all of that per state-management stack. AgentGate is that layer, done once, tested, and open.

## Who it is for

**Banks & fintech** — step-up authentication, fraud-aware flows, "are you sure?" pages for anomalous transfers, tailored onboarding. AgentGate's *risk profile* keeps rules as the floor, requires minimum confidence, falls back to the *safe* page, and audits every decision with a context hash.

**E-commerce & marketplaces** — express vs. standard vs. assisted checkout, upsell vs. cross-sell vs. plain cart, returning vs. new customer paths, abandonment rescue. The *recommendation profile* allows caching and longer model calls.

**OTA / travel & hospitality** — fare-family selection pages, ancillary upsell (bags, seats, insurance) only when behaviour suggests interest, "price freeze" pages for hesitant users, loyalty-tier routing.

**Insurance, telco, healthcare portals** — adaptive form flows, human-handoff pages when users struggle, eligibility-aware paths.

**Any product team** doing personalisation, A/B/n routing, or funnel optimisation who wants the *decision* to live in their backend, close to their data science and compliance teams — not hard-coded in the app.

## How it makes your work easier

- **One line to route**: `AgentGate.instance.navigate(checkoutGate, context: context)`.
- **Zero vendor lock-in**: bring OpenAI, Anthropic, Gemini, Mistral, Llama, a scikit model, a rules engine — or a human review queue. AgentGate speaks plain JSON.
- **Keys stay off the device**: the recommended path is `HttpDecider` → your backend → your model. `CallbackDecider` exists if you insist on on-device SDKs.
- **Behaviour signals for free**: dwell time, hesitation, taps per target, attempts/failures, validation errors, field edits (never values), scroll depth, back-navigation, page trail. Consent-gated, bounded, in-memory.
- **Never hangs, never routes off-map**: hard timeout, retries only for transient errors, unknown ids rejected, allow-lists enforced, minimum-confidence enforced, always a fallback.
- **Compliance built in**: consent controller, PII redaction, explainable `reason` on every decision, audit sink with context hash, no raw input captured.
- **Works with your stack**: Navigator 1.0/2.0, GoRouter, GetX, Bloc, Riverpod, auto_route, Beamer — via three tiny adapters or a widget you can drop into any router.
- **Prompt scaffolding included**: `PromptBuilder` gives you enum-constrained tool/function schemas in OpenAI, Anthropic and Gemini shapes so your backend is ~20 lines.

## Install

```yaml
dependencies:
  agent_gate: ^0.1.0
```

Requires Flutter ≥ 3.22 / Dart ≥ 3.13. No platform code, no native dependencies.

## Five-minute quick start

**1. Configure once (e.g. in `main()`):**

```dart
import 'package:agent_gate/agent_gate.dart';

void main() {
  AgentGate.configure(
    // Your backend decides. It holds the AI key and your business rules.
    decider: HttpDecider(
      endpoint: Uri.parse('https://api.yourcompany.com/agent-gate/decide'),
      headers: (req) async => {'authorization': 'Bearer ${await auth.token()}'},
    ),
    // How to actually navigate — plain Navigator here.
    adapter: const NavigatorAdapter(),
    // App context every decision should see (redaction applies).
    contextBuilder: () => {'tier': session.tier, 'country': session.country},
    // Where audit entries go.
    auditSink: MyAuditSink(),
  );
  runApp(const MyApp());
}
```

**2. Declare a gate (top-level, reusable):**

```dart
final checkoutGate = Gate(
  id: 'cart_to_checkout',
  from: 'cart',
  fallback: 'checkout_standard',
  config: const GateConfig.recommendation(),
  candidates: [
    GateCandidate(
      id: 'checkout_express',
      label: 'Express checkout',
      description: 'One-tap with saved card. For confident returning users who move fast.',
      builder: (_) => const ExpressCheckoutPage(),
    ),
    GateCandidate(
      id: 'checkout_standard',
      label: 'Standard checkout',
      description: 'Regular 3-step flow. Safe default.',
      builder: (_) => const StandardCheckoutPage(),
    ),
    GateCandidate(
      id: 'checkout_assisted',
      label: 'Assisted checkout',
      description: 'Guided flow with help. When the user struggled (failed coupons, many backs).',
      builder: (_) => const AssistedCheckoutPage(),
    ),
  ],
);
```

**3. Track the page and route:**

```dart
class CartPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = AgentGate.instance.tracker;
    return TrackedPage(               // records enter/exit for page 'cart'
      id: 'cart',
      child: Scaffold(
        body: Column(children: [
          TrackedTap(id: 'btn_apply_coupon', onTap: applyCoupon, child: const Text('Apply coupon')),
          FilledButton(
            onPressed: () => AgentGate.instance.navigate(
              checkoutGate,
              context: context,
              extra: {'cart_total': cart.total, 'items': cart.count},
            ),
            child: const Text('Checkout'),
          ),
        ]),
      ),
    );
  }
}
```

**4. Turn tracking on when the user consents:**

```dart
AgentGate.instance.tracker.consent.grant();   // after your privacy prompt
```

That's it. When the user taps **Checkout**, AgentGate shows a subtle loading overlay, POSTs a JSON payload to your endpoint, validates the answer, audits it, and pushes the chosen page. If anything goes wrong within the timeout, it pushes `checkout_standard`.

Run the `example/` app to see this offline (a simulated decider is included).

## Core concepts

| Type | What it is |
|---|---|
| `Gate` | A decision point: `id`, `from` page, `candidates` (B0…Bn), `fallback`, optional `config`, `instructions`, per-gate `decider`. Validated at construction (no dupes, ≤ 1000, fallback must exist). |
| `GateCandidate` | One destination: `id`, `label`, plain-language `description` (this is what the AI reads), and *either* a `builder` (Navigator) *or* a `route` string (routers) — or both. Plus `tags`, `priority`, `metadata`. |
| `GateConfig` | Timeout, retries, `minConfidence`, `cacheTtl`, `allowedCandidateIds`, `redactKeys`, `requireConsent`, `showLoadingUi`. Named presets: `.risk()`, `.recommendation()`. |
| `AgentDecider` | The one interface between AgentGate and your intelligence. Ships with `HttpDecider`, `CallbackDecider`, `RuleDecider`, `CompositeDecider`. |
| `NavigationAdapter` | How to navigate: `NavigatorAdapter`, `RouteNameAdapter`, `CallbackAdapter`. |
| `BehaviorTracker` | Consent-gated, in-memory event collector + per-page summaries. |
| `GateContext` / `GateRequest` | The JSON payload your decider receives. |
| `GateDecision` | `{candidate_id, confidence, reason}` + `source` (agent / rule / cache / fallback), `model`, `latency`. |
| `GateAuditSink` / `GateObserver` | Where decisions are recorded and lifecycle hooks. |
| `GatePage` | A widget that decides inline and renders the chosen candidate — perfect for declarative routers. |

## Wiring your intelligence (deciders)

### Backend (recommended)

```dart
HttpDecider(
  endpoint: Uri.parse('https://api.example.com/gate'),
  headers: (req) async => {'authorization': 'Bearer ${await getToken()}'},
  signingSecret: kIsWeb ? null : 'optional-hmac-secret',   // adds X-AgentGate-Signature
  decodeResponse: (json) => json['data'] as Map<String, Object?>, // if you wrap responses
)
```

Your endpoint receives the [`agent_gate/v1` payload](#the-wire-protocol-agent_gatev1) and returns:

```json
{ "candidate_id": "checkout_assisted", "confidence": 0.86, "reason": "Two failed coupon attempts and 3 back-navigations.", "model": "gpt-4o-mini" }
```

Return HTTP 5xx / 429 for transient failures (AgentGate retries per `maxRetries`), 4xx for permanent ones (no retry, fallback).

### On-device with any SDK (`CallbackDecider` + `PromptBuilder`)

`PromptBuilder` renders the system prompt, user prompt and an **enum-constrained** tool schema in three provider shapes. Your job is just to call the SDK and pass back the tool arguments.

**OpenAI / OpenAI-compatible (Groq, Mistral, Together, Ollama…)**

```dart
CallbackDecider((req) async {
  final body = PromptBuilder().openAiRequest(req)..['model'] = 'gpt-4o-mini';
  final res = await http.post(Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {'authorization': 'Bearer $OPENAI_KEY', 'content-type': 'application/json'},
      body: jsonEncode(body));
  final msg = jsonDecode(res.body)['choices'][0]['message'];
  final args = jsonDecode(msg['tool_calls'][0]['function']['arguments']);
  return GateDecision.fromJson(args, model: 'gpt-4o-mini');
});
```

**Anthropic**

```dart
CallbackDecider((req) async {
  final body = PromptBuilder().anthropicRequest(req)
    ..['model'] = 'claude-sonnet-5'
    ..['max_tokens'] = 300;
  final res = await http.post(Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {'x-api-key': ANTHROPIC_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'},
      body: jsonEncode(body));
  final content = (jsonDecode(res.body)['content'] as List)
      .firstWhere((c) => c['type'] == 'tool_use');
  return GateDecision.fromJson(content['input'], model: 'claude-sonnet-5');
});
```

**Gemini**

```dart
CallbackDecider((req) async {
  final body = PromptBuilder().geminiRequest(req);
  final res = await http.post(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_KEY'),
      headers: {'content-type': 'application/json'}, body: jsonEncode(body));
  final call = jsonDecode(res.body)['candidates'][0]['content']['parts'][0]['functionCall'];
  return GateDecision.fromJson(call['args'], model: 'gemini-2.5-flash');
});
```

> Keys on device are visible to anyone with the binary. Use `flutter_dotenv`/`--dart-define` for development; use `HttpDecider` for production.

### Rules and composition

```dart
AgentGate.configure(
  decider: CompositeDecider([
    RuleDecider([
      GateRule(id: 'blocked_country', when: (r) => r.context.app['country'] == 'XX', candidateId: 'blocked'),
      GateRule(id: 'over_limit', when: (r) => (r.context.app['amount'] as num) > 5000, candidateId: 'step_up'),
    ]),
    HttpDecider(endpoint: ...),        // only reached when no rule matched
  ]),
);
```

Rules are evaluated first, in order, deterministically. In risk profiles this is where your non-negotiables live; the AI only ranks the grey zone.

### Streaming reasoning into the loading UI

Any decider may implement `Stream<String>? reasoning(GateRequest)`. The default `AgentLoadingView` shows it live ("Comparing 3 options…"). Replace the whole screen with `AgentGate.configure(loadingBuilder: (ctx, stream) => MyLoader(stream))`.

## Behaviour tracking

```dart
final t = AgentGate.instance.tracker;

t.enterPage('transfer');          // or wrap in TrackedPage / use GateNavigatorObserver
t.tap('btn_continue');
t.fieldFocus('field_amount');
t.fieldEdit('field_amount', length: 4);   // the VALUE is never captured
t.validationError('field_amount', code: 'min');
t.attempt('transfer');
t.failure('transfer', code: 'declined');
t.scroll(0.8);                            // throttled
t.back();
t.custom('opened_help', target: 'faq_fees');
t.exitPage();
```

What the decider sees for the current page (`PageSessionSummary`):

```json
{ "page": "transfer", "dwell_ms": 41200, "hesitation_ms": 3800, "taps": 7, "attempts": 2, "failures": 1,
  "validation_errors": 2, "backs": 1, "field_edits": 9, "max_scroll": 0.6,
  "taps_by_target": {"btn_continue": 2, "field_amount": 5}, "attempts_by_name": {"transfer": 2} }
```

plus `history` — the same summary for the last *N* pages — and the ordered `pageTrail`. Raw events are **not** sent unless you set `includeRawEvents: true`.

Automatic page tracking options:

- `TrackedPage(id: 'cart', child: …)` — explicit, works everywhere.
- `GateNavigatorObserver()` in `MaterialApp.navigatorObservers` / GoRouter `observers` — uses route names.
- Call `enterPage/exitPage` yourself from a Bloc, GetX controller, or Riverpod notifier.

**Consent**: nothing is recorded until `tracker.consent.grant()`. Revoking clears the buffers. `GateConfig.requireConsent` (default `true`) also strips behaviour from the payload.

**Bounds**: `maxEvents` (2000) and `maxPages` (30) ring buffers. Nothing is persisted to disk by AgentGate.

## State management & routers

AgentGate has zero dependencies on any state-management or routing package. Pick an adapter:

### Plain Navigator

```dart
adapter: const NavigatorAdapter(),          // uses candidate.builder
AgentGate.instance.navigate(gate, context: context);
```

### GoRouter

*Imperative*:

```dart
adapter: RouteNameAdapter((ctx, route, _) async => ctx!.go(route)),
// candidates use route: '/checkout/express'
```

*Declarative* — let the router own the page and decide inline:

```dart
GoRoute(path: '/checkout', builder: (_, __) => GatePage(gate: checkoutGate)),
```

### GetX

```dart
adapter: RouteNameAdapter((_, route, __) async => Get.toNamed(route)),
AgentGate.instance.navigate(gate);   // no context needed
```

### Bloc / Cubit

Keep the decision in your state machine:

```dart
class CheckoutCubit extends Cubit<CheckoutState> {
  Future<void> proceed() async {
    emit(CheckoutState.deciding());
    final d = await AgentGate.instance.decide(checkoutGate, extra: {'total': total});
    emit(CheckoutState.route(d.candidateId));   // your UI listens and navigates
  }
}
```

Or use `CallbackAdapter((ctx, cand, dec) async => bloc.add(NavigateTo(cand.id)))`.

### Riverpod

```dart
final nextPageProvider = FutureProvider.family<GateDecision, Gate>(
  (ref, gate) => AgentGate.instance.decide(gate));
```

### auto_route / Beamer / anything with named routes

`RouteNameAdapter` covers all of them. For fully custom stacks use `CallbackAdapter`.

## Risk vs. recommendation profiles

| | `GateConfig.risk()` | `GateConfig.recommendation()` |
|---|---|---|
| Purpose | Fraud, step-up auth, safety | Personalisation, upsell, funnel |
| Timeout | 2 s | 6 s |
| Retries | 0 | 1 |
| `minConfidence` | 0.6 | 0 |
| Cache | off | 10 min |
| Fallback advice | The **safest** page | The **default** page |
| Rules | Floor — put non-negotiables in `RuleDecider` first | Optional |

Both are just `GateConfig` presets; override anything with `copyWith`.

**Guidance for regulated flows**: never route to a *less* protected page on the strength of an AI decision alone. Express the protective outcomes as rules or `allowedCandidateIds` and let AI choose only among acceptable options.

## Security, privacy & compliance

- **Keys**: not on device (`HttpDecider`). AgentGate never sees them.
- **Consent**: off by default; `ConsentController`; revoke wipes memory.
- **Minimisation**: summaries not raw events by default; field values never captured; `Redactor` strips PII/PCI keys (defaults include `email, phone, pan, card_number, cvv, ssn, iban, token, password, otp, dob, address…`) at any depth before payload leaves the device. Extend via `redactKeys`.
- **Explainability**: every decision carries a `reason`; keep it truthful in your prompt (the default system prompt instructs the model to).
- **Bounded automation**: `allowedCandidateIds` and `RuleDecider` are the developer's guardrails so an LLM can never route outside what your compliance team approved.
- **Integrity**: optional HMAC signing (`X-AgentGate-Signature`, `X-AgentGate-Timestamp`) for tamper-evidence. For fraud use cases pair with **App Attest / Play Integrity** tokens via `headers`, and enforce a replay window server-side. A device is never a trusted fraud oracle — the *scoring* belongs on your backend.
- **Audit**: `GateAuditEntry` records request id, gate, candidates offered, decision, source, confidence, reason, model, latency, decider, error, and a **context hash** — so you can prove *what* was sent without storing PII.
- **Regulatory notes** (not legal advice): behaviour-based routing may constitute profiling (GDPR Art. 22 / UK GDPR), be subject to consumer-protection rules on manipulative design (EU DSA/UCPD, UK FCA Consumer Duty, US CFPB/FTC "dark patterns" guidance). AgentGate gives you consent, minimisation, explainability and allow-lists — you still own the DPIA and the choice of what you route to. Prefer routing that serves the user (help, protection, relevance) over routing that only serves conversion.

## Audit & observability

```dart
class SiemAuditSink implements GateAuditSink {
  @override
  Future<void> record(GateAuditEntry e) => siem.send(e.toJson());
}

class AnalyticsObserver extends GateObserver {
  @override
  void onDecision(GateRequest r, GateDecision d) => analytics.log('gate_decision', {
    'gate': r.gateId, 'to': d.candidateId, 'source': d.source.name, 'conf': d.confidence,
  });
  @override
  void onFallback(GateRequest r, Object error, GateDecision fb) => crashlytics.log('gate fallback: $error');
}

AgentGate.configure(
  auditSink: MultiAuditSink([SiemAuditSink(), MemoryAuditSink()]),
  observers: [AnalyticsObserver()],
);
```

## The wire protocol (`agent_gate/v1`)

Request (POST body from `HttpDecider`, or `GateRequest.toJson()`):

```json
{
  "schema": "agent_gate/v1",
  "request_id": "lz3k9q-4-a8f1c2",
  "timestamp": "2026-08-18T09:12:44.120Z",
  "gate_id": "cart_to_checkout",
  "from_page": "cart",
  "profile": "recommendation",
  "instructions": "Prefer the fewest steps unless the user showed confusion.",
  "candidates": [
    {"id": "checkout_express", "label": "Express checkout", "description": "…", "route": "/checkout/express", "priority": 0},
    {"id": "checkout_standard", "label": "Standard checkout", "description": "…", "priority": 0},
    {"id": "checkout_assisted", "label": "Assisted checkout", "description": "…", "tags": ["help"], "priority": 0}
  ],
  "context": {
    "consent": true,
    "current_page": {"page": "cart", "dwell_ms": 41200, "taps": 7, "attempts": 2, "failures": 2, "backs": 1, "...": "..."},
    "history": [{"page": "product", "dwell_ms": 12000, "...": "..."}],
    "app": {"tier": "gold", "cart_total": 211, "email": "[REDACTED]"},
    "device": {"platform": "android", "locale": "en-GB", "debug": false}
  }
}
```

Response:

```json
{ "candidate_id": "checkout_assisted", "confidence": 0.86, "reason": "…", "model": "gpt-4o-mini" }
```

Rules AgentGate enforces on the answer: id must be a candidate; must be in `allowedCandidateIds` if set; `confidence ≥ minConfidence`; arrives before `timeout`. Otherwise → `fallback`, with the reason recorded.

Headers sent: `content-type: application/json`, `x-agentgate-request-id`, plus yours, plus optional `x-agentgate-timestamp` / `x-agentgate-signature: sha256=<hmac(ts + "." + body)>`.

## Backend reference implementations

Any language works. A minimal Node/TypeScript handler using the OpenAI SDK:

```ts
// POST /agent-gate/decide
import OpenAI from "openai";
const openai = new OpenAI();

export async function decide(req: AgentGateRequest) {
  const ids = req.candidates.map(c => c.id);
  const baseline = await getBaselineFor(req.from_page);            // your population stats
  const risk = await riskEngine.score(req.request_id, req.context); // your fraud signals

  const completion = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    temperature: 0,
    messages: [
      { role: "system", content: SYSTEM_PROMPT_FOR(req.profile) },
      { role: "user", content: JSON.stringify({ candidates: req.candidates, context: { ...req.context, baseline, risk } }) },
    ],
    tools: [{ type: "function", function: { name: "choose_next_page", strict: true,
      parameters: { type: "object", additionalProperties: false, required: ["candidate_id","confidence","reason"],
        properties: { candidate_id: { type: "string", enum: ids }, confidence: { type: "number" }, reason: { type: "string" } } } } }],
    tool_choice: { type: "function", function: { name: "choose_next_page" } },
  });
  const args = JSON.parse(completion.choices[0].message.tool_calls![0].function.arguments);
  await audit.save({ ...args, request_id: req.request_id, model: "gpt-4o-mini" });
  return { ...args, model: "gpt-4o-mini" };
}
```

The system prompt text is available on-device via `PromptBuilder().systemPrompt(req)` if you want to keep it in one place; most teams copy it into the backend and iterate there.

## Performance & cost

- **Fast path**: `RuleDecider` answers in microseconds; only grey-zone requests reach a model.
- **Cache**: `cacheTtl` keys on gate + candidate ids + context hash. Same behaviour, same answer, zero calls.
- **Prefetch**: `AgentGate.instance.prefetch(gate)` while the user is still on page A (e.g. after they fill the last field) — the later `navigate` is instant.
- **Payload size**: summaries only, typically 1–3 KB. Raw events are opt-in.
- **Loading UX**: the overlay is only shown when a decision is actually in flight; disable with `showLoadingUi: false` and show your own.
- **Model choice**: this is a classification-with-reason task — small/fast models (gpt-4o-mini, Claude Haiku, Gemini Flash) do very well with the enum-constrained schema.

## FAQ

**Does AgentGate call any AI service?** No. It has no AI dependency at all. You provide an `AgentDecider`.

**Can I use it without any AI?** Yes — `RuleDecider` alone gives you a declarative, audited, consent-aware behavioural router.

**Where do API keys go?** Your backend. If you must call an SDK from the app, use `CallbackDecider` and understand the key is extractable.

**Does it work on web?** Yes; it's pure Dart/Flutter. HMAC signing is pointless on web (secret is visible) — leave `signingSecret` null there.

**How many candidates?** 1 to 1,000 per gate (`kMaxGateCandidates`). For very large sets, pre-filter with rules or `metadata` on the backend — models choose better among ≤ 20 well-described options.

**Is behaviour data sent to third parties?** Only to whatever *your* decider sends it to. AgentGate itself never phones home.

**Can decisions be A/B tested?** Yes — put the bucket in `contextBuilder` and let your backend/rules branch on it; every audit entry carries the full context hash for later analysis.

**What if the model picks something outside the allow-list?** AgentGate rejects it and routes to `fallback`, recording why. Observers get `onFallback`.

## Companion packages & backend samples

| Package | What |
|---|---|
| [`agent_gate_go_router`](../agent_gate_go_router) | `GoRouterAdapter`, `GateExtra`, `GateRoute.page`, `GateRoute.redirect` (async redirect middleware) |
| [`agent_gate_getx`](../agent_gate_getx) | `GetxAdapter` (context-free), `GateArguments`, `GateGetPage`, `GateController`, `GateMiddleware` |
| [`agent_gate_bloc`](../agent_gate_bloc) | `GateCubit`, `GateBloc`, sealed `GateState`, `GateBlocListener` |
| [`backends/node`](../../backends/node) | Reference `agent_gate/v1` endpoint — Express + zod + OpenAI-compatible |
| [`backends/python`](../../backends/python) | Reference `agent_gate/v1` endpoint — FastAPI + OpenAI / Anthropic / Gemini providers |

## Roadmap

- Optional persistent audit sink (SQLite) and encrypted event buffer.
- Session-level baseline sync (backend pushes population stats down for on-device pre-scoring).
- Multi-step "agentic" gates: decide → collect one more signal → re-decide, with a step budget.
- Web dashboard template for reviewing decisions and drift.

---

## Contributing

Issues and PRs welcome. Run `flutter test` and `flutter analyze` (the package is lint-clean with `public_member_api_docs`). Keep the core free of AI-provider and state-management dependencies — those belong in companion packages.

## License

MIT — see `LICENSE`.

Authored by MSI Shamim · Increments Inc.
