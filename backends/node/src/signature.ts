/**
 * Verifies the optional HMAC the Flutter `HttpDecider(signingSecret: …)` adds:
 *
 *   X-AgentGate-Timestamp: <ms since epoch>
 *   X-AgentGate-Signature: sha256=<hex hmac_sha256(secret, `${ts}.${rawBody}`)>
 *
 * Reminder (also in the app docs): the secret ships inside the app binary, so
 * this is *tamper-evidence*, not authentication. Pair with platform
 * attestation (App Attest / Play Integrity) and normal user auth for anything
 * fraud-related.
 */
import { createHmac, timingSafeEqual } from "node:crypto";

export interface VerifyOptions {
  secret: string;
  replayWindowMs?: number;
  now?: () => number;
}

export function verifySignature(
  rawBody: string,
  headers: Record<string, string | string[] | undefined>,
  opts: VerifyOptions,
): { ok: true } | { ok: false; reason: string } {
  const ts = first(headers["x-agentgate-timestamp"]);
  const sig = first(headers["x-agentgate-signature"]);
  if (!ts || !sig) return { ok: false, reason: "missing signature headers" };

  const tsNum = Number(ts);
  const now = (opts.now ?? Date.now)();
  const window = opts.replayWindowMs ?? 5 * 60_000;
  if (!Number.isFinite(tsNum) || Math.abs(now - tsNum) > window) {
    return { ok: false, reason: "timestamp outside replay window" };
  }

  const expected = "sha256=" + createHmac("sha256", opts.secret).update(`${ts}.${rawBody}`).digest("hex");
  const a = Buffer.from(expected);
  const b = Buffer.from(sig);
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    return { ok: false, reason: "signature mismatch" };
  }
  return { ok: true };
}

const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);
