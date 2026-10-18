import { jsonEndpoint } from "./_http";
import { isCoachRequest } from "./_validation";
import {
  INTERPRET_SYSTEM_PROMPT,
  buildInterpretationInput,
  isUsableInterpretation,
} from "../shared/focus/interpretation";
import type { ThrowRecord } from "../shared/throwEntry";
import {
  FIT_SYSTEM_PROMPT,
  buildFitInput,
  fitRejection,
  type FitInput,
} from "../shared/focus/fitPrompt";
import type { FocusAssessment } from "../shared/contracts/assessment";
import type { HandProfile } from "../shared/contracts/handProfile";
import type { GripPlan } from "../shared/contracts/gripPlan";
import { generate } from "./_client";

export { DEFAULT_COACH_MODEL, resolveCoachModel } from "./_client";

/**
 * Holds the API key so the browser never does.
 *
 * The bundle this app ships is static, and the iOS build serves it from a
 * local file server, so anything the client can read ends up in a file a user
 * can open. The key stays here and the client sends its data instead.
 */

export interface CoachRequestBody {
  assessment: FocusAssessment;
  /** Both optional: without them the fit explanation is simply absent. */
  profile?: HandProfile;
  plan?: GripPlan;
  throws?: ThrowRecord[];
}

export interface CoachResponse {
  detail: string;
  rewritten: boolean;
  /** How this hand meets this grip. Absent when there is nothing to say. */
  fit?: string;
  /** Why a part was not produced. Absent on full success. */
  reason?: string;
  fitReason?: string;
}

export async function rewriteCoaching(
  body: CoachRequestBody,
  apiKey: string | undefined,
): Promise<CoachResponse> {
  const { assessment, profile, plan } = body;
  const fallback = assessment.nextAction.detail;
  const coachInput = buildInterpretationInput(body);

  const fitContext: FitInput | null =
    profile && plan ? { assessment, profile, plan } : null;
  const fitInput = fitContext ? buildFitInput(fitContext) : null;

  // Both calls read the same already-decided assessment, so running them
  // together costs one round trip instead of two.
  const [rewrite, fit] = await Promise.all([
    generate({
      apiKey,
      system: INTERPRET_SYSTEM_PROMPT,
      input: coachInput,
      maxTokens: 400,
      reject: (text) =>
        isUsableInterpretation(text, coachInput) ? null : "rejected",
    }),
    fitContext && fitInput
      ? generate({
          apiKey,
          system: FIT_SYSTEM_PROMPT,
          input: fitInput,
          maxTokens: 300,
          reject: (text) => fitRejection(text, fitContext, fitInput),
        })
      : Promise.resolve({ ok: false as const, reason: "no-hand-data" }),
  ]);

  return {
    detail: rewrite.ok ? rewrite.text : fallback,
    rewritten: rewrite.ok,
    reason: rewrite.ok ? undefined : rewrite.reason,
    fit: fit.ok ? fit.text : undefined,
    fitReason: fit.ok ? undefined : fit.reason,
  };
}

export function handleCoachRequest(
  request: Request,
  apiKey: string | undefined,
): Promise<Response> {
  return jsonEndpoint(request, isCoachRequest, (body: CoachRequestBody) =>
    rewriteCoaching(body, apiKey),
  );
}

export default function handler(request: Request): Promise<Response> {
  return handleCoachRequest(request, process.env.ANTHROPIC_API_KEY);
}
