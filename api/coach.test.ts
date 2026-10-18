import { describe, expect, it, vi, beforeEach } from "vitest";
import assessmentFixture from "../shared/contracts/fixtures/focus-assessment-four-seam.json";
import profileFixture from "../shared/contracts/fixtures/hand-profile-small-right.json";
import planFixture from "../shared/contracts/fixtures/grip-plan-four-seam.json";
import type { FocusAssessment } from "../shared/contracts/assessment";
import type { HandProfile } from "../shared/contracts/handProfile";
import type { GripPlan } from "../shared/contracts/gripPlan";
import { FIT_SYSTEM_PROMPT } from "../shared/focus/fitPrompt";

// The point of these cases is what is NOT sent, so the provider call is the
// thing under observation rather than something to stub away quietly.
const { generate } = vi.hoisted(() => ({ generate: vi.fn() }));
vi.mock("./_client", async (importOriginal) => ({
  ...(await importOriginal<typeof import("./_client")>()),
  generate,
}));

const { explainFit, resolveCoachModel } = await import("./coach");

const assessment = assessmentFixture as FocusAssessment;
const handData = {
  profile: profileFixture as HandProfile,
  plan: planFixture as GripPlan,
};

beforeEach(() => {
  generate.mockReset();
  generate.mockResolvedValue({ ok: true, text: "Your hand meets this grip." });
});

describe("model resolution", () => {
  // An unset key in a .env file arrives as "", not undefined, so `??` silently
  // sent an empty model and the API answered 400. The deterministic sentence
  // still shipped, which is exactly why this was invisible without a live call.
  it("falls back when the environment supplies an empty value", () => {
    expect(resolveCoachModel("")).toBe("claude-opus-5");
    expect(resolveCoachModel("   ")).toBe("claude-opus-5");
    expect(resolveCoachModel(undefined)).toBe("claude-opus-5");
  });

  it("uses an explicit override", () => {
    expect(resolveCoachModel("claude-haiku-4-5")).toBe("claude-haiku-4-5");
    expect(resolveCoachModel(" claude-sonnet-5 ")).toBe("claude-sonnet-5");
  });
});

describe("coaching text", () => {
  it("makes one model call, and it is the fit explanation", async () => {
    await explainFit({ assessment, ...handData }, "key");
    expect(generate).toHaveBeenCalledTimes(1);
    expect(generate.mock.calls[0][0].system).toBe(FIT_SYSTEM_PROMPT);
  });

  it("returns the engine's own sentence rather than a rewrite of it", async () => {
    // The engine writes this line in full now. A model that agreed with it
    // would add nothing, and one that did not would be overruling the rules.
    const response = await explainFit({ assessment, ...handData }, "key");
    expect(response.detail).toBe(assessment.nextAction.detail);
    expect(response.rewritten).toBe(false);
    expect(response.fit).toBe("Your hand meets this grip.");
  });

  it("calls nothing at all when there is no hand and no grip to explain", async () => {
    const response = await explainFit({ assessment }, "key");
    expect(generate).not.toHaveBeenCalled();
    expect(response.detail).toBe(assessment.nextAction.detail);
    expect(response.fitReason).toBe("no-hand-data");
  });

  it("keeps the engine's sentence when the fit explanation is rejected", async () => {
    generate.mockResolvedValue({ ok: false, reason: "rejected" });
    const response = await explainFit({ assessment, ...handData }, "key");
    expect(response.detail).toBe(assessment.nextAction.detail);
    expect(response.fit).toBeUndefined();
    expect(response.fitReason).toBe("rejected");
  });
});
