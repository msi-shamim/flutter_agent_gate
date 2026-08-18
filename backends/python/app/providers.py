"""
Provider layer — the only file that knows about a specific AI vendor.

Why plain REST via ``httpx`` instead of three SDKs? The reference backend
should show the *shape* of each request (mirroring the Flutter
``PromptBuilder``), stay dependency-light, and be trivially portable to a
Cloudflare Worker / Lambda / whatever. In your own service, use the official
SDK for the provider you pick — the request bodies below are exactly what the
SDKs build for you.

Every provider returns a ``GateDecision`` or raises ``ProviderError``
(transport / 5xx → the HTTP layer answers 503 so the app retries) or
``ProviderBadAnswer`` (unusable output → the app falls back).
"""
from __future__ import annotations

import json
import os
from typing import Any, Protocol

import httpx

from .prompt import TOOL_NAME, decision_schema, system_prompt, user_prompt
from .schema import GateDecision, GateRequest


class ProviderError(Exception):
    """Transient: network, 429, 5xx."""


class ProviderBadAnswer(Exception):
    """Permanent for this request: model didn't call the tool / bad JSON."""


class Provider(Protocol):
    name: str

    async def decide(self, req: GateRequest, extra_context: dict[str, Any]) -> GateDecision: ...


def _payload(req: GateRequest, extra: dict[str, Any]) -> str:
    return user_prompt(req, extra)


async def _post(client: httpx.AsyncClient, url: str, **kw: Any) -> dict[str, Any]:
    try:
        r = await client.post(url, timeout=20.0, **kw)
    except httpx.HTTPError as e:  # DNS, connect, read timeouts…
        raise ProviderError(str(e)) from e
    if r.status_code == 429 or r.status_code >= 500:
        raise ProviderError(f"HTTP {r.status_code}")
    if r.status_code >= 400:
        raise ProviderBadAnswer(f"HTTP {r.status_code}: {r.text[:200]}")
    return r.json()


def _finish(args: dict[str, Any], model: str) -> GateDecision:
    try:
        conf = float(args.get("confidence", 0))
    except (TypeError, ValueError):
        conf = 0.0
    return GateDecision(
        candidate_id=str(args.get("candidate_id", "")),
        confidence=min(1.0, max(0.0, conf)),
        reason=str(args.get("reason", "")),
        model=model,
    )


class OpenAICompatible:
    """OpenAI, Groq, Mistral, Together, OpenRouter, Ollama, vLLM …"""

    name = "openai"

    def __init__(self, api_key: str, model: str, base_url: str = "https://api.openai.com/v1", client: httpx.AsyncClient | None = None):
        self.api_key, self.model, self.base_url = api_key, model, base_url.rstrip("/")
        self.client = client or httpx.AsyncClient()

    async def decide(self, req: GateRequest, extra_context: dict[str, Any]) -> GateDecision:
        body = {
            "model": self.model,
            "temperature": 0,
            "messages": [
                {"role": "system", "content": system_prompt(req)},
                {"role": "user", "content": _payload(req, extra_context)},
            ],
            "tools": [{
                "type": "function",
                "function": {"name": TOOL_NAME, "description": "Select the next page.", "strict": True, "parameters": decision_schema(req)},
            }],
            "tool_choice": {"type": "function", "function": {"name": TOOL_NAME}},
        }
        data = await _post(self.client, f"{self.base_url}/chat/completions", json=body,
                           headers={"authorization": f"Bearer {self.api_key}"})
        try:
            call = data["choices"][0]["message"]["tool_calls"][0]["function"]
            if call["name"] != TOOL_NAME:
                raise KeyError(call["name"])
            return _finish(json.loads(call["arguments"]), self.model)
        except (KeyError, IndexError, TypeError, json.JSONDecodeError) as e:
            raise ProviderBadAnswer(f"unexpected OpenAI response: {e}") from e


class Anthropic:
    name = "anthropic"

    def __init__(self, api_key: str, model: str, client: httpx.AsyncClient | None = None):
        self.api_key, self.model = api_key, model
        self.client = client or httpx.AsyncClient()

    async def decide(self, req: GateRequest, extra_context: dict[str, Any]) -> GateDecision:
        body = {
            "model": self.model,
            "max_tokens": 300,
            "temperature": 0,
            "system": system_prompt(req),
            "messages": [{"role": "user", "content": _payload(req, extra_context)}],
            "tools": [{"name": TOOL_NAME, "description": "Select the next page.", "input_schema": decision_schema(req)}],
            "tool_choice": {"type": "tool", "name": TOOL_NAME},
        }
        data = await _post(self.client, "https://api.anthropic.com/v1/messages", json=body,
                           headers={"x-api-key": self.api_key, "anthropic-version": "2023-06-01"})
        try:
            block = next(b for b in data["content"] if b.get("type") == "tool_use" and b.get("name") == TOOL_NAME)
            return _finish(block["input"], self.model)
        except (KeyError, StopIteration, TypeError) as e:
            raise ProviderBadAnswer(f"unexpected Anthropic response: {e}") from e


class Gemini:
    name = "gemini"

    def __init__(self, api_key: str, model: str, client: httpx.AsyncClient | None = None):
        self.api_key, self.model = api_key, model
        self.client = client or httpx.AsyncClient()

    async def decide(self, req: GateRequest, extra_context: dict[str, Any]) -> GateDecision:
        schema = dict(decision_schema(req))
        schema.pop("additionalProperties", None)  # Gemini rejects it
        body = {
            "system_instruction": {"parts": [{"text": system_prompt(req)}]},
            "contents": [{"role": "user", "parts": [{"text": _payload(req, extra_context)}]}],
            "tools": [{"function_declarations": [{"name": TOOL_NAME, "description": "Select the next page.", "parameters": schema}]}],
            "tool_config": {"function_calling_config": {"mode": "ANY", "allowed_function_names": [TOOL_NAME]}},
        }
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent?key={self.api_key}"
        data = await _post(self.client, url, json=body)
        try:
            parts = data["candidates"][0]["content"]["parts"]
            call = next(p["functionCall"] for p in parts if "functionCall" in p)
            return _finish(call["args"], self.model)
        except (KeyError, IndexError, StopIteration, TypeError) as e:
            raise ProviderBadAnswer(f"unexpected Gemini response: {e}") from e


def provider_from_env() -> Provider | None:
    """Pick a provider from environment. ``None`` → rules-only mode."""
    kind = os.getenv("AGENT_GATE_PROVIDER", "openai").lower()
    if kind == "openai" and os.getenv("OPENAI_API_KEY"):
        return OpenAICompatible(os.environ["OPENAI_API_KEY"], os.getenv("MODEL", "gpt-4o-mini"),
                                os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1"))
    if kind == "anthropic" and os.getenv("ANTHROPIC_API_KEY"):
        return Anthropic(os.environ["ANTHROPIC_API_KEY"], os.getenv("MODEL", "claude-sonnet-5"))
    if kind == "gemini" and os.getenv("GEMINI_API_KEY"):
        return Gemini(os.environ["GEMINI_API_KEY"], os.getenv("MODEL", "gemini-2.5-flash"))
    return None
