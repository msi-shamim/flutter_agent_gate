/**
 * Model call — OpenAI-compatible chat completions with a *forced*,
 * enum-constrained tool call. This mirrors `PromptBuilder.openAiRequest`
 * in the Flutter package so the two never drift on prompt semantics.
 *
 * Provider-agnostic on purpose: set OPENAI_BASE_URL to Groq / Mistral /
 * Together / OpenRouter / Ollama etc. Swapping to Anthropic or Gemini is a
 * ~15 line change (see the Python sample for a multi-provider layout).
 */
import OpenAI from "openai";
import type { GateDecision, GateRequest } from "./schema.js";

export const TOOL_NAME = "choose_next_page";

export function systemPrompt(req: GateRequest): string {
  const lines = [
    `You are a navigation decision engine inside a mobile application. The user is leaving page "${req.from_page}". You must pick exactly one of the candidate next pages by calling the tool "${TOOL_NAME}".`,
    "",
    "Rules:",
    "- Choose ONLY from the provided candidate ids.",
    "- Base your choice on the behavioural context, the population baseline (if present) and the app context.",
    "- Explain the reason briefly and truthfully; it may be shown to the user and stored for audit.",
    "- If the context is insufficient, pick the safest / most neutral candidate and give a low confidence.",
  ];
  if (req.profile === "risk") {
    lines.push(
      "- This is a RISK decision. Prefer protective outcomes (verification, review, safe defaults) when signals are anomalous. Never route to a less-protected page on weak evidence.",
    );
  } else if (req.profile === "recommendation") {
    lines.push(
      "- This is a RECOMMENDATION decision. Optimise for the user's stated and inferred goals; do not pressure or mislead.",
    );
  }
  if (req.instructions) lines.push("", "Developer instructions:", req.instructions);
  return lines.join("\n");
}

export function toolDefinition(req: GateRequest) {
  return {
    type: "function" as const,
    function: {
      name: TOOL_NAME,
      description: "Select the next page for the user.",
      strict: true,
      parameters: {
        type: "object",
        additionalProperties: false,
        required: ["candidate_id", "confidence", "reason"],
        properties: {
          candidate_id: {
            type: "string",
            description: "The id of the single best candidate page.",
            enum: req.candidates.map((c) => c.id),
          },
          confidence: { type: "number", description: "0..1" },
          reason: { type: "string", description: "One or two plain sentences." },
        },
      },
    },
  };
}

export interface ModelDeps {
  client: Pick<OpenAI, "chat">;
  model: string;
}

export function makeOpenAIClient(): ModelDeps | null {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) return null;
  return {
    client: new OpenAI({ apiKey, baseURL: process.env.OPENAI_BASE_URL || undefined }),
    model: process.env.MODEL || "gpt-4o-mini",
  };
}

/**
 * Ask the model. Throws on transport errors (caller maps to 5xx so the app
 * retries) and on unusable output (caller maps to fallback).
 */
export async function askModel(
  deps: ModelDeps,
  req: GateRequest,
  extraContext: Record<string, unknown> = {},
): Promise<GateDecision> {
  const userPayload = {
    candidates: req.candidates,
    context: { ...req.context, ...extraContext },
  };
  const completion = await deps.client.chat.completions.create({
    model: deps.model,
    temperature: 0,
    messages: [
      { role: "system", content: systemPrompt(req) },
      { role: "user", content: `${JSON.stringify(userPayload, null, 2)}\n\nCall ${TOOL_NAME} now.` },
    ],
    tools: [toolDefinition(req)],
    tool_choice: { type: "function", function: { name: TOOL_NAME } },
  });

  const call = completion.choices[0]?.message?.tool_calls?.[0];
  if (!call || call.function.name !== TOOL_NAME) {
    throw new Error("model did not call the tool");
  }
  const args = JSON.parse(call.function.arguments) as GateDecision;
  return {
    candidate_id: String(args.candidate_id),
    confidence: Math.min(1, Math.max(0, Number(args.confidence ?? 0))),
    reason: String(args.reason ?? ""),
    model: deps.model,
  };
}
