# agent_gate/v1 reference backend — Python / FastAPI

A small, production-shaped implementation of the endpoint that `HttpDecider`
in the Flutter package talks to — with a **pluggable provider layer**
(OpenAI-compatible, Anthropic, Gemini) so you can see all three request
shapes side by side.

```
POST /agent-gate/decide     agent_gate/v1 request  →  { candidate_id, confidence, reason, model? }
GET  /healthz
```

## Layout

| File | Role |
|---|---|
| `app/schema.py` | Pydantic models mirroring the Flutter `GateRequest` / `GateDecision` |
| `app/rules.py` | Deterministic, server-side rules (the floor for risk gates) |
| `app/prompt.py` | System prompt + enum-constrained tool schema (mirrors Flutter `PromptBuilder`) |
| `app/providers.py` | `OpenAICompatible`, `Anthropic`, `Gemini` over plain `httpx` — swap for the official SDK in your service |
| `app/decide.py` | Pipeline: rules → baseline enrichment → provider → unknown-id defence → audit |
| `app/main.py` | FastAPI: HMAC verify, validation, status mapping (200 / 400 / 503) |

## Run

```sh
python -m venv .venv && . .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -e ".[dev]"
cp .env.example .env                              # set a provider key, or leave empty for rules-only
uvicorn app.main:app --reload --port 8787
```

App side: `HttpDecider(endpoint: Uri.parse('http://10.0.2.2:8787/agent-gate/decide'))`.

## Test

```sh
pytest -q      # 12 tests: rules, pipeline, all three provider shapes (respx-mocked), HMAC, HTTP status mapping
```

## Status codes ↔ app behaviour

| Code | Meaning | `HttpDecider` reaction |
|---|---|---|
| 200 | decision | validated against allow-list / min-confidence, then used |
| 400 | bad payload / bad signature | fallback, no retry |
| 503 | provider transport error | retry (`maxRetries`), then fallback |

## Extending

- Rules: add a function `(req) -> GateDecision | None` to `DEFAULT_RULES`.
- Baseline: pass `DecideDeps(baseline_for=my_warehouse_lookup)` — "how a typical user behaves on this page" is server knowledge.
- Fraud signals: extend `extra` in `decide()` (device reputation, velocity, IP risk).
- Audit: replace the stdout printer in `create_app` with your sink; `request_id` joins with the app's audit entry.
