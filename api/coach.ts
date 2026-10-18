import { jsonEndpoint } from "./_http";
import { isCoachRequest } from "./_validation";
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
  /** Still accepted because the phone sends it. Fit reads the hand, not throws. */
  throws?: ThrowRecord[];
}

export interface CoachResponse {
  /** The engine's own sentence, passed through untouched. */
  detail: string;
  /**
   * Permanently false, and typed as such.
   *
   * Nothing rewrites `detail` any more, but the field has to keep being sent:
   * Swift's `CoachReply.rewritten` is a non-optional `Bool` with a synthesised
   * decoder, so dropping the key makes the whole reply fail to decode and the
   * fit explanation below would be lost with it. Retiring the field is the
   * Swift side's call, not ours.
   */
  rewritten: false;
  /** How this hand meets this grip. Absent when there is nothing to say. */
  fit?: string;
  /** Why the fit explanation was not produced. Absent on success. */
  fitReason?: string;
}

/**
 * Explains the hand fit. Nothing here writes coaching text.
 *
 * The coaching sentence used to be a model rewrite of a finding the engine had
 * already made. The engine now writes that sentence in full, so a rewrite can
 * only damage it, and the guard meant to protect it selected for vagueness: it
 * rejected a spin figure for carrying a comma, rejected the rule's own target,
 * and accepted a paragraph containing no numbers at all.
 *
 * Fit is a different question and keeps its call. It reads this player's
 * measured hand against this grip, which differs for every hand, pitch and
 * throw combination and is not something a rule table can hold.
 */
export async function explainFit(
  body: CoachRequestBody,
  apiKey: string | undefined,
): Promise<CoachResponse> {
  const { assessment, profile, plan } = body;
  const detail = assessment.nextAction.detail;

  const fitContext: FitInput | null =
    profile && plan ? { assessment, profile, plan } : null;
  if (!fitContext) {
    return { detail, rewritten: false, fitReason: "no-hand-data" };
  }

  const fitInput = buildFitInput(fitContext);
  const fit = await generate({
    apiKey,
    system: FIT_SYSTEM_PROMPT,
    input: fitInput,
    maxTokens: 300,
    reject: (text) => fitRejection(text, fitContext, fitInput),
  });

  return {
    detail,
    rewritten: false,
    fit: fit.ok ? fit.text : undefined,
    fitReason: fit.ok ? undefined : fit.reason,
  };
}

export function handleCoachRequest(
  request: Request,
  apiKey: string | undefined,
): Promise<Response> {
  return jsonEndpoint(request, isCoachRequest, (body: CoachRequestBody) =>
    explainFit(body, apiKey),
  );
}

export default function handler(request: Request): Promise<Response> {
  return handleCoachRequest(request, process.env.ANTHROPIC_API_KEY);
}
