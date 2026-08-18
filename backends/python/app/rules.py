"""
Deterministic rules — the *floor* for risk gates.

Server-side rules cannot be tampered with, unlike the app's ``RuleDecider``.
Put compliance-signed non-negotiables here; let the model rank the rest.
A rule returns a decision or ``None``; first match wins.
"""
from __future__ import annotations

from collections.abc import Callable

from .schema import GateDecision, GateRequest

Rule = Callable[[GateRequest], GateDecision | None]


def blocked_user(req: GateRequest) -> GateDecision | None:
    if req.profile != "risk" or req.context.app.get("blocked") is not True:
        return None
    c = req.by_tag("blocked") or req.by_tag("protective")
    return GateDecision(candidate_id=c.id, confidence=1.0, reason="rule:blocked_user") if c else None


def amount_over_limit(req: GateRequest) -> GateDecision | None:
    if req.profile != "risk":
        return None
    try:
        amount = float(req.context.app.get("amount", 0))
        limit = float(req.context.app.get("hard_limit", 5000))
    except (TypeError, ValueError):
        return None
    if amount <= limit:
        return None
    c = req.by_tag("protective")
    return GateDecision(candidate_id=c.id, confidence=1.0, reason=f"rule:amount_over_{int(limit)}") if c else None


def no_signal_default(req: GateRequest) -> GateDecision | None:
    if req.context.consent or req.context.app:
        return None
    tagged = [c for c in req.candidates if "default" in c.tags]
    if not tagged:
        return None
    c = max(tagged, key=lambda x: x.priority)
    return GateDecision(candidate_id=c.id, confidence=0.5, reason="rule:no_signal_default")


DEFAULT_RULES: list[Rule] = [blocked_user, amount_over_limit, no_signal_default]


def run_rules(req: GateRequest, rules: list[Rule] | None = None) -> GateDecision | None:
    for rule in rules if rules is not None else DEFAULT_RULES:
        d = rule(req)
        if d is not None:
            return d
    return None
