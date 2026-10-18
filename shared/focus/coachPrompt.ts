import type { FocusAssessment } from "../contracts/assessment";

/**
 * Everything the coaching rewrite needs, with no network and no SDK.
 *
 * The model's only job is to say the engine's finding the way a coach would.
 * It is given the numbers rather than asked for them, told which zones it may
 * not mention, and constrained to one or two sentences. Keeping all of that
 * here means it can be tested without spending anything.
 */

export const COACH_SYSTEM_PROMPT = `You rewrite one line of baseball pitching feedback so it sounds like a coach talking to the player in front of them.

You are given a finished assessment. Another system already decided what is wrong, how confident it is, and which part of the hand to work on. You are not deciding any of that.

Rules:
- Use only numbers that appear in the input. Never introduce a number of your own, and never round one into a different number.
- Never mention a zone listed in unreachableZones. The player physically cannot make that contact, so telling them to adjust it is useless.
- Say one thing to change. Not three.
- One or two sentences. Short ones.
- Speak to the player as "you". No preamble, no sign-off, no exclamation marks.
- Write one paragraph with no line breaks. Use plain commas and full stops, not dashes.
- Do not promise a result. "Try this" is the tone, not "this will fix it".
- If classification is "not-grip", make clear the fix is in the arm or timing rather than the hand, and do not name a finger.

Write at a high school athlete's reading level.`;

/** The one field the model is allowed to produce. */
export interface CoachOutput {
  detail: string;
}

/** The subset of the assessment the model sees. Nothing else is sent. */
export function buildCoachInput(assessment: FocusAssessment): string {
  return JSON.stringify(
    {
      classification: assessment.classification,
      confidence: assessment.confidence,
      focusZone: assessment.nextAction.zoneId,
      summary: assessment.nextAction.summary,
      deterministicDetail: assessment.nextAction.detail,
      findings: assessment.zones.map((zone) => ({
        zone: zone.zoneId,
        severity: zone.severity,
        reason: zone.reason,
      })),
      unreachableZones: assessment.unreachableZones,
      consistency: assessment.consistency,
    },
    null,
    2,
  );
}

/** Digits the model is allowed to use, taken from what it was shown. */
function allowedNumbers(input: string): Set<string> {
  return new Set(input.match(/\d+(?:\.\d+)?/g) ?? []);
}

/**
 * Rejects a rewrite that broke a rule, so the deterministic sentence ships
 * instead. Catching a fabricated number matters more than catching an awkward
 * one: a wrong number reads as authoritative.
 */
export function isUsableRewrite(
  rewrite: string,
  assessment: FocusAssessment,
  input: string = buildCoachInput(assessment),
): boolean {
  const trimmed = rewrite.trim();
  if (trimmed.length < 10 || trimmed.length > 400) return false;

  const permitted = allowedNumbers(input);
  for (const number of trimmed.match(/\d+(?:\.\d+)?/g) ?? []) {
    if (!permitted.has(number)) return false;
  }

  const lowered = trimmed.toLowerCase();
  for (const zoneId of assessment.unreachableZones) {
    if (lowered.includes(zoneId.replace("-", " ")) || lowered.includes(zoneId)) {
      return false;
    }
  }
  return true;
}
