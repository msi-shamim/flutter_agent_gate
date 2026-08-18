"""
HTTP layer (FastAPI). Thin by design: parse → verify → decide → map errors to
the status codes the Flutter ``HttpDecider`` understands:

    200  {candidate_id, confidence, reason, model?}  → used (after app-side checks)
    400  invalid body / bad signature                 → app falls back, no retry
    503  provider transport failure                   → app retries, then falls back
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import sys
import time

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from .decide import DecideDeps, decide
from .providers import ProviderError, provider_from_env
from .schema import GateRequest


def verify_signature(raw: bytes, headers: dict[str, str], secret: str, replay_window_ms: int, now_ms: int | None = None) -> str | None:
    """Return an error string, or None when the signature is valid.

    Format (from Flutter HttpDecider): ``sha256=<hex hmac(secret, f"{ts}.{body}")>``.
    Tamper-evidence only — the secret ships in the app binary.
    """
    ts = headers.get("x-agentgate-timestamp")
    sig = headers.get("x-agentgate-signature")
    if not ts or not sig:
        return "missing signature headers"
    try:
        ts_i = int(ts)
    except ValueError:
        return "bad timestamp"
    now = now_ms if now_ms is not None else int(time.time() * 1000)
    if abs(now - ts_i) > replay_window_ms:
        return "timestamp outside replay window"
    expected = "sha256=" + hmac.new(secret.encode(), f"{ts}.".encode() + raw, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, sig):
        return "signature mismatch"
    return None


def create_app(deps: DecideDeps | None = None, signing_secret: str | None = None, replay_window_ms: int = 300_000) -> FastAPI:
    app = FastAPI(title="agent_gate/v1 decide endpoint")
    _deps = deps or DecideDeps(provider=provider_from_env(), audit=lambda r: print(json.dumps({"audit": r}), file=sys.stdout))

    @app.get("/healthz")
    async def healthz() -> dict[str, object]:
        return {"ok": True, "mode": "model" if _deps.provider else "rules-only", "provider": getattr(_deps.provider, "name", None)}

    @app.post("/agent-gate/decide")
    async def decide_route(request: Request) -> Response:
        raw = await request.body()
        if signing_secret:
            err = verify_signature(raw, {k.lower(): v for k, v in request.headers.items()}, signing_secret, replay_window_ms)
            if err:
                return JSONResponse({"error": err}, status_code=400)
        try:
            req = GateRequest.model_validate_json(raw)
        except ValidationError as e:
            return JSONResponse({"error": "invalid agent_gate/v1 payload", "issues": e.errors()}, status_code=400)
        try:
            d = await decide(req, _deps)
        except ProviderError:
            return JSONResponse({"error": "model unavailable"}, status_code=503)
        return JSONResponse(d.model_dump(exclude_none=True), headers={"x-agentgate-request-id": req.request_id})

    return app


app = create_app(
    signing_secret=os.getenv("AGENT_GATE_SIGNING_SECRET") or None,
    replay_window_ms=int(os.getenv("AGENT_GATE_REPLAY_WINDOW_MS", "300000")),
)
