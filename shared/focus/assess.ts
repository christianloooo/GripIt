import type {
  AssessInput,
  AssessmentClassification,
  ConsistencyReport,
  FocusAssessment,
  NextAction,
} from "../contracts/assessment";
import { unreachableZones } from "../contracts/zones";
import type { ThrowRecord } from "../throwEntry";
import { gripFeedback, type GripFeedback } from "./gripFeedback";

export type { AssessInput };

/**
 * Spread across a session that makes single-throw advice unreliable. Carried
 * over unchanged from the RuleSet defaults this file shipped with, where they
 * were `DEFAULT_VELOCITY_SPREAD_MPH` and `DEFAULT_TOTAL_SPIN_SPREAD_RPM` and
 * no caller ever overrode them. Not new numbers.
 *
 * Consistency is reported, never acted on: it does not change a verdict, so
 * it stays here rather than moving into the rule engine.
 */
const VELOCITY_SPREAD_MPH = 3;
const TOTAL_SPIN_SPREAD_RPM = 200;

/** Matches the shipped gate: fewer than three throws is not yet a spread. */
const MIN_THROWS_FOR_CONSISTENCY = 3;

/**
 * `FocusAssessment.confidence` is required by the wire type, and the rule
 * engine does not score confidence: a rule either fires on a reading or it
 * does not. Rather than invent a calibration, both values are lifted from the
 * paths this file already shipped — 0 when there are no throws, and the 0.5 it
 * returned on its own release-drift path. `prototypeAdvice` stays true, which
 * is the honest statement about an uncalibrated number.
 *
 * Phase two drops the field when the structured result is promoted out of
 * `extensions`.
 */
const UNSCORED_CONFIDENCE = 0.5;

function roundNumber(value: number, decimals = 2): number {
  const factor = 10 ** decimals;
  return Math.round((value + Number.EPSILON) * factor) / factor;
}

function computeConsistency(
  throws: readonly ThrowRecord[],
): ConsistencyReport | null {
  if (throws.length < MIN_THROWS_FOR_CONSISTENCY) return null;

  const velocities = throws
    .map((t) => t.measurements.velocityMph)
    .filter((v): v is number => typeof v === "number" && Number.isFinite(v));
  const spins = throws
    .map((t) => t.measurements.totalSpinRpm)
    .filter((v): v is number => typeof v === "number" && Number.isFinite(v));

  const velocitySpreadMph =
    velocities.length >= 2
      ? roundNumber(Math.max(...velocities) - Math.min(...velocities), 2)
      : 0;
  const totalSpinSpreadRpm =
    spins.length >= 2
      ? roundNumber(Math.max(...spins) - Math.min(...spins), 2)
      : 0;

  return {
    throwCount: throws.length,
    velocitySpreadMph,
    totalSpinSpreadRpm,
    inconsistent:
      velocitySpreadMph > VELOCITY_SPREAD_MPH ||
      totalSpinSpreadRpm > TOTAL_SPIN_SPREAD_RPM,
  };
}

function deriveGripPlanId(
  pitchId: string,
  throws: readonly ThrowRecord[],
  explicitId?: string,
): string {
  if (explicitId && explicitId.trim()) return explicitId;
  const isSample =
    throws.length === 0 ||
    throws.some(
      (t) => t.source === "sample" || t.throwId.startsWith("sample-"),
    );
  return `${isSample ? "sample-" : ""}${pitchId}-average-right`;
}

function deriveAssessmentId(
  pitchId: string,
  throws: readonly ThrowRecord[],
  explicitId?: string,
): string {
  if (explicitId && explicitId.trim()) return explicitId;
  if (throws.length === 1 && throws[0].throwId === "sample-throw-1") {
    return "sample-assessment-1";
  }
  const isSample =
    throws.length > 0 &&
    throws.every(
      (t) => t.source === "sample" || t.throwId.startsWith("sample-"),
    );
  const ids = throws.map((t) => t.throwId).join("-");
  return `${isSample ? "sample-" : ""}assessment-${pitchId}${ids ? `-${ids}` : ""}`;
}

/**
 * The measured line, then the change to make, then the number expected to
 * move. On an outcome that names no change, `change` and `expect` are null and
 * the detail is the arithmetic alone.
 */
function detailFrom(feedback: GripFeedback): string {
  return [feedback.measured, feedback.change, feedback.expect]
    .filter((part): part is string => part !== null && part.trim() !== "")
    .join(" ");
}

/**
 * Packs one `GripFeedback` into the existing `FocusAssessment` wire type.
 *
 * Phase one, so the wire type's shape is untouched and Swift keeps decoding
 * what it already decodes:
 *
 * - `nextAction.summary` is the headline.
 * - `nextAction.detail` is the measured line, the change and the expectation.
 * - `nextAction.zoneId` is the primary zone, the first of the chosen rule's
 *   zones, or null when the outcome names none.
 * - `extensions.gripFeedback` carries the whole structured result, which
 *   existing decoders ignore. Phase two promotes it to a first-class field.
 *
 * `zones` stays empty. `FocusZone` demands a severity and a confidence per
 * zone and the rule engine produces neither: a rule names the contacts to
 * change, with no colour and no score. Filling those in would be inventing a
 * calibration to tint a 3D model with, so the zones travel in `nextAction`
 * and in `extensions` instead, which is where phase one reads them from.
 */
export function assess(input: AssessInput): FocusAssessment {
  const { pitchId, throws, zones, baseline, handedness } = input;

  const feedback = gripFeedback({
    pitchId,
    throws,
    zones,
    baseline,
    handedness,
  });

  const nextAction: NextAction = {
    zoneId: feedback.zones[0] ?? null,
    summary: feedback.headline,
    detail: detailFrom(feedback),
    rewritten: false,
  };

  // A grip change is the only outcome that is a grip finding. A fit problem,
  // a missing baseline, release drift and an on-target reading all name no
  // technique change, which is what `not-grip` says.
  const classification: AssessmentClassification =
    feedback.kind === "change" ? "grip-focus" : "not-grip";

  return {
    schemaVersion: "1.0.0",
    assessmentId: deriveAssessmentId(pitchId, throws, input.assessmentId),
    gripPlanId: deriveGripPlanId(pitchId, throws, input.gripPlanId),
    throwIds: throws.map((t) => t.throwId),
    ruleVersion: feedback.ruleVersion,
    classification,
    zones: [],
    nextAction,
    confidence: feedback.kind === "no-data" ? 0 : UNSCORED_CONFIDENCE,
    unreachableZones: unreachableZones(zones),
    consistency: computeConsistency(throws),
    // True while the rule set has not been reviewed by a pitching coach.
    prototypeAdvice: true,
    extensions: { gripFeedback: feedback },
  };
}
