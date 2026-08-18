/**
 * Deterministic rules — the *floor* for risk gates.
 *
 * Why rules live on the server too (the app has `RuleDecider`): the app's
 * rules can be tampered with; the server's cannot. Put anything a compliance
 * team signed off on here, and let the model rank only what's left.
 *
 * A rule returns a decision or `null` ("not my business"). First match wins.
 */
import type { GateDecision, GateRequest } from "./schema.js";

export type Rule = (req: GateRequest) => GateDecision | null;

/** Helper: does the gate offer this candidate id? */
const has = (req: GateRequest, id: string) =>
  req.candidates.some((c) => c.id === id);

/** Helper: first candidate carrying a tag, if any. */
const byTag = (req: GateRequest, tag: string) =>
  req.candidates.find((c) => c.tags?.includes(tag));

export const defaultRules: Rule[] = [
  // 1. Risk gates: an explicit blocked/protective outcome always wins when
  //    the app context says so. Apps set `app.blocked = true` after their own
  //    KYC/sanctions checks; we never route a blocked user anywhere else.
  (req) => {
    if (req.profile !== "risk") return null;
    if (req.context.app["blocked"] !== true) return null;
    const c = byTag(req, "blocked") ?? byTag(req, "protective");
    return c
      ? { candidate_id: c.id, confidence: 1, reason: "rule:blocked_user" }
      : null;
  },

  // 2. Risk gates: amount over the hard limit → protective candidate.
  (req) => {
    if (req.profile !== "risk") return null;
    const amount = Number(req.context.app["amount"] ?? 0);
    const limit = Number(req.context.app["hard_limit"] ?? 5000);
    if (!(amount > limit)) return null;
    const c = byTag(req, "protective");
    return c
      ? { candidate_id: c.id, confidence: 1, reason: `rule:amount_over_${limit}` }
      : null;
  },

  // 3. Any gate: if consent is off AND there is no app context at all, we
  //    have nothing to reason about — pick the highest-priority candidate
  //    tagged `default` (or skip if none, so the caller's fallback applies).
  (req) => {
    const noSignal =
      !req.context.consent && Object.keys(req.context.app).length === 0;
    if (!noSignal) return null;
    const c = req.candidates
      .filter((x) => x.tags?.includes("default"))
      .sort((a, b) => (b.priority ?? 0) - (a.priority ?? 0))[0];
    return c && has(req, c.id)
      ? { candidate_id: c.id, confidence: 0.5, reason: "rule:no_signal_default" }
      : null;
  },
];

export function runRules(req: GateRequest, rules: Rule[] = defaultRules) {
  for (const rule of rules) {
    const d = rule(req);
    if (d) return d;
  }
  return null;
}
