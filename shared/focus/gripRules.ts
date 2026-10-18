import type { FocusZone, ZoneId } from "../contracts/zones";
import type { ThrowRecord } from "../throwEntry";
import { clockHoursApart, type DerivedMetrics } from "./metrics";
import type { PitchTarget, Range } from "./targets";

/**
 * Responses only: given metrics and a target, is a symptom present, how far
 * off is it, and what do we say. Choosing between rules belongs to
 * gripFeedback.ts. Target numbers are never written here; they come from the
 * PitchTarget argument.
 */
export interface Deviation {
  summary: string; // what is off, in plain words, naming the reading
  magnitude: number; // normalised, 0 means on target, bigger is worse
}

/** What this rule actually checks, including the inputs its guards need. */
interface RuleReading {
  metric: keyof Omit<DerivedMetrics, "throwCount">;
  measurement: keyof ThrowRecord["measurements"];
  label: string;
  unit?: string;
  target?: Exclude<keyof PitchTarget, "pitchId" | "source">;
  baseline?: keyof Omit<DerivedMetrics, "throwCount">;
  guard?: "axis" | "axis-and-efficiency";
  requiresMinimum?: boolean;
}

export interface GripRule {
  id: string;
  pitchIds: readonly string[];
  reading: RuleReading;
  detect(
    m: DerivedMetrics,
    t: PitchTarget,
    baseline: DerivedMetrics | null,
  ): Deviation | null;
  change: string; // what to do, in handInstructions wording
  cue: string; // consumer paraphrase, documented in handInstructions.md
  zones: readonly ZoneId[]; // fingers to highlight on the 3D hand
  expect: string; // which number should move, and which way
  source: string;
}

export const GRIP_RULE_VERSION = "demo-rules-1";

// How much deviation counts as one unit of badness. Several rules fire at
// once and only the worst is shown, so units must be comparable. These are
// judgement calls, not research: an hour of axis is treated as about as bad as
// 5 efficiency points, 2 spin per mph, 4 inches of break, or 2 mph of missing
// changeup separation. None of these decides whether a rule fires, only how
// two firing rules rank against each other, so none of them is a target.
const SCALE = {
  axisHours: 1,
  efficiencyPoints: 5,
  spinPerMph: 2,
  breakInches: 4,
  separationMph: 2,
} as const;

/** How far a value sits outside a range. 0 when inside, or value/range absent. */
function distanceOutside(
  value: number | null | undefined,
  range: Range | undefined,
): number {
  if (value === null || value === undefined || !range) return 0;
  if (range.min !== undefined && value < range.min) return range.min - value;
  if (range.max !== undefined && value > range.max) return value - range.max;
  return 0;
}

// The dial wraps, so 0.2 and 12.2 are the same reading. Shift the reading to
// within half a dial of the range before testing it, then measure the miss
// from the nearer end with clockHoursApart.
function axisDistance(
  axis: number | null,
  range: Range | undefined,
): number {
  if (axis === null || !range) return 0;
  const ends = [range.min, range.max].filter(
    (end): end is number => end !== undefined,
  );
  if (!ends.length) return 0;
  const mid = (Math.min(...ends) + Math.max(...ends)) / 2;
  let unwrapped = axis;
  while (unwrapped < mid - 6) unwrapped += 12;
  while (unwrapped > mid + 6) unwrapped -= 12;
  if (distanceOutside(unwrapped, range) === 0) return 0;
  return Math.min(...ends.map((end) => clockHoursApart(axis, end)));
}

/**
 * A clock reading as a dial position. Presentation only: nothing here decides
 * whether a rule fires, and axisDistance() does its own unwrapping.
 *
 * Exported so gripFeedback.ts's measured line reads the same renderer rather
 * than a second copy of it. gripFeedback already depends on this module, so
 * sharing adds no edge to the dependency graph.
 *
 * A dial has no zero hour. The twelfth hour runs from 12:00 up to 1:00, so a
 * reading in that band keeps the hour 12 instead of printing "0:mm".
 */
export function clockText(clock: number): string {
  const mod = clock % 12;
  const wrapped = mod < 1 ? mod + 12 : mod;
  let hours = Math.floor(wrapped);
  let minutes = Math.round((wrapped - hours) * 60);
  if (minutes === 60) {
    hours = hours === 12 ? 1 : hours + 1;
    minutes = 0;
  }
  return `${hours}:${String(minutes).padStart(2, "0")}`;
}

function deviation(
  summary: string,
  distance: number,
  scale: number,
): Deviation | null {
  return distance > 0 ? { summary, magnitude: distance / scale } : null;
}

const FOUR_SEAM = ["four-seam"] as const;
const TWO_SEAM = ["two-seam"] as const;
const SLIDER = ["slider"] as const;
const CHANGEUP = ["changeup"] as const;

// Only the shortfall counts as weak run. A lefty's range is mirrored, so the
// weak side is found from the range itself: a range centred above zero is
// weak below its min, one centred below zero is weak above its max. Too much
// run is not a grip fault, so it never fires.
function runShortfall(
  value: number | null,
  range: Range | undefined,
): number {
  if (value === null || !range) return 0;
  const ends = [range.min, range.max].filter(
    (end): end is number => end !== undefined,
  );
  if (!ends.length) return 0;
  const mid = (Math.min(...ends) + Math.max(...ends)) / 2;
  const nearZeroEnd = mid >= 0 ? { min: range.min } : { max: range.max };
  return distanceOutside(value, nearZeroEnd);
}

const RAPSODO_SOURCE =
  "Rapsodo, 'Understanding the Three Fastball Movement Profiles' and the fastball spin-rate/efficiency profile article";
const PRP_SOURCE = "PRP Baseball published pitch-grading cues";
const RAPSODO_SLIDER_SOURCE =
  "Rapsodo curveball/slider/changeup article: gyro sliders under 10 percent, topspin and sidespin sliders near 35 percent with 65 to 75 gyro degrees";
const CHANGEUP_BASELINE_SOURCE =
  "A changeup has no absolute target, so both rules compare it to the same pitcher's own fastball in the same session";

export const GRIP_RULES: readonly GripRule[] = [
  {
    id: "four-seam-axis",
    cue: "Rest your thumb under the ball, below the gap between your index and middle fingers.",
    pitchIds: FOUR_SEAM,
    reading: { metric: "spinDirectionClock", measurement: "spinDirectionClock", label: "Spin axis", target: "axisClock" },
    detect(m, t) {
      if (m.spinDirectionClock === null) return null;
      const miss = axisDistance(m.spinDirectionClock, t.axisClock);
      return deviation(
        `Spin axis reads ${clockText(m.spinDirectionClock)}, off the target clock range.`,
        miss,
        SCALE.axisHours,
      );
    },
    change:
      "Set the thumb pad under the space between the index and middle fingers, on smooth leather.",
    zones: ["thumb-pad"],
    expect: "Axis moves toward 12 o'clock and spin efficiency rises.",
    source: `${RAPSODO_SOURCE} (axis target); ${PRP_SOURCE}; handInstructions.md (thumb approximately opposite the space between the two upper fingers, initially on smooth leather). Centring the thumb squares the hand behind the ball.`,
  },
  {
    id: "four-seam-efficiency",
    cue: "Turn the ball so the seams cross under your index and middle fingertips.",
    pitchIds: FOUR_SEAM,
    reading: { metric: "spinEfficiencyPercent", measurement: "spinEfficiencyPercent", label: "Spin efficiency", unit: " percent", target: "efficiencyPercent", guard: "axis" },
    detect(m, t) {
      // The axis rule owns an off-target axis. One fix at a time.
      if (axisDistance(m.spinDirectionClock, t.axisClock) > 0) return null;
      const eff = m.spinEfficiencyPercent;
      if (eff === null) return null;
      return deviation(
        `Spin efficiency reads ${eff} percent, below target.`,
        distanceOutside(eff, t.efficiencyPercent),
        SCALE.efficiencyPoints,
      );
    },
    change:
      "Rotate the ball so the stitching crosses underneath both pads rather than running along them.",
    zones: ["index-pad", "middle-pad"],
    expect: "Spin efficiency rises.",
    source: `${RAPSODO_SOURCE} (efficiency target); ${PRP_SOURCE}; handInstructions.md (pad across the raised stitching, seam crossing underneath).`,
  },
  {
    id: "four-seam-purchase",
    cue: "Place your index and middle fingertips on the raised seams.",
    pitchIds: FOUR_SEAM,
    reading: { metric: "spinPerMph", measurement: "totalSpinRpm", label: "Spin per mph", target: "spinPerMph" },
    detect(m, t) {
      const spm = m.spinPerMph;
      if (spm === null) return null;
      return deviation(
        `Spin per mph reads ${spm}, below target. The pads may be on smooth leather.`,
        distanceOutside(spm, t.spinPerMph),
        SCALE.spinPerMph,
      );
    },
    change: "Move both pads onto the raised stitching.",
    zones: ["index-pad", "middle-pad"],
    expect: "Total spin rises.",
    source: `Spin per mph target from PitchLogic via targets.ts; ${PRP_SOURCE}; handInstructions.md (pad across the raised stitching).`,
  },
  {
    id: "four-seam-cut",
    cue: "Bring your index and middle fingers closer without squeezing them together.",
    pitchIds: FOUR_SEAM,
    reading: { metric: "horizontalBreakInches", measurement: "horizontalBreakInches", label: "Horizontal break", unit: " inches", target: "horizontalBreakInches", guard: "axis" },
    detect(m, t) {
      // Horizontal break on a fastball is downstream of the spin axis: an
      // axis at 1:56 rather than 12:00 produces arm-side run as a direct
      // consequence, so closing the finger gap is the wrong change when the
      // axis is what is off. Same shared-cause case as four-seam-buried, and
      // correctness must not depend on ranking. Efficiency is deliberately
      // not guarded against: it scales how large the break is, not which
      // direction it goes, so it is not a shared cause here.
      if (axisDistance(m.spinDirectionClock, t.axisClock) > 0) return null;
      const h = m.horizontalBreakInches;
      if (h === null) return null;
      return deviation(
        `Horizontal break reads ${h} inches. A four-seam should run near straight.`,
        distanceOutside(h, t.horizontalBreakInches),
        SCALE.breakInches,
      );
    },
    change:
      "Bring the index and middle fingers closer, to a comfortable, small separation.",
    zones: ["index-pad", "middle-pad"],
    expect: "Sideways movement drops and vertical break rises.",
    source: `${RAPSODO_SOURCE} (backspin profile has near-zero horizontal break); ${PRP_SOURCE}; handInstructions.md (a comfortable, small separation between the fingers).`,
  },
  {
    id: "four-seam-buried",
    cue: "Hold the ball with your fingers and thumb, leaving a little space above your palm.",
    pitchIds: FOUR_SEAM,
    reading: { metric: "verticalBreakInches", measurement: "verticalBreakInches", label: "Vertical break", unit: " inches", target: "verticalBreakInches", guard: "axis-and-efficiency", requiresMinimum: true },
    detect(m, t) {
      // Low vertical break follows from an off axis or low efficiency more
      // often than from palm depth, so this rule only speaks when neither of
      // those explains it. Correctness must not depend on ranking.
      if (axisDistance(m.spinDirectionClock, t.axisClock) > 0) return null;
      const eff = m.spinEfficiencyPercent;
      if (distanceOutside(eff, t.efficiencyPercent) > 0) return null;
      const v = m.verticalBreakInches;
      // Only a low reading means buried. Extra rise is not a grip fault.
      if (v === null || (t.verticalBreakInches?.min ?? -Infinity) <= v) {
        return null;
      }
      return deviation(
        `Vertical break reads ${v} inches, below target. The ball may be buried in the palm.`,
        distanceOutside(v, t.verticalBreakInches),
        SCALE.breakInches,
      );
    },
    change:
      "Hold the ball between the upper pads and thumb, without deliberately burying it in your palm.",
    zones: ["palm"],
    expect: "Vertical break rises.",
    source: `${RAPSODO_SOURCE} (vertical break target); ${PRP_SOURCE}; handInstructions.md (without deliberately burying it in your palm).`,
  },
  {
    id: "two-seam-axis",
    cue: "Turn the ball so the two close seams run along your index and middle fingers.",
    pitchIds: TWO_SEAM,
    reading: { metric: "spinDirectionClock", measurement: "spinDirectionClock", label: "Spin axis", target: "axisClock" },
    detect(m, t) {
      if (m.spinDirectionClock === null) return null;
      const miss = axisDistance(m.spinDirectionClock, t.axisClock);
      return deviation(
        `Spin axis reads ${clockText(m.spinDirectionClock)}, off the target clock range. The ball may still be set like a four-seamer.`,
        miss,
        SCALE.axisHours,
      );
    },
    change:
      "Rotate the ball so the two close stretches of stitching run from your wrist toward your fingertips.",
    zones: ["index-pad", "middle-pad"],
    expect: "Axis moves into the arm-side range and the ball starts running.",
    source: `${RAPSODO_SOURCE} (axis target); ${PRP_SOURCE}; handInstructions.md (rotate the ball until the seams run approximately from the wrist toward the fingertips).`,
  },
  {
    id: "two-seam-run",
    cue: "Place your index and middle fingertips along the two close seams, one finger on each seam.",
    pitchIds: TWO_SEAM,
    reading: { metric: "horizontalBreakInches", measurement: "horizontalBreakInches", label: "Horizontal break", unit: " inches", target: "horizontalBreakInches", guard: "axis" },
    detect(m, t) {
      // An off axis explains weak run better than seam placement does, and
      // two-seam-axis owns that case. Correctness must not depend on ranking.
      if (axisDistance(m.spinDirectionClock, t.axisClock) > 0) return null;
      const h = m.horizontalBreakInches;
      if (h === null) return null;
      return deviation(
        `Horizontal break reads ${h} inches, below target. The pitch is not running.`,
        runShortfall(h, t.horizontalBreakInches),
        SCALE.breakInches,
      );
    },
    change:
      "Set the index pad along the thumb-side seam and the middle pad along the other seam. Rotate the ball slightly until both pads engage stitching.",
    zones: ["index-pad", "middle-pad"],
    expect: "Horizontal run increases.",
    source: `${RAPSODO_SOURCE} (horizontal break target); ${PRP_SOURCE}; handInstructions.md (index pad on the thumb-side seam, middle pad on the other seam, each following the stitching).`,
  },
  {
    id: "two-seam-efficiency",
    cue: "Move your thumb under the ball, below your index and middle fingers.",
    pitchIds: TWO_SEAM,
    reading: { metric: "spinEfficiencyPercent", measurement: "spinEfficiencyPercent", label: "Spin efficiency", unit: " percent", target: "efficiencyPercent", guard: "axis" },
    detect(m, t) {
      // The axis rule owns an off-target axis. One fix at a time.
      if (axisDistance(m.spinDirectionClock, t.axisClock) > 0) return null;
      const eff = m.spinEfficiencyPercent;
      if (eff === null) return null;
      return deviation(
        `Spin efficiency reads ${eff} percent, below target. The hand may have slipped to the side of the ball.`,
        distanceOutside(eff, t.efficiencyPercent),
        SCALE.efficiencyPoints,
      );
    },
    change:
      "Bring the thumb back under the two upper fingers, supporting the underside with its fleshy pad.",
    zones: ["thumb-pad"],
    expect: "Spin efficiency rises.",
    source: `${RAPSODO_SOURCE} (75 to 100 percent efficiency, wide because different efficiencies suit different spin directions, arm slots and grips); ${PRP_SOURCE}; handInstructions.md (thumb supports the underside, approximately opposite the two upper fingers).`,
  },
  {
    id: "two-seam-purchase",
    cue: "Place your index and middle fingertips along their seams.",
    pitchIds: TWO_SEAM,
    reading: { metric: "spinPerMph", measurement: "totalSpinRpm", label: "Spin per mph", target: "spinPerMph" },
    detect(m, t) {
      const spm = m.spinPerMph;
      if (spm === null) return null;
      return deviation(
        `Spin per mph reads ${spm}, below target. The pads may be on smooth leather.`,
        distanceOutside(spm, t.spinPerMph),
        SCALE.spinPerMph,
      );
    },
    change:
      "Set both pads onto their seams so each follows its own stitching.",
    zones: ["index-pad", "middle-pad"],
    expect: "Total spin rises.",
    source: `Spin per mph target from PitchLogic via targets.ts; ${PRP_SOURCE}; handInstructions.md (each upper finger follows its own seam).`,
  },
  // Only one slider rule. "Fingers too far apart" cannot be observed from ball
  // flight or a static scan. "Not enough sweep" has no target because the app
  // does not know whether a sweeper or a gyro slider was intended, and
  // targetFor("slider") carries no break range. Spin per mph has no slider
  // target either, so there is no purchase rule.
  {
    id: "slider-efficiency",
    cue: "Relax your index finger beside your middle finger and let your middle finger hold the seam.",
    pitchIds: SLIDER,
    reading: { metric: "spinEfficiencyPercent", measurement: "spinEfficiencyPercent", label: "Spin efficiency", unit: " percent", target: "efficiencyPercent" },
    detect(m, t) {
      const eff = m.spinEfficiencyPercent;
      if (eff === null) return null;
      return deviation(
        `Spin efficiency reads ${eff} percent, above the slider range. The index finger may be driving the ball like a fastball.`,
        distanceOutside(eff, t.efficiencyPercent),
        SCALE.efficiencyPoints,
      );
    },
    // The index is named only to relax it. On a slider it parks on leather.
    change:
      "Let the index pad rest on the smooth leather beside the middle finger, and let the middle finger alone work the pinky-side seam.",
    zones: ["index-pad"],
    expect: "Spin efficiency drops and gyro degree rises.",
    source: `${RAPSODO_SLIDER_SOURCE} (efficiency ceiling); ${PRP_SOURCE}; handInstructions.md (middle pad on the pinky-side seam, index pad resting on the adjacent smooth leather).`,
  },
  // Two changeup rules, not the four the design table lists.
  //
  // "No fade" is cut. It needs to know whether the changeup is breaking
  // arm-side, and targetFor("changeup") carries no horizontalBreakInches
  // range to measure that against. detect() is not given handedness, and the
  // changeup target is identical for both hands because it has nothing to
  // mirror, so the arguments carry no way to tell arm-side from glove-side.
  // The only ways to get it are to invent a break target or to assume a sign,
  // and a sign assumption passes every right-handed test while inverting the
  // advice for every left-hander. Restore this row when a sourced changeup
  // break range exists; it will then mirror like the two-seam one does.
  //
  // "Loop squeezed rigid" is cut. Its trigger is grip pressure, which ball
  // flight and a static hand scan cannot observe. Same class as the cut
  // slider "fingers too far apart" row.
  {
    id: "changeup-separation",
    cue: "Let the ball sit deeper in your hand while your middle and ring fingers stay on it.",
    pitchIds: CHANGEUP,
    reading: { metric: "velocityMph", measurement: "velocityMph", label: "Changeup velocity", unit: " mph", target: "velocitySeparationMph", baseline: "velocityMph" },
    detect(m, t, baseline) {
      if (!baseline) return null;
      const velocity = m.velocityMph;
      const fastball = baseline.velocityMph;
      if (velocity === null || fastball === null) return null;
      // A gap, not a signed measurement, so handedness cannot touch it.
      const separation = Math.round((fastball - velocity) * 10) / 10;
      return deviation(
        `Changeup velocity reads ${velocity} mph, ${separation} off the fastball's ${fastball}. It is too close to read as a different pitch.`,
        distanceOutside(separation, t.velocitySeparationMph),
        SCALE.separationMph,
      );
    },
    change:
      "Let the ball settle comfortably into the hand while maintaining middle- and ring-finger contact.",
    zones: ["palm"],
    expect: "Velocity drops.",
    source: `${CHANGEUP_BASELINE_SOURCE}. Separation floor from targets.ts, where it is recorded as a coaching convention rather than a measured target; ${PRP_SOURCE}; handInstructions.md (let the ball settle comfortably into the hand while maintaining middle- and ring-finger contact).`,
  },
  {
    id: "changeup-spin",
    cue: "Curl your index finger around the side of the ball near your thumb.",
    pitchIds: CHANGEUP,
    reading: { metric: "spinPerMph", measurement: "totalSpinRpm", label: "Spin per mph", baseline: "spinPerMph" },
    // No target argument is read: a changeup has no absolute spin target.
    detect(m, _t, baseline) {
      if (!baseline) return null;
      const spm = m.spinPerMph;
      const fastball = baseline.spinPerMph;
      if (spm === null || fastball === null) return null;
      // The comparison point is the pitcher's own fastball, not a number of
      // ours. Not guarded against changeup-separation: a changeup still at
      // fastball velocity has a deflated spin per mph, so a missing
      // separation can only hide this symptom, never manufacture it.
      return deviation(
        `Spin per mph reads ${spm}, above the fastball's ${fastball}. The changeup is still spinning like a fastball.`,
        distanceOutside(spm, { max: fastball }),
        SCALE.spinPerMph,
      );
    },
    change:
      "Wrap the index finger's inner middle/distal surface around the thumb-side centre of the ball, close to the equator, opposite the pinky. Keep the tip softly curled rather than pointing away.",
    zones: ["index-pad"],
    expect: "Spin drops.",
    source: `${CHANGEUP_BASELINE_SOURCE}, so the comparison point is the baseline's own spin per mph and no threshold is written here; ${PRP_SOURCE}; handInstructions.md (inner middle/distal surface around the thumb-side centre, opposite the pinky; tip softly curled).`,
  },
];


function hasReading(value: number | null | undefined): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function hasRange(range: Range | undefined): range is Range {
  return !!range && (hasReading(range.min) || hasReading(range.max));
}

/** Availability and shared-cause guards apply to every severity color. */
export function ruleReadingAvailable(
  rule: GripRule,
  m: DerivedMetrics,
  t: PitchTarget,
  baseline: DerivedMetrics | null,
): boolean {
  const reading = rule.reading;
  const value = m[reading.metric];
  if (!hasReading(value)) return false;
  if (reading.target && !hasRange(t[reading.target])) return false;
  if (reading.requiresMinimum &&
      (!reading.target || !hasReading(t[reading.target]?.min))) return false;
  if (reading.baseline && (!baseline || !hasReading(baseline[reading.baseline]))) return false;
  if (reading.guard) {
    if (!hasReading(m.spinDirectionClock) || !hasRange(t.axisClock) ||
        axisDistance(m.spinDirectionClock, t.axisClock) > 0) return false;
    if (reading.guard === "axis-and-efficiency" &&
        (!hasReading(m.spinEfficiencyPercent) || !hasRange(t.efficiencyPercent) ||
         distanceOutside(m.spinEfficiencyPercent, t.efficiencyPercent) > 0)) return false;
  }
  return true;
}

/**
 * A null detector alone is not evidence of a clean check. Require its data
 * and shared-cause guards without changing detection, targets, or ranking.
 */
export function checkedRuleReading(
  rule: GripRule,
  m: DerivedMetrics,
  t: PitchTarget,
  baseline: DerivedMetrics | null,
): Pick<FocusZone, "reason" | "triggeringMeasurement"> | null {
  if (!ruleReadingAvailable(rule, m, t, baseline)) return null;
  if (rule.detect(m, t, baseline) !== null) return null;
  const reading = rule.reading;
  const value = m[reading.metric]!;
  const formatted = reading.metric === "spinDirectionClock" ? clockText(value) : value;
  const comparison = reading.baseline ? ` against the fastball's ${baseline![reading.baseline]}${reading.unit ?? ""}` : "";
  return {
    reason: `${reading.label} reads ${formatted}${reading.unit ?? ""}${comparison}. This check found no deviation.`,
    triggeringMeasurement: reading.measurement,
  };
}
