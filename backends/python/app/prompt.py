"""
Prompt + tool schema. Mirrors ``PromptBuilder`` in the Flutter package so the
model sees the same instructions whether you decide on-device or here.
"""
from __future__ import annotations

import json
from typing import Any

from .schema import GateRequest

TOOL_NAME = "choose_next_page"


def decision_schema(req: GateRequest) -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["candidate_id", "confidence", "reason"],
        "properties": {
            "candidate_id": {
                "type": "string",
                "description": "The id of the single best candidate page.",
                "enum": req.candidate_ids(),
            },
            "confidence": {"type": "number", "minimum": 0, "maximum": 1, "description": "How sure you are, 0..1."},
            "reason": {
                "type": "string",
                "description": "One or two sentences, plain language, truthful. May be shown to the user and stored for audit.",
            },
        },
    }


def system_prompt(req: GateRequest) -> str:
    lines = [
        f'You are a navigation decision engine inside a mobile application. The user is leaving page "{req.from_page}". '
        f'You must pick exactly one of the candidate next pages by calling the tool "{TOOL_NAME}".',
        "",
        "Rules:",
        "- Choose ONLY from the provided candidate ids.",
        "- Base your choice on the behavioural context, the population baseline (if present) and the app context.",
        "- Explain the reason briefly and truthfully.",
        "- If the context is insufficient, pick the safest / most neutral candidate and give a low confidence.",
    ]
    if req.profile == "risk":
        lines.append("- This is a RISK decision. Prefer protective outcomes (verification, review, safe defaults) when signals are anomalous. Never route to a less-protected page on weak evidence.")
    elif req.profile == "recommendation":
        lines.append("- This is a RECOMMENDATION decision. Optimise for the user's stated and inferred goals; do not pressure or mislead.")
    if req.instructions:
        lines += ["", "Developer instructions:", req.instructions]
    return "\n".join(lines)


def user_prompt(req: GateRequest, extra_context: dict[str, Any] | None = None) -> str:
    ctx = req.context.model_dump(exclude_none=True)
    if extra_context:
        ctx.update(extra_context)
    return (
        "Candidates:\n" + json.dumps([c.model_dump(exclude_none=True) for c in req.candidates], indent=2)
        + "\n\nContext:\n" + json.dumps(ctx, indent=2)
        + f"\n\nCall {TOOL_NAME} now."
    )
