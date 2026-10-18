import type { FocusAssessment } from "../contracts/assessment";

/**
 * Asks the proxy to rewrite the coaching line, and degrades quietly.
 *
 * Every failure path returns the deterministic sentence the rule engine
 * already produced, so a dead network costs a slightly stiffer line rather
 * than an empty panel. Nothing here needs an API key; the proxy holds it.
 */

export interface CoachResult {
  detail: string;
  rewritten: boolean;
  reason?: string;
}

export const COACH_ENDPOINT = "/api/coach";
const COACH_TIMEOUT_MS = 8000;

export async function coach(
  assessment: FocusAssessment,
  options: { endpoint?: string; timeoutMs?: number; signal?: AbortSignal } = {},
): Promise<CoachResult> {
  const fallback: CoachResult = {
    detail: assessment.nextAction.detail,
    rewritten: false,
  };

  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort(),
    options.timeoutMs ?? COACH_TIMEOUT_MS,
  );
  options.signal?.addEventListener("abort", () => controller.abort());

  try {
    const response = await fetch(options.endpoint ?? COACH_ENDPOINT, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(assessment),
      signal: controller.signal,
    });
    if (!response.ok) return { ...fallback, reason: `http-${response.status}` };

    const body = (await response.json()) as Partial<CoachResult>;
    if (typeof body.detail !== "string" || !body.detail.trim()) {
      return { ...fallback, reason: "empty" };
    }
    return {
      detail: body.detail,
      rewritten: body.rewritten === true,
      reason: body.reason,
    };
  } catch (error) {
    const aborted = error instanceof Error && error.name === "AbortError";
    return { ...fallback, reason: aborted ? "timeout" : "network" };
  } finally {
    clearTimeout(timer);
  }
}

/** Folds a rewrite back into the assessment without touching any finding. */
export function withCoaching(
  assessment: FocusAssessment,
  result: CoachResult,
): FocusAssessment {
  return {
    ...assessment,
    nextAction: {
      ...assessment.nextAction,
      detail: result.detail,
      rewritten: result.rewritten,
    },
  };
}
