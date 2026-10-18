import type { FocusAssessment } from "../contracts/assessment";
import type { GripPlan } from "../contracts/gripPlan";
import type { ThrowRecord } from "../throwEntry";
import {
  fingerLengthMm,
  middleIndexDifferenceMm,
  type HandProfile,
} from "../contracts/handProfile";

/**
 * Explains how this player's measured hand meets this pitch's grip.
 *
 * Nothing else in the pipeline does this. The rule engine reads throw numbers
 * and the solver reports reachability as one enum per zone, so a 63 mm palm and
 * a 95 mm palm currently receive identical advice for the same throw. That gap
 * is the product's whole premise, and it is the kind of reasoning a rule table
 * cannot hold: the answer differs for every hand, pitch and throw combination.
 *
 * The guard is strict for the same reason the task is valuable. Invented
 * biomechanics read exactly like measured ones.
 */

/** Short enough to scan beside the model. Two sentences, not an essay. */
export const MAX_FIT_LENGTH = 320;

export const FIT_SYSTEM_PROMPT = `You explain how a specific pitcher's hand meets a specific grip.

Write at most two sentences, in one paragraph, under 300 characters. This sits in a small panel beside a 3D model, so length is a hard constraint, not a preference. Pick the single most useful thing the measurements say and leave the rest out.

You are given their measured hand and the grip this pitch asks for. Explain static fit only, not throw performance.

Rules:
- Every physical claim must rest on a measurement you were given. Cite the number.
- Use only numbers that appear in the input. Never introduce one, and never round one into a different number.
- Describe what the measurements mean for where the fingers sit. Do not diagnose an injury, predict a velocity, or promise a result.
- Static lengths do not establish wrist tilt, release motion or finger force. Do not claim the hand must compensate or twist. If suggesting a contact adjustment, phrase it as an optional fit check, not an observed fault.
- If a zone is marked unreachable or strained, say the grip does not fit that hand well and what to do instead. Never tell them to press harder on it.
- Do not compare this player to other pitchers, to averages, or to professionals. You have no such data.
- If the measurements say nothing useful about this pitch, say the hand looks unremarkable for this grip. That is a valid and useful answer.
- Speak to the player as "you". No preamble, no second paragraph.
- Write one paragraph with no line breaks. Use plain commas and full stops, not dashes.

Write at a high school athlete's reading level.`;

export interface FitInput {
  assessment: FocusAssessment;
  profile: HandProfile;
  plan: GripPlan;
  throws?: ThrowRecord[];
}

/** Only the measurements and the grip intent. No geometry, no landmarks. */
export function buildFitInput({ profile, plan }: FitInput): string {
  const fingers = profile.measurements.fingers;
  return JSON.stringify(
    {
      pitch: plan.pitchId,
      handedness: profile.handedness,
      hand: {
        palmWidthMm: profile.measurements.palm.widthMm,
        palmLengthMm: profile.measurements.palm.lengthMm,
        fingerLengthsMm: {
          index: fingerLengthMm(fingers.index),
          middle: fingerLengthMm(fingers.middle),
          ring: fingerLengthMm(fingers.ring),
          pinky: fingerLengthMm(fingers.pinky),
          thumb: fingerLengthMm(fingers.thumb),
        },
        middleMinusIndexMm: middleIndexDifferenceMm(profile),
        segmentsMm: Object.fromEntries(
          Object.entries(fingers).map(([name, f]) => [name, f.segmentsMm]),
        ),
      },
      gripAsksFor: plan.instructionZones.map((zone) => ({
        zone: zone.zoneId,
        does: zone.instruction,
        pressure: zone.pressure,
        role: zone.role,
        reach: zone.reach,
      })),
      fitConfidence: plan.fit.confidence,
    },
    null,
    2,
  );
}

/**
 * Rejects an explanation that invented a figure or pushed on a contact the
 * hand cannot make. A fabricated millimetre reads exactly like a measured one,
 * which is why this is checked rather than trusted.
 */
export function fitRejection(
  text: string,
  input: FitInput,
  serialized: string = buildFitInput(input),
): string | null {
  const trimmed = text.trim();
  if (trimmed.length < 20) return "too-short";
  if (trimmed.length > MAX_FIT_LENGTH) return "too-long";

  const permitted = new Set(serialized.match(/\d+(?:\.\d+)?/g) ?? []);
  for (const number of trimmed.match(/\d+(?:\.\d+)?/g) ?? []) {
    if (!permitted.has(number)) return `invented-number-${number}`;
  }

  const lowered = trimmed.toLowerCase();
  // No population claims: there is no such data anywhere in this product.
  for (const phrase of [
    "average pitcher",
    "most pitchers",
    "compared to other",
    "professional pitchers",
    "than average",
  ]) {
    if (lowered.includes(phrase)) return "population-claim";
  }
  return null;
}

export function isUsableFit(
  text: string,
  input: FitInput,
  serialized: string = buildFitInput(input),
): boolean {
  return fitRejection(text, input, serialized) === null;
}
