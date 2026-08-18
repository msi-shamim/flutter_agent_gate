import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";
import { decide, ModelUnavailable } from "../src/decide.js";
import type { ModelDeps } from "../src/model.js";
import type { GateRequest } from "../src/schema.js";
import { createApp } from "../src/server.js";
import { verifySignature } from "../src/signature.js";

/** A minimal, valid agent_gate/v1 request. */
function req(over: Partial<GateRequest> = {}): GateRequest {
  return {
    schema: "agent_gate/v1",
    request_id: "r1",
    timestamp: new Date().toISOString(),
    gate_id: "transfer_to_confirm",
    from_page: "transfer",
    profile: "risk",
    candidates: [
      { id: "confirm_simple", label: "Simple", description: "biometric only", tags: ["low_friction", "default"] },
      { id: "confirm_stepup", label: "Step-up", description: "otp", tags: ["protective"] },
    ],
    context: { consent: true, app: { amount: 100 } },
    ...over,
  };
}

/** Fake OpenAI client that returns a canned tool call. */
function fakeModel(candidateId: string, extra: Partial<{ throws: boolean }> = {}): ModelDeps {
  return {
    model: "fake-model",
    client: {
      chat: {
        completions: {
          create: async () => {
            if (extra.throws) throw new Error("ECONNRESET");
            return {
              choices: [
                {
                  message: {
                    tool_calls: [
                      {
                        function: {
                          name: "choose_next_page",
                          arguments: JSON.stringify({ candidate_id: candidateId, confidence: 0.8, reason: "fake" }),
                        },
                      },
                    ],
                  },
                },
              ],
            };
          },
        },
      },
    } as unknown as ModelDeps["client"],
  };
}

describe("decide()", () => {
  it("rules win before the model on risk gates", async () => {
    const d = await decide(req({ context: { consent: true, app: { amount: 9000 } } }), {
      model: fakeModel("confirm_simple"),
    });
    expect(d.candidate_id).toBe("confirm_stepup");
    expect(d.reason).toMatch(/rule:amount_over/);
  });

  it("uses the model when no rule matches", async () => {
    const audits: unknown[] = [];
    const d = await decide(req(), { model: fakeModel("confirm_simple"), audit: (r) => void audits.push(r) });
    expect(d.candidate_id).toBe("confirm_simple");
    expect(d.model).toBe("fake-model");
    expect(audits).toHaveLength(1);
  });

  it("rejects unknown ids from the model (defence in depth)", async () => {
    const d = await decide(req(), { model: fakeModel("evil_page") });
    expect(d.candidate_id).toBe("confirm_simple"); // tagged default
    expect(d.confidence).toBe(0);
    expect(d.reason).toMatch(/unknown id/);
  });

  it("rules-only mode answers with confidence 0", async () => {
    const d = await decide(req(), { model: null });
    expect(d.confidence).toBe(0);
    expect(d.reason).toMatch(/rules-only/);
  });

  it("maps transport failures to ModelUnavailable", async () => {
    await expect(decide(req(), { model: fakeModel("x", { throws: true }) })).rejects.toBeInstanceOf(ModelUnavailable);
  });
});

describe("verifySignature()", () => {
  const secret = "s3cret";
  const body = '{"a":1}';
  const sign = (ts: number) => "sha256=" + createHmac("sha256", secret).update(`${ts}.${body}`).digest("hex");

  it("accepts a fresh, correct signature", () => {
    const ts = 1_000_000;
    const r = verifySignature(body, { "x-agentgate-timestamp": String(ts), "x-agentgate-signature": sign(ts) }, { secret, now: () => ts + 10 });
    expect(r.ok).toBe(true);
  });

  it("rejects replayed timestamps and bad signatures", () => {
    const ts = 1_000_000;
    expect(verifySignature(body, { "x-agentgate-timestamp": String(ts), "x-agentgate-signature": sign(ts) }, { secret, now: () => ts + 10 * 60_000 }).ok).toBe(false);
    expect(verifySignature(body, { "x-agentgate-timestamp": String(ts), "x-agentgate-signature": "sha256=deadbeef" }, { secret, now: () => ts }).ok).toBe(false);
  });
});

describe("HTTP", () => {
  it("POST /agent-gate/decide returns a decision and 400 on junk", async () => {
    const app = createApp({ model: fakeModel("confirm_simple"), audit: () => {} });
    const server = app.listen(0);
    const port = (server.address() as { port: number }).port;
    try {
      const ok = await fetch(`http://127.0.0.1:${port}/agent-gate/decide`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(req()),
      });
      expect(ok.status).toBe(200);
      const body = (await ok.json()) as { candidate_id: string };
      expect(body.candidate_id).toBe("confirm_simple");

      const bad = await fetch(`http://127.0.0.1:${port}/agent-gate/decide`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ schema: "nope" }),
      });
      expect(bad.status).toBe(400);
    } finally {
      server.close();
    }
  });

  it("returns 503 when the model is unavailable so the app retries", async () => {
    const app = createApp({ model: fakeModel("x", { throws: true }), audit: () => {} });
    const server = app.listen(0);
    const port = (server.address() as { port: number }).port;
    try {
      const r = await fetch(`http://127.0.0.1:${port}/agent-gate/decide`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(req()),
      });
      expect(r.status).toBe(503);
    } finally {
      server.close();
    }
  });
});
