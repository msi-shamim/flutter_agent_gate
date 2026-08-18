"""
Wire schema for ``agent_gate/v1``.

Mirrors ``GateRequest.toJson()`` / ``GateDecision.fromJson()`` in the Flutter
package (the source of truth). Strict where it matters (schema tag, candidate
ids, profile), permissive on ``context.app`` which is free-form by design.
"""
from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field, conlist


class Candidate(BaseModel):
    id: str = Field(min_length=1)
    label: str
    description: str
    route: str | None = None
    tags: list[str] = []
    priority: int = 0
    metadata: dict[str, Any] = {}


class PageSummary(BaseModel):
    page: str
    dwell_ms: int = 0
    taps: int = 0
    attempts: int = 0
    failures: int = 0
    successes: int = 0
    validation_errors: int = 0
    backs: int = 0
    field_edits: int = 0
    max_scroll: float = 0.0
    hesitation_ms: int | None = None
    attempts_by_name: dict[str, int] = {}
    taps_by_target: dict[str, int] = {}
    events: int = 0
    entered_at: str | None = None


class Context(BaseModel):
    consent: bool = False
    current_page: PageSummary | None = None
    history: list[PageSummary] = []
    events: list[Any] = []
    app: dict[str, Any] = {}
    baseline: dict[str, Any] | None = None
    device: dict[str, Any] = {}


class GateRequest(BaseModel):
    schema_: Literal["agent_gate/v1"] = Field(alias="schema")
    request_id: str = Field(min_length=1)
    timestamp: str
    gate_id: str = Field(min_length=1)
    from_page: str
    profile: Literal["risk", "recommendation", "general"]
    instructions: str | None = None
    candidates: conlist(Candidate, min_length=1, max_length=1000)  # type: ignore[valid-type]
    context: Context = Context()

    model_config = {"populate_by_name": True}

    def candidate_ids(self) -> list[str]:
        return [c.id for c in self.candidates]

    def has(self, cid: str) -> bool:
        return any(c.id == cid for c in self.candidates)

    def by_tag(self, tag: str) -> Candidate | None:
        return next((c for c in self.candidates if tag in c.tags), None)

    def default_candidate(self) -> Candidate:
        """First candidate tagged ``default`` (highest priority), else the first."""
        tagged = sorted((c for c in self.candidates if "default" in c.tags), key=lambda c: -c.priority)
        return tagged[0] if tagged else self.candidates[0]


class GateDecision(BaseModel):
    candidate_id: str
    confidence: float = Field(ge=0.0, le=1.0)
    reason: str
    model: str | None = None
