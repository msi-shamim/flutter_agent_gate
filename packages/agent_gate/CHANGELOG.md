## 0.1.0

Initial release.

- `Gate` / `GateCandidate` (up to 1,000 candidates per gate) with validation.
- `AgentGate.navigate` / `decide` / `prefetch` pipeline: cache → rules → decider with retries and a hard timeout → validation (known id, allow-list, min confidence) → audit → adapter navigation.
- Deciders: `HttpDecider` (recommended, optional HMAC signing), `CallbackDecider`, `RuleDecider`, `CompositeDecider`.
- `PromptBuilder` with enum-constrained tool schemas for OpenAI, Anthropic and Gemini request shapes.
- Consent-gated `BehaviorTracker` with per-page `PageSessionSummary` (dwell, hesitation, taps, attempts, failures, validation errors, field edits, scroll, back, page trail).
- `Redactor` for PII/PCI keys; `GateContext` with app / device / baseline layers.
- Adapters: `NavigatorAdapter`, `RouteNameAdapter` (GoRouter, GetX, auto_route, Beamer…), `CallbackAdapter` (Bloc, Riverpod, custom).
- Widgets: `GatePage`, `TrackedPage`, `TrackedTap`, `GateNavigatorObserver`, `AgentLoadingView` with streamed reasoning.
- Audit: `GateAuditSink`, `MemoryAuditSink`, `MultiAuditSink`; `GateObserver` hooks.
- `GateConfig.risk()` and `GateConfig.recommendation()` presets.
