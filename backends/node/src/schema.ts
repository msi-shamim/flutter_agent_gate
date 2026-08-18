/**
 * Wire schema for `agent_gate/v1`.
 *
 * Mirrors `GateRequest.toJson()` / `GateDecision.fromJson()` in the Flutter
 * package. Keep the two in sync — the Flutter side is the source of truth.
 * We validate strictly enough to reject garbage but stay permissive on
 * `context.app`, which is free-form by design.
 */
import { z } from "zod";

export const CandidateSchema = z.object({
  id: z.string().min(1),
  label: z.string(),
  description: z.string(),
  route: z.string().optional(),
  tags: z.array(z.string()).optional(),
  priority: z.number().int().optional(),
  metadata: z.record(z.unknown()).optional(),
});

export const PageSummarySchema = z.object({
  page: z.string(),
  entered_at: z.string().optional(),
  dwell_ms: z.number().optional(),
  taps: z.number().optional(),
  attempts: z.number().optional(),
  failures: z.number().optional(),
  successes: z.number().optional(),
  validation_errors: z.number().optional(),
  backs: z.number().optional(),
  field_edits: z.number().optional(),
  max_scroll: z.number().optional(),
  hesitation_ms: z.number().optional(),
  attempts_by_name: z.record(z.number()).optional(),
  taps_by_target: z.record(z.number()).optional(),
  events: z.number().optional(),
});

export const ContextSchema = z.object({
  consent: z.boolean().default(false),
  current_page: PageSummarySchema.optional(),
  history: z.array(PageSummarySchema).optional(),
  events: z.array(z.unknown()).optional(),
  app: z.record(z.unknown()).default({}),
  baseline: z.record(z.unknown()).optional(),
  device: z.record(z.unknown()).optional(),
});

export const GateRequestSchema = z.object({
  schema: z.literal("agent_gate/v1"),
  request_id: z.string().min(1),
  timestamp: z.string(),
  gate_id: z.string().min(1),
  from_page: z.string(),
  profile: z.enum(["risk", "recommendation", "general"]),
  instructions: z.string().optional(),
  candidates: z.array(CandidateSchema).min(1).max(1000),
  context: ContextSchema,
});

export type GateRequest = z.infer<typeof GateRequestSchema>;
export type Candidate = z.infer<typeof CandidateSchema>;

/** What we send back. Matches `GateDecision.fromJson`. */
export interface GateDecision {
  candidate_id: string;
  confidence: number; // 0..1
  reason: string;
  model?: string;
}
