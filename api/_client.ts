import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod";
import { createHash } from "node:crypto";
import { ResponseCache } from "./_cache";

export const DEFAULT_COACH_MODEL = "claude-opus-5";

/**
 * `??` would not catch this: an unset key in a .env file arrives as an empty
 * string rather than undefined, and an empty model is a 400.
 */
export function resolveCoachModel(value: string | undefined): string {
  return value?.trim() || DEFAULT_COACH_MODEL;
}

const TextSchema = z.object({
  text: z.string().describe("The reply, addressed to the player."),
});

export type GenerateOutcome =
  { ok: true; text: string } | { ok: false; reason: string };

const responses = new ResponseCache<GenerateOutcome>();

/**
 * One constrained call. Every caller supplies its own guard, because what
 * counts as an unusable answer differs per task, and every caller has a
 * deterministic thing to show when the answer is rejected.
 */
export async function generate(options: {
  apiKey: string | undefined;
  system: string;
  input: string;
  maxTokens?: number;
  /** Returns a reason string to reject, or null to accept. */
  reject: (text: string) => string | null;
}): Promise<GenerateOutcome> {
  if (!options.apiKey) return { ok: false, reason: "no-api-key" };
  const started = performance.now();
  const model = resolveCoachModel(process.env.COACH_MODEL);
  const maxTokens = options.maxTokens ?? 600;
  const key = createHash("sha256")
    .update(
      JSON.stringify([
        model,
        options.system,
        options.input,
        maxTokens,
        createHash("sha256").update(options.apiKey).digest("hex"),
      ]),
    )
    .digest("hex");
  try {
    const result = await responses.get(
      key,
      async (): Promise<GenerateOutcome> => {
        try {
          const client = new Anthropic({
            apiKey: options.apiKey,
            timeout: 6000,
            maxRetries: 0,
          });
          const response = await client.messages.parse({
            model,
            max_tokens: maxTokens,
            // These are short, constrained rewrites. Low effort keeps the demo
            // responsive; thinking is on by default on this model.
            output_config: {
              effort: "low",
              format: zodOutputFormat(TextSchema),
            },
            system: options.system,
            messages: [{ role: "user", content: options.input }],
          });
          // The model occasionally uses a line break as punctuation. In a paragraph
          // that collapses to a space and reads as a dropped word, so flatten it.
          const text = response.parsed_output?.text
            ?.replace(/\s+/g, " ")
            .trim();
          if (!text) return { ok: false, reason: "unparsed" };
          const rejection = options.reject(text);
          if (rejection) return { ok: false, reason: rejection };
          return { ok: true, text };
        } catch (error) {
          const reason =
            error instanceof Anthropic.APIConnectionTimeoutError
              ? "timeout"
              : error instanceof Anthropic.APIError
                ? `api-${error.status}`
                : "network";
          return { ok: false, reason };
        }
      },
      (value) => value.ok,
    );
    // Reapply the caller's guard even to cached text.
    const rejection = result.value.ok
      ? options.reject(result.value.text)
      : null;
    const value: GenerateOutcome = rejection
      ? { ok: false, reason: rejection }
      : result.value;
    console.info(
      JSON.stringify({
        event: "ai-generation",
        cache: result.status,
        ms: Math.round(performance.now() - started),
        ok: value.ok,
        reason: value.ok ? undefined : value.reason,
        model,
      }),
    );
    return value;
  } catch (error) {
    const reason =
      error instanceof Error && error.message === "busy" ? "busy" : "network";
    return { ok: false, reason };
  }
}
