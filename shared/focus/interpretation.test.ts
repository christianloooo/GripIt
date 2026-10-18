import { describe, expect, it } from "vitest";
import fixture from "../contracts/fixtures/focus-assessment-four-seam.json";
import type { FocusAssessment } from "../contracts/assessment";
import type { ThrowRecord } from "../throwEntry";
import {
  buildInterpretationInput,
  isUsableInterpretation,
  INTERPRET_SYSTEM_PROMPT,
} from "./interpretation";

const assessment = fixture as FocusAssessment;
const records: ThrowRecord[] = [82, 83, 84].map((velocityMph, i) => ({
  schemaVersion: "1.0.0",
  throwId: `t${i}`,
  sessionId: "s",
  pitchId: "four-seam",
  recordedAt: "2026-10-18T00:00:00Z",
  source: "manual",
  extensions: {},
  measurements: {
    velocityMph,
    totalSpinRpm: 2200,
    spinEfficiencyPercent: 72,
    gyroDegree: null,
    spinDirectionClock: 12.5,
    // Required and nullable since break became part of the measurement
    // contract. Null, not a number: this fixture exercises the interpretation
    // boundary, and a break reading would widen the set of numbers the guard
    // permits rather than leave the cases asserting what they assert today.
    horizontalBreakInches: null,
    verticalBreakInches: null,
    releaseHeightFeet: 5.8,
    rapsodoScore: null,
  },
}));

// Every call carries a question now. The coaching rewrite was the only
// caller that built this input without one, and it is gone.
const QUESTION = "What should I try next with this grip?";

describe("AI interpretation boundary", () => {
  it("provides raw readings and computed summaries rather than just preset advice", () => {
    const input = JSON.parse(
      buildInterpretationInput({ assessment, throws: records }, QUESTION),
    );
    expect(input.observations.throwCount).toBe(3);
    expect(input.observations.medians.velocityMph).toBe(83);
    expect(
      input.observations.recentThrows[0].measurements.spinDirectionClock,
    ).toBe(12.5);
    expect(input.prototypeRules.validated).toBe(false);
    expect(INTERPRET_SYSTEM_PROMPT).toContain("may disagree");
    expect(INTERPRET_SYSTEM_PROMPT).toContain("general explanation");
  });

  it("accepts computed numbers and explanations without forcing a preset zone", () => {
    const input = buildInterpretationInput(
      { assessment, throws: records },
      QUESTION,
    );
    expect(
      isUsableInterpretation(
        "Your median was 83 mph. Spin efficiency describes the ball, so it cannot identify which finger caused this result.",
        input,
      ),
    ).toBe(true);
    expect(
      isUsableInterpretation(
        "Your velocity was 99 mph. Change your grip.",
        input,
      ),
    ).toBe(false);
  });

  it("bounds recent detail and includes all throws in summary calculations", () => {
    const many = Array.from({ length: 30 }, (_, i) => ({
      ...records[0],
      throwId: `t${i}`,
    }));
    const input = JSON.parse(
      buildInterpretationInput({ assessment, throws: many }, QUESTION),
    );
    expect(input.observations.throwCount).toBe(30);
    expect(input.observations.recentThrows).toHaveLength(10);
  });

  it("accepts formatted clock time and rejects numbers borrowed from questions or source links", () => {
    const input = buildInterpretationInput(
      { assessment, throws: records },
      "Should I aim for 99 mph?",
    );
    expect(
      isUsableInterpretation(
        "Your spin direction was 12:30. That describes tilt, not finger pressure.",
        input,
      ),
    ).toBe(true);
    expect(
      isUsableInterpretation("Your measured velocity was 99 mph.", input),
    ).toBe(false);
    expect(
      isUsableInterpretation("Your measured velocity was 28500954 mph.", input),
    ).toBe(false);
  });

  it("preserves the sign on gyro measurements", () => {
    const record = {
      ...records[0],
      measurements: {
        ...records[0].measurements,
        gyroDegree: -25,
        spinEfficiencyPercent: null,
      },
    };
    const input = buildInterpretationInput(
      { assessment, throws: [record] },
      QUESTION,
    );
    expect(
      isUsableInterpretation("Your entered gyro angle was -25 degrees.", input),
    ).toBe(true);
    expect(
      isUsableInterpretation("Your entered gyro angle was +25 degrees.", input),
    ).toBe(false);
  });
});
