import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod";
import {
  COACH_SYSTEM_PROMPT,
  buildCoachInput,
  isUsableRewrite,
} from "../src/focus/coachPrompt";
import type { FocusAssessment } from "../src/contracts/assessment";

/**
 * Holds the API key so the browser never does.
 *
 * The bundle this app ships is static, and the iOS build serves it from a
 * local file server, so anything the client can read ends up in a file a user
 * can open. The key stays here and the client sends an assessment instead.
 */

const CoachSchema = z.object({
  detail: z
    .string()
    .describe("One or two short sentences of coaching, addressed to the player."),
});

/** Shape the client expects back, whether or not the model ran. */
export interface CoachResponse {
  detail: string;
  rewritten: boolean;
  /** Why the rewrite was not used. Absent on success. */
  reason?: string;
}

export async function rewriteCoaching(
  assessment: FocusAssessment,
  apiKey: string | undefined,
): Promise<CoachResponse> {
  const fallback = assessment.nextAction.detail;
  if (!apiKey) {
    return { detail: fallback, rewritten: false, reason: "no-api-key" };
  }

  const input = buildCoachInput(assessment);
  try {
    const client = new Anthropic({ apiKey });
    const response = await client.messages.parse({
      model: "claude-opus-5",
      max_tokens: 400,
      // A one-sentence rewrite needs no depth, and low effort keeps the demo
      // responsive. Thinking is on by default on this model.
      output_config: {
        effort: "low",
        format: zodOutputFormat(CoachSchema),
      },
      system: COACH_SYSTEM_PROMPT,
      messages: [{ role: "user", content: input }],
    });

    const parsed = response.parsed_output;
    if (!parsed) {
      return { detail: fallback, rewritten: false, reason: "unparsed" };
    }
    if (!isUsableRewrite(parsed.detail, assessment, input)) {
      return { detail: fallback, rewritten: false, reason: "rejected" };
    }
    return { detail: parsed.detail.trim(), rewritten: true };
  } catch (error) {
    // A missing coach line is worse than a stiff one. Never surface the error
    // to the player; the deterministic sentence is already correct.
    const reason =
      error instanceof Anthropic.APIError ? `api-${error.status}` : "network";
    return { detail: fallback, rewritten: false, reason };
  }
}

export default async function handler(request: Request): Promise<Response> {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  let assessment: FocusAssessment;
  try {
    assessment = (await request.json()) as FocusAssessment;
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }
  if (!assessment?.nextAction?.detail) {
    return new Response(
      JSON.stringify({ error: "Body must be a FocusAssessment" }),
      { status: 400, headers: { "content-type": "application/json" } },
    );
  }
  const result = await rewriteCoaching(
    assessment,
    process.env.ANTHROPIC_API_KEY,
  );
  return new Response(JSON.stringify(result), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}
