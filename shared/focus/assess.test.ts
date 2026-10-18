import { describe, expect, it } from "vitest";
import type { AssessInput, FocusAssessment } from "../contracts/assessment";
import type { GripFeedback } from "./gripFeedback";
import type { ThrowRecord } from "../throwEntry";
import { assess } from "./assess";
import { FOUR_SEAM_INSTRUCTION_ZONES, instructionZonesForPitch } from "./rules";

function makeThrow(
  overrides: Omit<Partial<ThrowRecord>, "measurements"> & {
    measurements?: Partial<ThrowRecord["measurements"]>;
  } = {},
): ThrowRecord {
  const { measurements: measurementOverrides, ...rest } = overrides;
  return {
    schemaVersion: "1.0.0",
    throwId: "sample-throw-1",
    sessionId: "sample-session-1",
    pitchId: "four-seam",
    recordedAt: "2026-10-17T00:00:00Z",
    measurements: {
      velocityMph: 82.4,
      totalSpinRpm: 2180,
      spinDirectionClock: 12.5,
      spinEfficiencyPercent: 72,
      gyroDegree: null,
      // Required and nullable since break became part of the measurement
      // contract. Null, not a number: the Maya acceptance case carries no
      // break reading and inventing one would change what the fixture means.
      horizontalBreakInches: null,
      verticalBreakInches: null,
      releaseHeightFeet: 5.8,
      rapsodoScore: null,
      ...measurementOverrides,
    },
    source: "sample",
    extensions: {},
    ...rest,
  };
}

/** The structured result assess() parks under `extensions` for phase two. */
function feedbackOf(result: FocusAssessment): GripFeedback {
  return result.extensions.gripFeedback as GripFeedback;
}

const mayaFourSeam: AssessInput = {
  pitchId: "four-seam",
  throws: [makeThrow()],
  zones: FOUR_SEAM_INSTRUCTION_ZONES,
};

describe("assess packs one grip change into the FocusAssessment wire type", () => {
  it("takes its next action and its rule version from the grip rule engine", () => {
    const result = assess(mayaFourSeam);

    // 72 percent against the 95 to 100 four-seam band, with the axis inside
    // its range so the axis rule does not own the reading.
    expect(result.ruleVersion).toBe("demo-rules-1");
    expect(result.classification).toBe("grip-focus");
    expect(result.nextAction.summary).toBe(
      "Spin efficiency reads 72 percent, below target.",
    );
    expect(result.nextAction.rewritten).toBe(false);
    expect(feedbackOf(result).ruleId).toBe("four-seam-efficiency");
  });

  it("writes the measured line, the change and the expectation into the detail", () => {
    const { nextAction } = assess(mayaFourSeam);
    const feedback = feedbackOf(assess(mayaFourSeam));

    expect(nextAction.detail).toBe(
      `${feedback.measured} ${feedback.change} ${feedback.expect}`,
    );
    // The arithmetic, so the player can see the reading the advice came from.
    expect(nextAction.detail).toContain("72 percent spin efficiency");
    // The change, in handInstructions wording.
    expect(nextAction.detail).toContain("stitching crosses underneath");
    // The number expected to move.
    expect(nextAction.detail).toContain("Spin efficiency rises.");
  });

  it("points nextAction.zoneId at the primary zone of the chosen change", () => {
    const result = assess(mayaFourSeam);
    const feedback = feedbackOf(result);

    expect(feedback.zones).toEqual(["index-pad", "middle-pad"]);
    expect(result.nextAction.zoneId).toBe("index-pad");
    expect(result.nextAction.zoneId).toBe(feedback.zones[0]);
  });

  it("carries the whole structured result under extensions", () => {
    const feedback = feedbackOf(assess(mayaFourSeam));

    expect(feedback).toEqual({
      kind: "change",
      measured: expect.stringContaining("1 throw:"),
      headline: "Spin efficiency reads 72 percent, below target.",
      change:
        "Rotate the ball so the stitching crosses underneath both pads rather than running along them.",
      expect: "Spin efficiency rises.",
      zones: ["index-pad", "middle-pad"],
      ruleId: "four-seam-efficiency",
      ruleVersion: "demo-rules-1",
      source: expect.stringContaining("handInstructions.md"),
    });
  });

  it("leaves the tinted zone list empty, because the engine scores no severity", () => {
    // FocusZone demands a severity and a confidence per zone and the rule
    // engine produces neither. The zones ride in nextAction.zoneId and in
    // extensions instead; phase two promotes them to a first-class field.
    expect(assess(mayaFourSeam).zones).toEqual([]);
  });
});

describe("assess handedness and baseline", () => {
  it("judges a left-hander against the mirrored axis target", () => {
    // 12:30 sits inside the right-handed 12:00 to 12:30 band and outside the
    // mirrored 11:30 to 12:00 one, so the same reading changes which rule
    // owns it. Dropping handedness would silently judge every lefty right.
    const right = assess(mayaFourSeam);
    const left = assess({ ...mayaFourSeam, handedness: "left" });

    expect(feedbackOf(right).ruleId).toBe("four-seam-efficiency");
    expect(feedbackOf(left).ruleId).toBe("four-seam-axis");
    expect(left.nextAction.summary).toBe(
      "Spin axis reads 12:30, off the target clock range.",
    );
    expect(left.nextAction.zoneId).toBe("thumb-pad");
  });

  it("defaults to a right-hander when handedness is not given", () => {
    expect(assess(mayaFourSeam)).toEqual(
      assess({ ...mayaFourSeam, handedness: "right" }),
    );
  });

  it("cannot judge a changeup without a fastball baseline, and can with one", () => {
    const changeup = {
      pitchId: "changeup",
      throws: [
        makeThrow({
          throwId: "changeup-1",
          pitchId: "changeup",
          measurements: { velocityMph: 80 },
        }),
      ],
      zones: instructionZonesForPitch("changeup"),
    };

    const alone = assess(changeup);
    expect(feedbackOf(alone).kind).toBe("baseline");
    expect(alone.classification).toBe("not-grip");
    expect(alone.nextAction.zoneId).toBeNull();

    // 4 mph off the fastball, against the 8 mph separation floor.
    const compared = assess({
      ...changeup,
      baseline: [
        makeThrow({ throwId: "fastball-1", measurements: { velocityMph: 84 } }),
      ],
    });
    expect(feedbackOf(compared).kind).toBe("change");
    expect(feedbackOf(compared).ruleId).toBe("changeup-separation");
    expect(compared.classification).toBe("grip-focus");
    expect(compared.nextAction.zoneId).toBe("palm");
  });
});

describe("assess outcomes that are not a grip change", () => {
  it("never tells a hand to move a contact it cannot make", () => {
    const result = assess({
      ...mayaFourSeam,
      zones: instructionZonesForPitch("four-seam", {
        "index-pad": "unreachable",
      }),
    });

    expect(feedbackOf(result).kind).toBe("fit");
    expect(result.classification).toBe("not-grip");
    expect(result.unreachableZones).toEqual(["index-pad"]);
    // The zone is still named, so the hand can show which contact does not
    // fit, but the advice is about fit rather than technique.
    expect(result.nextAction.zoneId).toBe("index-pad");
    expect(result.nextAction.summary).toContain("does not fit your hand yet");
    expect(result.nextAction.detail).not.toContain("Rotate the ball");
  });

  it("calls drifting release height an arm-slot problem and names no finger", () => {
    const result = assess({
      pitchId: "four-seam",
      throws: [5.2, 5.8, 6.2].map((releaseHeightFeet, i) =>
        makeThrow({
          throwId: `sample-throw-${i + 1}`,
          measurements: { releaseHeightFeet },
        }),
      ),
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
    });

    expect(feedbackOf(result).kind).toBe("drift");
    expect(result.classification).toBe("not-grip");
    expect(result.nextAction.zoneId).toBeNull();
    expect(result.nextAction.summary).toContain("arm-slot problem");
    expect(result.consistency).not.toBeNull();
  });

  it("says so when every reading is inside its target range", () => {
    // A slider wants low efficiency: 20 percent is under the 35 ceiling.
    const result = assess({
      pitchId: "slider",
      throws: [
        makeThrow({
          throwId: "slider-1",
          pitchId: "slider",
          measurements: { spinEfficiencyPercent: 20 },
        }),
      ],
      zones: instructionZonesForPitch("slider"),
    });

    expect(feedbackOf(result).kind).toBe("on-target");
    expect(result.classification).toBe("not-grip");
    expect(result.nextAction.zoneId).toBeNull();
    expect(result.confidence).toBe(0.5);
  });

  it("asks for throws, with zero confidence, when none were recorded", () => {
    const result = assess({
      pitchId: "four-seam",
      throws: [],
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
    });

    expect(feedbackOf(result).kind).toBe("no-data");
    expect(result.throwIds).toEqual([]);
    expect(result.confidence).toBe(0);
    expect(result.nextAction.zoneId).toBeNull();
    expect(result.nextAction.summary).toContain("Record a few throws");
  });

  it("cannot fire a rule whose reading is absent", () => {
    const result = assess({
      pitchId: "four-seam",
      throws: [
        makeThrow({
          measurements: { spinEfficiencyPercent: null, gyroDegree: null },
        }),
      ],
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
    });

    // Efficiency is the only four-seam reading off target here, and it is
    // missing, so nothing is claimed about it.
    expect(feedbackOf(result).kind).toBe("on-target");
    expect(result.nextAction.detail).not.toContain("spin efficiency");
  });
});

describe("assess bookkeeping around the engine", () => {
  it("is pure and deterministic: identical inputs produce identical output without mutating them", () => {
    const throws = [makeThrow()];
    const zones = instructionZonesForPitch("four-seam");
    const baseline = [
      makeThrow({ throwId: "fastball-1", measurements: { velocityMph: 90 } }),
    ];

    const snapshotThrows = structuredClone(throws);
    const snapshotZones = structuredClone(zones);
    const snapshotBaseline = structuredClone(baseline);

    const first = assess({ pitchId: "four-seam", throws, zones, baseline });
    const second = assess({ pitchId: "four-seam", throws, zones, baseline });

    expect(first).toEqual(second);
    expect(throws).toEqual(snapshotThrows);
    expect(zones).toEqual(snapshotZones);
    expect(baseline).toEqual(snapshotBaseline);
  });

  it("derives ids and throw ids deterministically from the session", () => {
    const result = assess(mayaFourSeam);

    expect(result.schemaVersion).toBe("1.0.0");
    expect(result.assessmentId).toBe("sample-assessment-1");
    expect(result.gripPlanId).toBe("sample-four-seam-average-right");
    expect(result.throwIds).toEqual(["sample-throw-1"]);
    expect(result.prototypeAdvice).toBe(true);

    const explicit = assess({
      ...mayaFourSeam,
      gripPlanId: "plan-7",
      assessmentId: "assessment-7",
    });
    expect(explicit.gripPlanId).toBe("plan-7");
    expect(explicit.assessmentId).toBe("assessment-7");
  });

  it("returns null consistency under 3 throws and reports spread separately from grip focus", () => {
    expect(assess(mayaFourSeam).consistency).toBeNull();

    const threeThrows = [
      { velocityMph: 80.0, totalSpinRpm: 2050, releaseHeightFeet: 5.8 },
      { velocityMph: 84.5, totalSpinRpm: 2300, releaseHeightFeet: 5.9 },
      { velocityMph: 82.0, totalSpinRpm: 2150, releaseHeightFeet: 5.85 },
    ].map((measurements, i) =>
      makeThrow({ throwId: `sample-throw-${i + 1}`, measurements }),
    );

    const result = assess({
      pitchId: "four-seam",
      throws: threeThrows,
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
    });

    expect(result.consistency).toEqual({
      throwCount: 3,
      velocitySpreadMph: 4.5,
      totalSpinSpreadRpm: 250,
      inconsistent: true,
    });
    // Spread is reported, never acted on: the grip finding stands on its own.
    expect(result.classification).toBe("grip-focus");
    expect(feedbackOf(result).ruleId).toBe("four-seam-efficiency");
  });
});
