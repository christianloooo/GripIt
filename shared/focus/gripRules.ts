import type { ZoneId } from "../contracts/zones";
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

export interface GripRule {
  id: string;
  pitchIds: readonly string[];
  detect(
    m: DerivedMetrics,
    t: PitchTarget,
    baseline: DerivedMetrics | null,
  ): Deviation | null;
  change: string; // what to do, in handInstructions wording
  zones: readonly ZoneId[]; // fingers to highlight on the 3D hand
  expect: string; // which number should move, and which way
  source: string;
}

export const GRIP_RULE_VERSION = "demo-rules-1";

// How much deviation counts as one unit of badness. Several rules fire at
// once and only the worst is shown, so units must be comparable. These are
// judgement calls, not research: an hour of axis is treated as about as bad as
// 5 efficiency points, 2 spin per mph, or 4 inches of break.
const SCALE = {
  axisHours: 1,
  efficiencyPoints: 5,
  spinPerMph: 2,
  breakInches: 4,
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

function clockText(clock: number): string {
  const wrapped = clock % 12 === 0 ? 12 : clock % 12;
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

const RAPSODO_SOURCE =
  "Rapsodo, 'Understanding the Three Fastball Movement Profiles' and the fastball spin-rate/efficiency profile article";
const PRP_SOURCE = "PRP Baseball published pitch-grading cues";

export const GRIP_RULES: readonly GripRule[] = [
  {
    id: "four-seam-axis",
    pitchIds: FOUR_SEAM,
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
    pitchIds: FOUR_SEAM,
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
    pitchIds: FOUR_SEAM,
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
    pitchIds: FOUR_SEAM,
    detect(m, t) {
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
    pitchIds: FOUR_SEAM,
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
];
