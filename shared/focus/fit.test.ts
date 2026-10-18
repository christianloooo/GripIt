import { describe, expect, it } from "vitest";
import assessmentFixture from "../contracts/fixtures/focus-assessment-four-seam.json";
import profileFixture from "../contracts/fixtures/hand-profile-small-right.json";
import planFixture from "../contracts/fixtures/grip-plan-four-seam.json";
import type { FocusAssessment } from "../contracts/assessment";
import type { HandProfile } from "../contracts/handProfile";
import type { GripPlan } from "../contracts/gripPlan";
import {
  middleIndexDifferenceMm,
  fingerLengthMm,
} from "../contracts/handProfile";
import {
  buildFitInput,
  fitRejection,
  isUsableFit,
  MAX_FIT_LENGTH,
} from "./fitPrompt";
import { isAskableQuestion } from "./askPrompt";

const context = {
  assessment: assessmentFixture as FocusAssessment,
  profile: profileFixture as HandProfile,
  plan: planFixture as GripPlan,
};

describe("hand measurements", () => {
  it("sums a finger and reports the middle-to-index difference", () => {
    expect(fingerLengthMm(context.profile.measurements.fingers.index)).toBe(79);
    expect(fingerLengthMm(context.profile.measurements.fingers.middle)).toBe(
      88,
    );
    expect(middleIndexDifferenceMm(context.profile)).toBe(9);
  });

  it("returns null rather than a wrong number when a segment is missing", () => {
    expect(fingerLengthMm({ segmentsMm: [], diameterMm: null })).toBeNull();
    expect(
      fingerLengthMm({ segmentsMm: [36, Number.NaN, 20], diameterMm: null }),
    ).toBeNull();
  });
});

describe("fit explanation input", () => {
  it("carries the measurements and the grip, and no geometry", () => {
    const input = buildFitInput(context);
    expect(input).toContain("palmWidthMm");
    expect(input).toContain("76");
    expect(input).toContain("middleMinusIndexMm");
    expect(input).toContain("strained");
    // Step 4 must never reconstruct the pose.
    expect(input).not.toContain("ballTransform");
    expect(input).not.toContain("jointTransforms");
    expect(input).not.toContain("landmarks");
  });
});

describe("fit explanation guard", () => {
  it("accepts an explanation built from the measurements it was given", () => {
    expect(
      isUsableFit(
        "Your middle finger is 9 mm longer than your index, so it sits deeper on the seam at the same wrist angle. That suits the firmer middle pressure this grip asks for.",
        context,
      ),
    ).toBe(true);
  });

  it("rejects an invented measurement", () => {
    // A fabricated millimetre reads exactly like a measured one.
    expect(
      isUsableFit(
        "Your index finger is 52 mm long, which is short for this grip.",
        context,
      ),
    ).toBe(false);
  });

  it("rejects a comparison to other pitchers", () => {
    // There is no population data anywhere in this product.
    expect(
      isUsableFit(
        "Your palm is 76 mm, narrower than most pitchers who throw this grip.",
        context,
      ),
    ).toBe(false);
  });

  it("rejects something too short to be an explanation", () => {
    expect(fitRejection("Looks fine.", context)).toBe("too-short");
  });

  // This sits beside the model in a narrow column. The first live runs came
  // back at roughly 900 characters, which is an essay, not a panel note.
  it("rejects an explanation too long for the panel", () => {
    const essay = "Your middle finger is 9 mm longer than your index. ".repeat(
      20,
    );
    expect(essay.length).toBeGreaterThan(MAX_FIT_LENGTH);
    expect(fitRejection(essay, context)).toBe("too-long");
  });

  it("names the invented number rather than just failing", () => {
    expect(fitRejection("Your index finger is 52 mm long.", context)).toBe(
      "invented-number-52",
    );
  });
});

describe("follow-up questions", () => {
  // All that survives of the ask prompt. The question box still calls a model,
  // but through INTERPRET_SYSTEM_PROMPT and isUsableInterpretation, which
  // interpretation.test.ts covers. This guard runs before the key is read.
  it("rejects an empty or oversized question before spending anything", () => {
    expect(isAskableQuestion("")).toBe(false);
    expect(isAskableQuestion("  ")).toBe(false);
    expect(isAskableQuestion("x".repeat(301))).toBe(false);
    expect(isAskableQuestion("Why is my wrist red?")).toBe(true);
  });
});
