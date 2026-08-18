"""
Decision pipeline, framework-free so it is unit-testable without HTTP:

    validate → rules → baseline enrichment → provider → validate answer → audit

Contract with the app (mirrors AgentGate's own checks — defence in depth):
- returned ``candidate_id`` MUST be one of ``req.candidates``;
- confidence is clamped to 0..1;
- transient provider failures propagate as ``ProviderError`` (→ HTTP 503 so
  the app retries); unusable answers become a confidence-0 fallback.
"""
from __future__ import annotations

import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from typing import Any

from .providers import Provider, ProviderBadAnswer, ProviderError
from .rules import Rule, run_rules
from .schema import GateDecision, GateRequest

Baseline = Callable[[str], Awaitable[dict[str, Any] | None]]
Audit = Callable[[dict[str, Any]], None]


@dataclass
class DecideDeps:
    provider: Provider | None = None            # None → rules-only mode
    rules: list[Rule] | None = None
    baseline_for: Baseline | None = None
    audit: Audit = field(default=lambda rec: None)


async def decide(req: GateRequest, deps: DecideDeps) -> GateDecision:
    start = time.monotonic()

    def finish(d: GateDecision, source: str) -> GateDecision:
        deps.audit({
            "request_id": req.request_id,
            "gate_id": req.gate_id,
            "profile": req.profile,
            "decision": d.model_dump(exclude_none=True),
            "source": source,
            "latency_ms": int((time.monotonic() - start) * 1000),
        })
        return d

    # 1. Rules — deterministic floor.
    ruled = run_rules(req, deps.rules)
    if ruled:
        return finish(ruled, "rule")

    # 2. No provider → tell the app to use its fallback (valid id, confidence 0).
    if deps.provider is None:
        c = req.default_candidate()
        return finish(GateDecision(candidate_id=c.id, confidence=0.0, reason="no provider configured (rules-only mode)"), "fallback")

    # 3. Server-side enrichment the device cannot be trusted with.
    extra: dict[str, Any] = {}
    if deps.baseline_for is not None:
        baseline = await deps.baseline_for(req.from_page)
        if baseline:
            extra["baseline"] = baseline

    # 4. Provider.
    try:
        answer = await deps.provider.decide(req, extra)
    except ProviderBadAnswer as e:
        c = req.default_candidate()
        return finish(GateDecision(candidate_id=c.id, confidence=0.0, reason=f"provider answer unusable: {e}"), "fallback")
    except ProviderError:
        raise  # HTTP layer → 503

    # 5. Defence in depth.
    if not req.has(answer.candidate_id):
        c = req.default_candidate()
        return finish(GateDecision(candidate_id=c.id, confidence=0.0, reason=f'model returned unknown id "{answer.candidate_id}"', model=answer.model), "fallback")
    return finish(answer, "model")
