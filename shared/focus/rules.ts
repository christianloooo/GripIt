import type { AssessmentRule, RuleSet } from "../contracts/assessment";
import type { InstructionZone, ZoneId, ZoneReach } from "../contracts/zones";

/**
 * Versioned prototype rule set (`sample-rules-1`).
 *
 * Rules are pure data so coaching thresholds can move during coach review
 * without editing engine control flow.
 *
 * Pitch coverage follows `docs/workstreams/step-4-rule-engine.md`:
 * - `four-seam`: full spin-efficiency bands against the 90% target from `PRODUCT.md`.
 * - `two-seam`: conservative lower bound and lower confidence to account for deliberate sidespin.
 * - `slider`: inverted comparison (a slider wants low spin efficiency, never fastball logic)
 *   with low confidence; throws at or below the ceiling return `not-grip`.
 * - `changeup`: no single-pitch rules because the signal is velocity separation from a fastball.
 */
export const SAMPLE_RULES_LIST: readonly AssessmentRule[] = [
  {
    id: "four-seam-low-spin-efficiency",
    pitchIds: ["four-seam"],
    measurement: "spinEfficiencyPercent",
    when: { below: 80, target: 90 },
    zones: [
      { zoneId: "wrist", severity: "red", confidence: 0.6 },
      { zoneId: "middle-pad", severity: "red", confidence: 0.5 },
      { zoneId: "index-pad", severity: "yellow", confidence: 0.4 },
      { zoneId: "thumb-pad", severity: "yellow", confidence: 0.4 },
    ],
    reason: "Spin efficiency {value}% is below the {target}% four-seam target",
    nextAction: {
      zoneId: "wrist",
      summary: "Stay behind the ball",
      detail:
        "Keep the wrist firm and push through the back of the ball instead of around its side.",
    },
    confidence: 0.6,
    classification: "grip-focus",
  },
  {
    id: "four-seam-moderate-spin-efficiency",
    pitchIds: ["four-seam"],
    measurement: "spinEfficiencyPercent",
    when: { atLeast: 80, below: 90, target: 90 },
    zones: [
      { zoneId: "wrist", severity: "yellow", confidence: 0.5 },
      { zoneId: "middle-pad", severity: "yellow", confidence: 0.5 },
      { zoneId: "index-pad", severity: "yellow", confidence: 0.45 },
      { zoneId: "thumb-pad", severity: "yellow", confidence: 0.4 },
    ],
    reason: "Spin efficiency {value}% is below the {target}% four-seam target",
    nextAction: {
      zoneId: "middle-pad",
      summary: "Finish squarely through the horseshoe seam",
      detail:
        "Keep both upper finger pads even across the stitching and drive straight through release.",
    },
    confidence: 0.5,
    classification: "grip-focus",
  },
  {
    id: "four-seam-target-spin-efficiency",
    pitchIds: ["four-seam"],
    measurement: "spinEfficiencyPercent",
    when: { atLeast: 90, target: 90 },
    zones: [
      { zoneId: "wrist", severity: "green", confidence: 0.6 },
      { zoneId: "middle-pad", severity: "green", confidence: 0.6 },
      { zoneId: "index-pad", severity: "green", confidence: 0.55 },
      { zoneId: "thumb-pad", severity: "green", confidence: 0.5 },
    ],
    reason: "Spin efficiency {value}% meets the {target}% four-seam target",
    nextAction: {
      zoneId: "wrist",
      summary: "Repeat this four-seam release",
      detail:
        "Spin efficiency meets the 90% target. Keep the same wrist position and finger pressure on the next throw.",
    },
    confidence: 0.6,
    classification: "grip-focus",
  },
  {
    id: "two-seam-low-spin-efficiency",
    pitchIds: ["two-seam"],
    measurement: "spinEfficiencyPercent",
    when: { below: 65, target: 75 },
    zones: [
      { zoneId: "wrist", severity: "yellow", confidence: 0.4 },
      { zoneId: "index-pad", severity: "yellow", confidence: 0.35 },
      { zoneId: "middle-pad", severity: "yellow", confidence: 0.35 },
    ],
    reason:
      "Spin efficiency {value}% is below the conservative {threshold}% two-seam floor",
    nextAction: {
      zoneId: "index-pad",
      summary: "Keep pads aligned along the two-seam pair",
      detail:
        "Rest the index and middle pads along their seams and stay behind the ball before adding extra movement.",
    },
    confidence: 0.4,
    classification: "grip-focus",
  },
  {
    id: "slider-excess-spin-efficiency",
    pitchIds: ["slider"],
    measurement: "spinEfficiencyPercent",
    when: { above: 65, target: 65 },
    zones: [
      { zoneId: "middle-pad", severity: "yellow", confidence: 0.35 },
      { zoneId: "wrist", severity: "yellow", confidence: 0.35 },
    ],
    reason:
      "Spin efficiency {value}% is above the {threshold}% slider ceiling where sliders aim for lower efficiency",
    nextAction: {
      zoneId: "middle-pad",
      summary: "Work the pinky-side seam",
      detail:
        "A slider wants lower spin efficiency than a fastball. Apply firmer purchase along the pinky-side seam with the middle finger.",
    },
    confidence: 0.35,
    classification: "grip-focus",
  },
];

export const SAMPLE_RULE_SET: RuleSet = {
  version: "sample-rules-1",
  ruleVersion: "sample-rules-1",
  prototypeAdvice: true,
  releaseHeightDriftFeet: 0.5,
  velocitySpreadThresholdMph: 3,
  totalSpinSpreadThresholdRpm: 200,
  rules: SAMPLE_RULES_LIST,
};

export const DEFAULT_RULE_SET: RuleSet = SAMPLE_RULE_SET;

/**
 * Canonical Step 2 instruction zones per pitch from `docs/workstreams/zone-contract.md`.
 * Used by tests and fallback callers when evaluating throws against standard grips.
 */
export const PITCH_INSTRUCTION_ZONES: Record<
  string,
  readonly InstructionZone[]
> = {
  "four-seam": [
    {
      zoneId: "index-pad",
      title: "Index finger",
      instruction: "Pad across the raised stitching, seam crossing underneath",
      pressure: "medium",
      role: "drive",
      reach: "comfortable",
      placement: {
        surface: "pad",
        region: "top",
        seam: "across",
        seamOffsetMm: 0,
        opposes: [],
      },
    },
    {
      zoneId: "middle-pad",
      title: "Middle finger",
      instruction: "Beside the index, pad also crossing the stitching",
      pressure: "firm",
      role: "drive",
      reach: "comfortable",
      placement: {
        surface: "pad",
        region: "top",
        seam: "across",
        seamOffsetMm: 0,
        opposes: [],
      },
    },
    {
      zoneId: "ring-side",
      title: "Ring finger",
      instruction: "Side of the finger curled against the ball for light support",
      pressure: "light",
      role: "support",
      reach: "comfortable",
      placement: {
        surface: "side",
        region: "pinky-side",
        seam: "off",
        seamOffsetMm: null,
        opposes: [],
      },
    },
    {
      zoneId: "pinky",
      title: "Pinky",
      instruction: "Relaxed beside the ring finger, clear of the ball",
      pressure: "none",
      role: "clear",
      reach: "comfortable",
      placement: {
        surface: "none",
        region: "off-ball",
        seam: "none",
        seamOffsetMm: null,
        opposes: [],
      },
    },
    {
      zoneId: "thumb-pad",
      title: "Thumb",
      instruction: "Fleshy pad underneath, on smooth leather",
      pressure: "light",
      role: "support",
      reach: "comfortable",
      placement: {
        surface: "pad",
        region: "underside",
        seam: "off",
        seamOffsetMm: null,
        opposes: ["index-pad", "middle-pad"],
      },
    },
    {
      zoneId: "palm",
      title: "Palm",
      instruction: "Do not bury the ball. Leave a small gap",
      pressure: "none",
      role: "clear",
      reach: "comfortable",
      placement: null,
    },
    {
      zoneId: "wrist",
      title: "Wrist",
      instruction: "Stay behind the ball",
      pressure: "firm",
      role: "drive",
      reach: "comfortable",
      placement: null,
    },
  ],
  "two-seam": [
    {
      zoneId: "index-pad",
      title: "Index finger",
      instruction: "Pad along the thumb-side seam, following its direction",
      pressure: "medium",
      role: "drive",
      reach: "comfortable",
      placement: {
        surface: "pad",
        region: "top",
        seam: "along",
        seamOffsetMm: 0,
        opposes: [],
      },
    },
    {
      zoneId: "middle-pad",
      title: "Middle finger",
      instruction: "Pad along the other seam, toward the pinky side",
      pressure: "medium",
      role: "drive",
      reach: "comfortable",
      placement: {
        surface: "pad",
        region: "top",
        seam: "along",
        seamOffsetMm: 0,
        opposes: [],
      },
    },
    {
      zoneId: "ring-side",
      title: "Ring finger",
      instruction: "Curled lightly against the pinky-side surface",
      pressure: "light",
      role: "support",
      reach: "comfortable",
      placement: {
        surface: "side",
        region: "pinky-side",
        seam: "off",
        seamOffsetMm: null,
        opposes: [],
      },
    },
    {
      zoneId: "pinky",
      title: "Pinky",
      instruction: "Relaxed beside the ring finger, off the ball",
      pressure: "none",
      role: "clear",
      reach: "comfortable",
      placement: {
        surface: "none",
        region: "off-ball",
        seam: "none",
        seamOffsetMm: null,
        opposes: [],
      },
    },
    {
      zoneId: "thumb-pad",
      title: "Thumb",
      instruction: "Fleshy pad underneath, opposite the two upper fingers",
      pressure: "light",
      role: "support",
      reach: "comfortable",
      placement: {
        surface: "pad",
        region: "underside",
        seam: "off",
        seamOffsetMm: null,
        opposes: ["index-pad", "middle-pad"],
      },
    },
    {
      zoneId: "palm",
      title: "Palm",
      instruction: "Similar depth to the four-seam. Do not bury the ball",
      pressure: "none",
      role: "clear",
      reach: "comfortable",
      placement: null,
    },
    {
      zoneId: "wrist",
      title: "Wrist",
      instruction: "Stay behind the ball",
      pressure: "firm",
      role: "drive",
      reach: "comfortable",
      placement: null,
    },
  ],
  slider: [
    {
      zoneId: "index-pad",
      title: "Index finger",
      instruction: "Rests on smooth leather beside the middle finger, stabilising",
      pressure: "light",
      role: "support",
      reach: "comfortable",
      placement: {
        surface: "pad",
        region: "top",
        seam: "beside",
        seamOffsetMm: null,
        opposes: [],
      },
    },
    {
      zoneId: "middle-pad",
      title: "Middle finger",
      instruction: "Pad along the pinky-side seam with definite purchase",
      pressure: "firm",
      role: "drive",
      reach: "comfortable",
      placement: {
        surface: "pad",
        region: "top",
        seam: "along",
        seamOffsetMm: 0,
        opposes: [],
      },
    },
    {
      zoneId: "ring-side",
      title: "Ring finger",
      instruction: "Curled against the surface below the middle finger",
      pressure: "light",
      role: "support",
      reach: "comfortable",
      placement: {
        surface: "side",
        region: "pinky-side",
        seam: "off",
        seamOffsetMm: null,
        opposes: [],
      },
    },
    {
      zoneId: "pinky",
      title: "Pinky",
      instruction: "Relaxed beside the ring finger, clear of the ball",
      pressure: "none",
      role: "clear",
      reach: "comfortable",
      placement: {
        surface: "none",
        region: "off-ball",
        seam: "none",
        seamOffsetMm: null,
        opposes: [],
      },
    },
    {
      zoneId: "thumb-pad",
      title: "Thumb",
      instruction: "Underneath and opposite, slightly off centre, no hard pinch",
      pressure: "light",
      role: "support",
      reach: "comfortable",
      placement: {
        surface: "pad",
        region: "underside",
        seam: "off",
        seamOffsetMm: null,
        opposes: ["middle-pad"],
      },
    },
    {
      zoneId: "wrist",
      title: "Wrist",
      instruction: "Release decides whether this behaves like a slider",
      pressure: "firm",
      role: "drive",
      reach: "comfortable",
      placement: null,
    },
  ],
  changeup: [
    {
      zoneId: "index-pad",
      title: "Index finger",
      instruction: "Curled around the thumb-side surface, forming a loop with the thumb",
      pressure: "light",
      role: "support",
      reach: "comfortable",
      placement: {
        surface: "curl",
        region: "thumb-side",
        seam: "off",
        seamOffsetMm: null,
        opposes: ["thumb-pad"],
      },
    },
    {
      zoneId: "middle-pad",
      title: "Middle finger",
      instruction: "Pad along the thumb-side seam",
      pressure: "medium",
      role: "drive",
      reach: "comfortable",
      placement: {
        surface: "pad",
        region: "top",
        seam: "along",
        seamOffsetMm: 0,
        opposes: [],
      },
    },
    {
      zoneId: "ring-side",
      title: "Ring finger",
      instruction: "Pad along the pinky-side seam. A principal contact here",
      pressure: "medium",
      role: "drive",
      reach: "comfortable",
      placement: {
        surface: "pad",
        region: "top",
        seam: "along",
        seamOffsetMm: 0,
        opposes: [],
      },
    },
    {
      zoneId: "pinky",
      title: "Pinky",
      instruction: "Wrapped lightly around the far side to stabilise",
      pressure: "light",
      role: "support",
      reach: "comfortable",
      placement: {
        surface: "curl",
        region: "pinky-side",
        seam: "off",
        seamOffsetMm: null,
        opposes: [],
      },
    },
    {
      zoneId: "thumb-pad",
      title: "Thumb",
      instruction: "Wrapped around the lower thumb-side surface, closing the loop",
      pressure: "light",
      role: "support",
      reach: "comfortable",
      placement: {
        surface: "pad",
        region: "thumb-side",
        seam: "off",
        seamOffsetMm: null,
        opposes: ["index-pad"],
      },
    },
    {
      zoneId: "palm",
      title: "Palm",
      instruction: "Let the ball settle comfortably into the hand",
      pressure: "light",
      role: "support",
      reach: "comfortable",
      placement: null,
    },
  ],
};

export const FOUR_SEAM_INSTRUCTION_ZONES: readonly InstructionZone[] =
  PITCH_INSTRUCTION_ZONES["four-seam"];

export function instructionZonesForPitch(
  pitchId: string,
  reachOverrides: Partial<Record<ZoneId, ZoneReach>> = {},
): InstructionZone[] {
  const base =
    PITCH_INSTRUCTION_ZONES[pitchId] ?? PITCH_INSTRUCTION_ZONES["four-seam"];
  return base.map((zone) => ({
    ...zone,
    placement: zone.placement
      ? { ...zone.placement, opposes: [...zone.placement.opposes] }
      : null,
    reach: reachOverrides[zone.zoneId] ?? zone.reach,
  }));
}
