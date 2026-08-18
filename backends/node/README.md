# agent_gate/v1 reference backend — Node / TypeScript

A small, production-shaped implementation of the endpoint that
`HttpDecider` in the Flutter package talks to. Copy it into your stack or use
it as the spec.

```
POST /agent-gate/decide     agent_gate/v1 request  →  { candidate_id, confidence, reason, model? }
GET  /healthz
```

## What it does

1. **Validates** the payload with `zod` (`src/schema.ts` mirrors the Flutter `GateRequest`).
2. **Verifies** the optional HMAC (`X-AgentGate-Signature` / `-Timestamp`) with a replay window (`src/signature.ts`).
3. **Rules first** (`src/rules.ts`): blocked users, hard amount limits, no-signal defaults. Deterministic, auditable, tamper-proof because they live server-side.
4. **Baseline enrichment** hook (`baselineFor`) — plug your warehouse's "typical user on this page" stats here; the device never computes it.
5. **Model** (`src/model.ts`): OpenAI-compatible chat completions with a *forced, enum-constrained* tool call — the model literally cannot answer with an id you didn't offer. Works with OpenAI, Groq, Mistral, Together, OpenRouter, Ollama … via `OPENAI_BASE_URL`.
6. **Defence in depth**: unknown ids → fallback with confidence 0; transport errors → **503** so the app retries; bad input/signature → **400** so the app falls back immediately.
7. **Audit** every decision (stdout JSON by default — replace with your sink).

## Run

```sh
cp .env.example .env         # set OPENAI_API_KEY (or leave empty for rules-only mode)
npm install
npm run dev                  # http://localhost:8787
```

Point the app at it:

```dart
HttpDecider(endpoint: Uri.parse('http://10.0.2.2:8787/agent-gate/decide'))
```

## Test

```sh
npm test        # vitest: rules, model parsing, unknown-id defence, HMAC, HTTP status mapping
npm run typecheck
```

## Extending

- Add rules in `src/rules.ts` — a rule is `(req) => decision | null`.
- Swap providers in `src/model.ts` (Anthropic / Gemini shapes are in the Flutter `PromptBuilder` and in the Python sample).
- Add fraud signals to `extraContext` in `decide()` (device reputation, velocity, IP risk) — that's exactly what the phone cannot be trusted to know.
- Persist `AuditRecord`s; the `request_id` matches the app's audit entry, so you can join both sides.
