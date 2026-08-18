/**
 * HTTP layer. Thin by design: parse → verify → decide → map errors to status
 * codes the Flutter `HttpDecider` understands:
 *
 *   200  { candidate_id, confidence, reason, model? }   → used (after app-side checks)
 *   400  invalid body / bad signature                    → app falls back, no retry
 *   503  model transport failure                         → app retries then falls back
 */
import express, { type Request, type Response } from "express";
import { decide, ModelUnavailable, type AuditRecord } from "./decide.js";
import { makeOpenAIClient } from "./model.js";
import { GateRequestSchema } from "./schema.js";
import { verifySignature } from "./signature.js";

export function createApp(opts?: {
  signingSecret?: string;
  replayWindowMs?: number;
  model?: ReturnType<typeof makeOpenAIClient>;
  audit?: (r: AuditRecord) => void;
}) {
  const app = express();
  // Keep the raw body: HMAC must be computed over the exact bytes sent.
  app.use(
    express.json({
      limit: "256kb",
      verify: (req, _res, buf) => {
        (req as Request & { rawBody?: string }).rawBody = buf.toString("utf8");
      },
    }),
  );

  const model = opts?.model === undefined ? makeOpenAIClient() : opts.model;
  const audit = opts?.audit ?? ((r: AuditRecord) => console.log(JSON.stringify({ audit: r })));

  app.get("/healthz", (_req, res) => res.json({ ok: true, mode: model ? "model" : "rules-only" }));

  app.post("/agent-gate/decide", async (req: Request & { rawBody?: string }, res: Response) => {
    if (opts?.signingSecret) {
      const v = verifySignature(req.rawBody ?? "", req.headers, {
        secret: opts.signingSecret,
        replayWindowMs: opts.replayWindowMs,
      });
      if (!v.ok) return res.status(400).json({ error: v.reason });
    }

    const parsed = GateRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: "invalid agent_gate/v1 payload", issues: parsed.error.issues });
    }

    try {
      const decision = await decide(parsed.data, { model, audit });
      res.setHeader("x-agentgate-request-id", parsed.data.request_id);
      return res.json(decision);
    } catch (e) {
      if (e instanceof ModelUnavailable) return res.status(503).json({ error: "model unavailable" });
      console.error(e);
      return res.status(500).json({ error: "internal" });
    }
  });

  return app;
}

// Only start listening when run directly (not when imported by tests).
if (process.argv[1] && /server\.(ts|js)$/.test(process.argv[1])) {
  const port = Number(process.env.PORT ?? 8787);
  createApp({
    signingSecret: process.env.AGENT_GATE_SIGNING_SECRET || undefined,
    replayWindowMs: Number(process.env.AGENT_GATE_REPLAY_WINDOW_MS ?? 300000),
  }).listen(port, () => console.log(`agent_gate/v1 decide endpoint on :${port}`));
}
