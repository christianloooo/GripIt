import { describe, expect, it } from "vitest";
import fixture from "../contracts/fixtures/focus-assessment-four-seam.json";
import type { AssessmentRule, FocusAssessment, RuleSet } from "../contracts/assessment";
import { toSeverityMap } from "../contracts/zones";
import type { ThrowRecord } from "../throwEntry";
import { assess } from "./assess";
import { isUsableRewrite } from "./coachPrompt";
import {
  FOUR_SEAM_INSTRUCTION_ZONES,
  SAMPLE_RULE_SET,
  instructionZonesForPitch,
} from "./rules";

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

describe("Step 4 deterministic rule engine (assess)", () => {
  it("reproduces the Maya 72% four-seam acceptance fixture exactly", () => {
    const mayaThrow = makeThrow({
      throwId: "sample-throw-1",
      pitchId: "four-seam",
      measurements: {
        velocityMph: 82.4,
        totalSpinRpm: 2180,
        spinDirectionClock: 12.5,
        spinEfficiencyPercent: 72,
        gyroDegree: null,
        releaseHeightFeet: 5.8,
        rapsodoScore: null,
      },
    });

    const result = assess({
      pitchId: "four-seam",
      throws: [mayaThrow],
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
      ruleSet: SAMPLE_RULE_SET,
    });

    expect(result).toEqual(fixture as FocusAssessment);
    expect(toSeverityMap(result.zones)).toEqual({
      wrist: "red",
      "middle-pad": "red",
      "index-pad": "yellow",
      "thumb-pad": "yellow",
    });
  });

  it("cools the four-seam zones to yellow at 84% and green at 92% as described in PRODUCT.md", () => {
    const secondThrow = makeThrow({
      throwId: "sample-throw-2",
      measurements: { spinEfficiencyPercent: 84 },
    });
    const yellowResult = assess({
      pitchId: "four-seam",
      throws: [secondThrow],
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
      ruleSet: SAMPLE_RULE_SET,
    });

    expect(yellowResult.classification).toBe("grip-focus");
    expect(yellowResult.zones.every((z) => z.severity === "yellow")).toBe(true);

    const onTargetThrow = makeThrow({
      throwId: "sample-throw-3",
      measurements: { spinEfficiencyPercent: 92 },
    });
    const greenResult = assess({
      pitchId: "four-seam",
      throws: [onTargetThrow],
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
      ruleSet: SAMPLE_RULE_SET,
    });

    expect(greenResult.classification).toBe("grip-focus");
    expect(greenResult.zones.every((z) => z.severity === "green")).toBe(true);
  });

  it("is pure and deterministic: identical inputs and rule version always produce identical output without mutating inputs", () => {
    const throws = [makeThrow({ measurements: { spinEfficiencyPercent: 72 } })];
    const zones = instructionZonesForPitch("four-seam");
    const ruleSet: RuleSet = structuredClone(SAMPLE_RULE_SET);

    const snapshotThrows = structuredClone(throws);
    const snapshotZones = structuredClone(zones);
    const snapshotRules = structuredClone(ruleSet);

    const first = assess({ pitchId: "four-seam", throws, zones, ruleSet });
    const second = assess({ pitchId: "four-seam", throws, zones, ruleSet });

    expect(first).toEqual(second);
    expect(throws).toEqual(snapshotThrows);
    expect(zones).toEqual(snapshotZones);
    expect(ruleSet).toEqual(snapshotRules);
  });

  it("ensures every emitted zone carries a non-empty reason and a bounded confidence", () => {
    const result = assess({
      pitchId: "four-seam",
      throws: [makeThrow({ measurements: { spinEfficiencyPercent: 72 } })],
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
      ruleSet: SAMPLE_RULE_SET,
    });

    expect(result.zones.length).toBeGreaterThan(0);
    for (const zone of result.zones) {
      expect(zone.reason.trim().length).toBeGreaterThan(0);
      expect(zone.reason).toContain("72%");
      expect(zone.triggeringMeasurement).toBe("spinEfficiencyPercent");
      expect(zone.confidence).toBeGreaterThan(0);
      expect(zone.confidence).toBeLessThanOrEqual(1);
    }
  });

  it("never gives technique advice to an unreachable zone and copies it to unreachableZones", () => {
    // Case 1: Secondary zone (`thumb-pad`) is unreachable
    const zonesWithUnreachableThumb = instructionZonesForPitch("four-seam", {
      "thumb-pad": "unreachable",
    });
    const thumbResult = assess({
      pitchId: "four-seam",
      throws: [makeThrow({ measurements: { spinEfficiencyPercent: 72 } })],
      zones: zonesWithUnreachableThumb,
      ruleSet: SAMPLE_RULE_SET,
    });

    expect(thumbResult.unreachableZones).toEqual(["thumb-pad"]);
    expect(thumbResult.zones.map((z) => z.zoneId)).not.toContain("thumb-pad");
    expect(thumbResult.nextAction.zoneId).not.toBe("thumb-pad");
    expect(isUsableRewrite(thumbResult.nextAction.detail, thumbResult)).toBe(
      true,
    );

    // Case 2: Primary target zone (`wrist`) is unreachable -> suppresses the rule targeting it
    const zonesWithUnreachableWrist = instructionZonesForPitch("four-seam", {
      wrist: "unreachable",
    });
    const wristResult = assess({
      pitchId: "four-seam",
      throws: [makeThrow({ measurements: { spinEfficiencyPercent: 72 } })],
      zones: zonesWithUnreachableWrist,
      ruleSet: SAMPLE_RULE_SET,
    });

    expect(wristResult.unreachableZones).toEqual(["wrist"]);
    expect(wristResult.zones.map((z) => z.zoneId)).not.toContain("wrist");
    expect(wristResult.nextAction.zoneId).toBeNull();
    expect(isUsableRewrite(wristResult.nextAction.detail, wristResult)).toBe(
      true,
    );
  });

  it("skips rules whose measurement is null and lowers overall confidence", () => {
    const presentResult = assess({
      pitchId: "four-seam",
      throws: [
        makeThrow({
          measurements: { spinEfficiencyPercent: 72, gyroDegree: null },
        }),
      ],
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
      ruleSet: SAMPLE_RULE_SET,
    });

    const nullResult = assess({
      pitchId: "four-seam",
      throws: [
        makeThrow({
          measurements: { spinEfficiencyPercent: null, gyroDegree: 24 },
        }),
      ],
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
      ruleSet: SAMPLE_RULE_SET,
    });

    expect(nullResult.zones).toEqual([]);
    expect(nullResult.classification).toBe("not-grip");
    expect(nullResult.confidence).toBeLessThan(presentResult.confidence);

    // Also verify partial null coverage when another rule in the RuleSet still fires
    const multiMeasurementRules: RuleSet = {
      version: "test-multi-1",
      rules: [
        ...SAMPLE_RULE_SET.rules,
        {
          id: "four-seam-low-spin-rate",
          pitchIds: ["four-seam"],
          measurement: "totalSpinRpm",
          when: { below: 2000 },
          zones: [{ zoneId: "middle-pad", severity: "yellow", confidence: 0.5 }],
          reason: "Total spin {value} rpm is below {threshold} rpm",
          nextAction: {
            zoneId: "middle-pad",
            summary: "Press firmer with the middle pad",
            detail: "Keep firm middle-finger pressure across the seam at release.",
          },
          confidence: 0.5,
          classification: "grip-focus",
        },
      ],
    };

    const fullEvidence = assess({
      pitchId: "four-seam",
      throws: [
        makeThrow({
          measurements: { spinEfficiencyPercent: 92, totalSpinRpm: 1850 },
        }),
      ],
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
      ruleSet: multiMeasurementRules,
    });

    const missingEfficiencyEvidence = assess({
      pitchId: "four-seam",
      throws: [
        makeThrow({
          measurements: { spinEfficiencyPercent: null, totalSpinRpm: 1850 },
        }),
      ],
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
      ruleSet: multiMeasurementRules,
    });

    expect(missingEfficiencyEvidence.zones).toHaveLength(1);
    expect(missingEfficiencyEvidence.zones[0].triggeringMeasurement).toBe(
      "totalSpinRpm",
    );
    expect(missingEfficiencyEvidence.confidence).toBeLessThan(
      fullEvidence.confidence,
    );
  });

  it("classifies drifting release height across 3+ throws as not-grip and colors nothing", () => {
    const driftingThrows = [
      makeThrow({
        throwId: "sample-throw-1",
        measurements: { spinEfficiencyPercent: 72, releaseHeightFeet: 5.2 },
      }),
      makeThrow({
        throwId: "sample-throw-2",
        measurements: { spinEfficiencyPercent: 72, releaseHeightFeet: 5.8 },
      }),
      makeThrow({
        throwId: "sample-throw-3",
        measurements: { spinEfficiencyPercent: 72, releaseHeightFeet: 6.2 },
      }),
    ];

    const result = assess({
      pitchId: "four-seam",
      throws: driftingThrows,
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
      ruleSet: SAMPLE_RULE_SET,
    });

    expect(result.classification).toBe("not-grip");
    expect(result.nextAction.zoneId).toBeNull();
    expect(result.zones).toEqual([]);
    expect(result.consistency).not.toBeNull();
  });

  it("selects exactly one nextAction by highest severity, then highest confidence, then rule order", () => {
    const tieBreakRules: AssessmentRule[] = [
      {
        id: "rule-yellow-high-conf",
        pitchIds: ["four-seam"],
        measurement: "spinEfficiencyPercent",
        when: { below: 85 },
        zones: [{ zoneId: "index-pad", severity: "yellow" }],
        reason: "Efficiency {value}% below {threshold}%",
        nextAction: {
          zoneId: "index-pad",
          summary: "Yellow action",
          detail: "Adjust index pad.",
        },
        confidence: 0.9,
        classification: "grip-focus",
      },
      {
        id: "rule-red-first-tie",
        pitchIds: ["four-seam"],
        measurement: "spinEfficiencyPercent",
        when: { below: 85 },
        zones: [{ zoneId: "wrist", severity: "red" }],
        reason: "Efficiency {value}% below {threshold}%",
        nextAction: {
          zoneId: "wrist",
          summary: "First red action",
          detail: "Keep the wrist firm.",
        },
        confidence: 0.7,
        classification: "grip-focus",
      },
      {
        id: "rule-red-second-tie",
        pitchIds: ["four-seam"],
        measurement: "totalSpinRpm",
        when: { below: 2300 },
        zones: [{ zoneId: "middle-pad", severity: "red" }],
        reason: "Spin {value} rpm below {threshold} rpm",
        nextAction: {
          zoneId: "middle-pad",
          summary: "Second red action",
          detail: "Press firmer with the middle finger.",
        },
        confidence: 0.7,
        classification: "grip-focus",
      },
    ];

    const result = assess({
      pitchId: "four-seam",
      throws: [makeThrow({ measurements: { spinEfficiencyPercent: 72, totalSpinRpm: 2100 } })],
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
      ruleSet: { version: "tie-test-1", rules: tieBreakRules },
    });

    // Red beats yellow even when yellow has higher confidence, and first red rule beats second red rule on a tie.
    expect(result.nextAction.summary).toBe("First red action");
    expect(result.nextAction.zoneId).toBe("wrist");
  });

  it("leaves unchecked zones absent rather than marking them green", () => {
    const result = assess({
      pitchId: "four-seam",
      throws: [makeThrow({ measurements: { spinEfficiencyPercent: 72 } })],
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
      ruleSet: SAMPLE_RULE_SET,
    });

    const emittedIds = result.zones.map((z) => z.zoneId);
    expect(emittedIds).toEqual(["wrist", "middle-pad", "index-pad", "thumb-pad"]);
    expect(emittedIds).not.toContain("ring-side");
    expect(emittedIds).not.toContain("pinky");
    expect(emittedIds).not.toContain("palm");
  });

  it("handles two-seam, slider, and changeup honestly without reusing four-seam logic", () => {
    // A 72% two-seam is above the conservative 65% floor, so it does not trigger a low-efficiency warning.
    const twoSeam72 = assess({
      pitchId: "two-seam",
      throws: [makeThrow({ pitchId: "two-seam", measurements: { spinEfficiencyPercent: 72 } })],
      zones: instructionZonesForPitch("two-seam"),
      ruleSet: SAMPLE_RULE_SET,
    });
    expect(twoSeam72.zones).toEqual([]);

    // A 58% two-seam triggers the conservative yellow rule with low confidence.
    const twoSeam58 = assess({
      pitchId: "two-seam",
      throws: [makeThrow({ pitchId: "two-seam", measurements: { spinEfficiencyPercent: 58 } })],
      zones: instructionZonesForPitch("two-seam"),
      ruleSet: SAMPLE_RULE_SET,
    });
    expect(twoSeam58.classification).toBe("grip-focus");
    expect(twoSeam58.confidence).toBeLessThanOrEqual(0.4);

    // A slider wants low spin efficiency: 40% is normal for a slider and does not trigger a fastball fault.
    const sliderLowEfficiency = assess({
      pitchId: "slider",
      throws: [makeThrow({ pitchId: "slider", measurements: { spinEfficiencyPercent: 40 } })],
      zones: instructionZonesForPitch("slider"),
      ruleSet: SAMPLE_RULE_SET,
    });
    expect(sliderLowEfficiency.classification).toBe("not-grip");
    expect(sliderLowEfficiency.zones).toEqual([]);

    // A slider with high spin efficiency (78%) inverts the comparison and returns a low-confidence finding.
    const sliderHighEfficiency = assess({
      pitchId: "slider",
      throws: [makeThrow({ pitchId: "slider", measurements: { spinEfficiencyPercent: 78 } })],
      zones: instructionZonesForPitch("slider"),
      ruleSet: SAMPLE_RULE_SET,
    });
    expect(sliderHighEfficiency.classification).toBe("grip-focus");
    expect(sliderHighEfficiency.confidence).toBeLessThanOrEqual(0.35);

    // A changeup throw returns `not-grip` because velocity separation requires a fastball comparison.
    const changeupResult = assess({
      pitchId: "changeup",
      throws: [makeThrow({ pitchId: "changeup", measurements: { spinEfficiencyPercent: 72 } })],
      zones: instructionZonesForPitch("changeup"),
      ruleSet: SAMPLE_RULE_SET,
    });
    expect(changeupResult.classification).toBe("not-grip");
    expect(changeupResult.zones).toEqual([]);
    expect(changeupResult.nextAction.zoneId).toBeNull();
  });

  it("returns null consistency under 3 throws and reports velocity/spin spread for 3+ throws separately from grip focus", () => {
    const singleResult = assess({
      pitchId: "four-seam",
      throws: [makeThrow()],
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
      ruleSet: SAMPLE_RULE_SET,
    });
    expect(singleResult.consistency).toBeNull();

    const threeThrows = [
      makeThrow({
        throwId: "sample-throw-1",
        measurements: { velocityMph: 80.0, totalSpinRpm: 2050, spinEfficiencyPercent: 72, releaseHeightFeet: 5.8 },
      }),
      makeThrow({
        throwId: "sample-throw-2",
        measurements: { velocityMph: 84.5, totalSpinRpm: 2300, spinEfficiencyPercent: 72, releaseHeightFeet: 5.9 },
      }),
      makeThrow({
        throwId: "sample-throw-3",
        measurements: { velocityMph: 82.0, totalSpinRpm: 2150, spinEfficiencyPercent: 72, releaseHeightFeet: 5.85 },
      }),
    ];

    const multiResult = assess({
      pitchId: "four-seam",
      throws: threeThrows,
      zones: FOUR_SEAM_INSTRUCTION_ZONES,
      ruleSet: SAMPLE_RULE_SET,
    });

    expect(multiResult.consistency).toEqual({
      throwCount: 3,
      velocitySpreadMph: 4.5,
      totalSpinSpreadRpm: 250,
      inconsistent: true,
    });
    // Consistency is kept separate from grip focus
    expect(multiResult.classification).toBe("grip-focus");
    expect(multiResult.zones).toHaveLength(4);
    expect(multiResult.prototypeAdvice).toBe(true);
  });
});
