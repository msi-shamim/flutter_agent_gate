from __future__ import annotations

import hashlib
import hmac
import json
from typing import Any

import httpx
import pytest
import respx

from app.decide import DecideDeps, decide
from app.main import create_app, verify_signature
from app.providers import Anthropic, Gemini, OpenAICompatible, ProviderError
from app.schema import GateDecision, GateRequest


def make_req(**over: Any) -> GateRequest:
    base: dict[str, Any] = {
        "schema": "agent_gate/v1",
        "request_id": "r1",
        "timestamp": "2026-08-18T00:00:00Z",
        "gate_id": "transfer_to_confirm",
        "from_page": "transfer",
        "profile": "risk",
        "candidates": [
            {"id": "confirm_simple", "label": "Simple", "description": "bio", "tags": ["low_friction", "default"]},
            {"id": "confirm_stepup", "label": "Step-up", "description": "otp", "tags": ["protective"]},
        ],
        "context": {"consent": True, "app": {"amount": 100}},
    }
    base.update(over)
    return GateRequest.model_validate(base)


class FakeProvider:
    name = "fake"

    def __init__(self, cid: str, *, raise_transient: bool = False):
        self.cid, self.raise_transient = cid, raise_transient

    async def decide(self, req: GateRequest, extra: dict[str, Any]) -> GateDecision:
        if self.raise_transient:
            raise ProviderError("boom")
        return GateDecision(candidate_id=self.cid, confidence=0.8, reason="fake", model="fake")


# ── pipeline ────────────────────────────────────────────────────────────

async def test_rules_win_before_model():
    d = await decide(make_req(context={"consent": True, "app": {"amount": 9000}}), DecideDeps(provider=FakeProvider("confirm_simple")))
    assert d.candidate_id == "confirm_stepup" and d.reason.startswith("rule:amount_over")


async def test_model_used_and_audited():
    audits: list[dict[str, Any]] = []
    d = await decide(make_req(), DecideDeps(provider=FakeProvider("confirm_simple"), audit=audits.append))
    assert d.candidate_id == "confirm_simple" and d.model == "fake"
    assert audits and audits[0]["source"] == "model"


async def test_unknown_id_is_rejected():
    d = await decide(make_req(), DecideDeps(provider=FakeProvider("evil")))
    assert d.candidate_id == "confirm_simple" and d.confidence == 0 and "unknown id" in d.reason


async def test_rules_only_mode():
    d = await decide(make_req(), DecideDeps(provider=None))
    assert d.confidence == 0 and "rules-only" in d.reason


async def test_transient_error_propagates():
    with pytest.raises(ProviderError):
        await decide(make_req(), DecideDeps(provider=FakeProvider("x", raise_transient=True)))


# ── providers (REST shapes, mocked with respx) ──────────────────────────

@respx.mock
async def test_openai_provider_parses_tool_call():
    respx.post("https://api.openai.com/v1/chat/completions").mock(return_value=httpx.Response(200, json={
        "choices": [{"message": {"tool_calls": [{"function": {"name": "choose_next_page", "arguments": json.dumps({"candidate_id": "confirm_simple", "confidence": 0.7, "reason": "ok"})}}]}}]
    }))
    p = OpenAICompatible("k", "gpt-4o-mini")
    d = await p.decide(make_req(), {})
    assert d.candidate_id == "confirm_simple" and d.model == "gpt-4o-mini"
    sent = json.loads(respx.calls.last.request.content)
    assert sent["tool_choice"]["function"]["name"] == "choose_next_page"
    assert sent["tools"][0]["function"]["parameters"]["properties"]["candidate_id"]["enum"] == ["confirm_simple", "confirm_stepup"]


@respx.mock
async def test_anthropic_provider_parses_tool_use():
    respx.post("https://api.anthropic.com/v1/messages").mock(return_value=httpx.Response(200, json={
        "content": [{"type": "text", "text": "thinking"}, {"type": "tool_use", "name": "choose_next_page", "input": {"candidate_id": "confirm_stepup", "confidence": 0.9, "reason": "anomalous"}}]
    }))
    d = await Anthropic("k", "claude-sonnet-5").decide(make_req(), {})
    assert d.candidate_id == "confirm_stepup"


@respx.mock
async def test_gemini_provider_parses_function_call_and_strips_additionalProperties():
    route = respx.post(url__startswith="https://generativelanguage.googleapis.com/").mock(return_value=httpx.Response(200, json={
        "candidates": [{"content": {"parts": [{"functionCall": {"name": "choose_next_page", "args": {"candidate_id": "confirm_simple", "confidence": 0.6, "reason": "fine"}}}]}}]
    }))
    d = await Gemini("k", "gemini-2.5-flash").decide(make_req(), {})
    assert d.candidate_id == "confirm_simple"
    sent = json.loads(route.calls.last.request.content)
    assert "additionalProperties" not in sent["tools"][0]["function_declarations"][0]["parameters"]


@respx.mock
async def test_provider_5xx_is_transient():
    respx.post("https://api.openai.com/v1/chat/completions").mock(return_value=httpx.Response(502))
    with pytest.raises(ProviderError):
        await OpenAICompatible("k", "m").decide(make_req(), {})


# ── signature + HTTP ────────────────────────────────────────────────────

def _sign(secret: str, ts: int, body: bytes) -> str:
    return "sha256=" + hmac.new(secret.encode(), f"{ts}.".encode() + body, hashlib.sha256).hexdigest()


def test_verify_signature():
    body, ts = b'{"a":1}', 1_000_000
    ok = verify_signature(body, {"x-agentgate-timestamp": str(ts), "x-agentgate-signature": _sign("s", ts, body)}, "s", 300_000, now_ms=ts + 5)
    assert ok is None
    assert verify_signature(body, {"x-agentgate-timestamp": str(ts), "x-agentgate-signature": _sign("s", ts, body)}, "s", 300_000, now_ms=ts + 10 * 60_000)
    assert verify_signature(body, {"x-agentgate-timestamp": str(ts), "x-agentgate-signature": "sha256=00"}, "s", 300_000, now_ms=ts)


async def test_http_roundtrip_and_status_mapping():
    app = create_app(DecideDeps(provider=FakeProvider("confirm_simple")))
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://t") as c:
        r = await c.post("/agent-gate/decide", json=make_req().model_dump(by_alias=True))
        assert r.status_code == 200 and r.json()["candidate_id"] == "confirm_simple"
        assert r.headers["x-agentgate-request-id"] == "r1"
        bad = await c.post("/agent-gate/decide", json={"schema": "nope"})
        assert bad.status_code == 400

    app503 = create_app(DecideDeps(provider=FakeProvider("x", raise_transient=True)))
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app503), base_url="http://t") as c:
        r = await c.post("/agent-gate/decide", json=make_req().model_dump(by_alias=True))
        assert r.status_code == 503


async def test_http_rejects_bad_signature():
    app = create_app(DecideDeps(provider=None), signing_secret="s")
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as c:
        r = await c.post("/agent-gate/decide", json=make_req().model_dump(by_alias=True))
        assert r.status_code == 400 and "signature" in r.json()["error"]
