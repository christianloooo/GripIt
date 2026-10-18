/**
 * Researched facts only: what each pitch should read. No coaching copy and no
 * instruction for a miss. Responses belong to gripRules.ts, so correcting a
 * number here never touches a rule.
 *
 * These are transcribed from manufacturer education and coaching sources.
 * They are not validated against outcomes.
 */
export interface Range {
  min?: number;
  max?: number;
}

export interface PitchTarget {
  pitchId: string;
  axisClock?: Range; // decimal clock hours, e.g. 12:30 is 12.5
  efficiencyPercent?: Range;
  horizontalBreakInches?: Range;
  verticalBreakInches?: Range;
  spinPerMph?: Range;
  source: string;
}

/** Stored for a right-handed pitcher. */
export const PITCH_TARGETS: Readonly<Record<string, PitchTarget>> = {
  "four-seam": {
    pitchId: "four-seam",
    axisClock: { min: 12, max: 12.5 },
    efficiencyPercent: { min: 95, max: 100 },
    verticalBreakInches: { min: 15, max: 20 },
    horizontalBreakInches: { min: -3, max: 3 },
    spinPerMph: { min: 22 },
    source:
      "Rapsodo, 'Understanding the Three Fastball Movement Profiles' and the fastball spin-rate/efficiency profile article (backspin profile). Spin per mph from PitchLogic: average near 24, barely changes with velocity.",
  },
  "two-seam": {
    pitchId: "two-seam",
    axisClock: { min: 1, max: 2 },
    // Wide on purpose. The source says different efficiencies suit different
    // spin directions, arm slots and grips.
    efficiencyPercent: { min: 75, max: 100 },
    horizontalBreakInches: { min: 10, max: 20 },
    spinPerMph: { min: 22 },
    source:
      "Rapsodo fastball spin-rate/efficiency article: 75 to 100 percent efficiency, wide because different efficiencies suit different spin directions, arm slots and grips.",
  },
  slider: {
    pitchId: "slider",
    // No minimum: a gyro slider runs under 10 percent and that is correct.
    // The value this replaces was 65 percent, which the same article puts at
    // a sweeping curveball, so the old rule was about 30 points wrong.
    efficiencyPercent: { max: 35 },
    source:
      "Rapsodo curveball/slider/changeup article: gyro sliders under 10 percent, topspin and sidespin sliders near 35 percent with 65 to 75 gyro degrees.",
  },
  changeup: {
    pitchId: "changeup",
    // Deliberately empty. A changeup is judged only against the same
    // pitcher's own fastball, which gripRules.ts handles with a baseline.
    source:
      "Rapsodo curveball/slider/changeup article: its own changeup examples run 71.6 to 100 percent efficiency, so no single efficiency target is defensible.",
  },
};

// Mirroring reverses order, so the bounds swap to keep min at or below max.
function mirrorRange(range: Range, fn: (value: number) => number): Range {
  const mirrored: Range = {};
  if (range.max !== undefined) mirrored.min = fn(range.max);
  if (range.min !== undefined) mirrored.max = fn(range.min);
  return mirrored;
}

// Mirror about 12 o'clock. Readings just past 12 stay above 12 (12:30 is
// 12.5), so a plain modulo would send 11.5 to 0.5 and break the round trip.
// Only values that land at 13 or more wrap back onto the dial.
function mirrorClock(clock: number): number {
  const mirrored = 24 - clock;
  return mirrored >= 13 ? mirrored - 12 : mirrored;
}

export function targetFor(
  pitchId: string,
  handedness: "left" | "right",
): PitchTarget | null {
  const target = PITCH_TARGETS[pitchId];
  if (!target) return null;
  if (handedness === "right") return target;

  const mirrored: PitchTarget = { ...target };
  if (target.axisClock) {
    mirrored.axisClock = mirrorRange(target.axisClock, mirrorClock);
  }
  if (target.horizontalBreakInches) {
    mirrored.horizontalBreakInches = mirrorRange(
      target.horizontalBreakInches,
      (inches) => -inches,
    );
  }
  return mirrored;
}
