/**
 * The decision pipeline, framework-free so it is unit-testable without HTTP:
 *
 *   validate → rules → (baseline enrichment) → model → validate answer → audit
 *
 * Contract with the app (mirrors AgentGate's own checks, defence in depth):
 *   - the returned candidate_id MUST be one of req.candidates
 *   - confidence is clamped to 0..1
 *   - on any model failure we return `null` and let the HTTP layer answer 5xx
 *     (transient → the app retries) or a fallback body (permanent).
 */
import { askModel, type ModelDeps } from "./model.js";
import { runRules, type Rule } from "./rules.js";
import type { GateDecision, GateRequest } from "./schema.js";

export interface AuditRecord {
  request_id: string;
  gate_id: string;
  profile: string;
  decision: GateDecision;
  source: "rule" | "model" | "fallback";
  latency_ms: number;
  at: string;
}

export interface DecideDeps {
  model: ModelDeps | null; // null → rules only
  rules?: Rule[];
  /** Population baseline for a page — from your warehouse. Stub returns none. */
  baselineFor?: (page: string) => Promise<Record<string, unknown> | undefined>;
  audit?: (rec: AuditRecord) => void | Promise<void>;
  now?: () => number;
}

export class ModelUnavailable extends Error {}

export async function decide(req: GateRequest, deps: DecideDeps): Promise<GateDecision> {
  const now = deps.now ?? Date.now;
  const start = now();
  const finish = async (decision: GateDecision, source: AuditRecord["source"]) => {
    await deps.audit?.({
      request_id: req.request_id,
      gate_id: req.gate_id,
      profile: req.profile,
      decision,
      source,
      latency_ms: now() - start,
      at: new Date(now()).toISOString(),
    });
    return decision;
  };

  // 1. Rules — deterministic floor.
  const ruled = runRules(req, deps.rules);
  if (ruled) return finish(ruled, "rule");

  // 2. No model configured → tell the app to use its fallback. We answer with
  //    the first candidate tagged `default` if any (so the app still gets a
  //    valid id), otherwise the first candidate, at confidence 0.
  if (!deps.model) {
    const c = req.candidates.find((x) => x.tags?.includes("default")) ?? req.candidates[0];
    return finish(
      { candidate_id: c.id, confidence: 0, reason: "no model configured (rules-only mode)" },
      "fallback",
    );
  }

  // 3. Enrich with server-side knowledge the device cannot have.
  const baseline = await deps.baselineFor?.(req.from_page);

  // 4. Model. Transport errors propagate as ModelUnavailable → HTTP 503.
  let answer: GateDecision;
  try {
    answer = await askModel(deps.model, req, baseline ? { baseline } : {});
  } catch (e) {
    throw new ModelUnavailable((e as Error).message);
  }

  // 5. Defence in depth: never return an id the app did not offer.
  if (!req.candidates.some((c) => c.id === answer.candidate_id)) {
    const c = req.candidates.find((x) => x.tags?.includes("default")) ?? req.candidates[0];
    return finish(
      { candidate_id: c.id, confidence: 0, reason: `model returned unknown id "${answer.candidate_id}"`, model: answer.model },
      "fallback",
    );
  }
  return finish(answer, "model");
}
