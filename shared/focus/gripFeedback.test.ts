import { describe, expect, it } from "vitest";
import type {
  InstructionZone,
  ZoneId,
  ZoneReach,
} from "../contracts/zones";
import type { ThrowRecord } from "../throwEntry";
import { rapsodo2Throws, sampleSessionThrows } from "./demoFixtures";
import { plan } from "./fitFixtures";
import { GRIP_RULES, GRIP_RULE_VERSION } from "./gripRules";
import { gripFeedback, gripFocusZones } from "./gripFeedback";

// Zones come from the committed grip-plan fixture rather than a new hand
// invented here. That fixture ships thumb-pad as `strained`, so every test
// starts from an all-comfortable copy and sets back only the reach it means
// to exercise.
const EXTRA_TITLES: Partial<Record<ZoneId, string>> = {
  palm: "Palm",
  "ring-side": "Ring finger",
};

function zonesWith(
  reach: Partial<Record<ZoneId, ZoneReach>> = {},
): InstructionZone[] {
  const base: InstructionZone[] = plan.instructionZones.map((zone) => ({
    ...zone,
    reach: "comfortable",
  }));
  const present = new Set(base.map((zone) => zone.zoneId));
  // The four-seam plan fixture carries no palm or ring side, and rules name
  // both, so the fit gate needs reach data for them too.
  for (const [zoneId, title] of Object.entries(EXTRA_TITLES)) {
    if (present.has(zoneId as ZoneId)) continue;
    base.push({
      zoneId: zoneId as ZoneId,
      title: title!,
      instruction: "Supporting contact",
      pressure: "light",
      role: "support",
      reach: "comfortable",
      placement: null,
    });
  }
  return base.map((zone) =>
    reach[zone.zoneId] ? { ...zone, reach: reach[zone.zoneId]! } : zone,
  );
}

// An on-target four-seam throw. Each test overrides only what it exercises.
function throwRecord(
  overrides: Partial<ThrowRecord["measurements"]> = {},
  pitchId = "four-seam",
): ThrowRecord {
  return {
    schemaVersion: "1.0.0",
    throwId: "t-1",
    sessionId: "s-1",
    pitchId,
    recordedAt: "2026-10-18T00:00:00.000Z",
    measurements: {
      velocityMph: 90,
      totalSpinRpm: 2200,
      spinDirectionClock: 12.2,
      spinEfficiencyPercent: 97,
      gyroDegree: null,
      horizontalBreakInches: 0,
      verticalBreakInches: 17,
      releaseHeightFeet: 6,
      rapsodoScore: null,
      ...overrides,
    },
    source: "manual",
    extensions: {},
  };
}

describe("severity prerequisites", () => {
  it("gives the winning thumb and secondary fingers their own short actions", () => {
    const input = { pitchId: "four-seam", throws: rapsodo2Throws("four-seam"), zones: zonesWith() };
    const zones = gripFocusZones(input, gripFeedback(input));
    expect(zones.find((zone) => zone.zoneId === "thumb-pad")).toMatchObject({
      severity: "red", action: "Rest your thumb under the ball, below the gap between your index and middle fingers.",
    });
    for (const zoneId of ["index-pad", "middle-pad"]) {
      expect(zones.find((zone) => zone.zoneId === zoneId)).toMatchObject({
        severity: "yellow", action: "Place your index and middle fingertips on the raised seams.",
      });
    }
  });

  it("does not prescribe a correction for checked-clean regions", () => {
    const input = { pitchId: "four-seam", throws: [throwRecord()], zones: zonesWith() };
    const zones = gripFocusZones(input, gripFeedback(input));
    expect(zones.length).toBeGreaterThan(0);
    for (const zone of zones) expect(zone).not.toHaveProperty("action");
  });

  it("leaves the palm unassessed when low break has no efficiency or gyro reading", () => {
    const input = {
      pitchId: "four-seam",
      throws: [throwRecord({ spinDirectionClock: 12, verticalBreakInches: 10,
        spinEfficiencyPercent: null, gyroDegree: null })],
      zones: zonesWith(),
    };
    const feedback = gripFeedback(input);
    expect(feedback.ruleId).toBe("four-seam-buried");
    expect(gripFocusZones(input, feedback).some((zone) => zone.zoneId === "palm")).toBe(false);
  });

  it("colors the palm when low break has the required in-range efficiency reading", () => {
    const input = {
      pitchId: "four-seam",
      throws: [throwRecord({ spinDirectionClock: 12, verticalBreakInches: 10 })],
      zones: zonesWith(),
    };
    const feedback = gripFeedback(input);
    expect(feedback.ruleId).toBe("four-seam-buried");
    expect(gripFocusZones(input, feedback).find((zone) => zone.zoneId === "palm")?.severity).toBe("red");
  });
});

describe("no-data", () => {
  it("returns no-data and names no zone when there are no throws", () => {
    const result = gripFeedback({
      pitchId: "four-seam",
      throws: [],
      zones: zonesWith(),
    });
    expect(result.kind).toBe("no-data");
    expect(result.zones).toEqual([]);
    expect(result.change).toBeNull();
    expect(result.expect).toBeNull();
    expect(result.ruleId).toBeNull();
    expect(result.ruleVersion).toBe(GRIP_RULE_VERSION);
  });
});

describe("fit gate", () => {
  // An axis at 1:30 trips four-seam-axis, whose only zone is the thumb pad.
  const offAxis = [throwRecord({ spinDirectionClock: 1.5 })];

  it("suppresses a rule whose named zone is unreachable", () => {
    const result = gripFeedback({
      pitchId: "four-seam",
      throws: offAxis,
      zones: zonesWith({ "thumb-pad": "unreachable" }),
    });
    expect(result.kind).toBe("fit");
    expect(result.change).toBeNull();
    expect(result.expect).toBeNull();
    expect(result.ruleId).toBeNull();
    expect(result.zones).toContain("thumb-pad");
  });

  it("treats strained exactly like unreachable", () => {
    const result = gripFeedback({
      pitchId: "four-seam",
      throws: offAxis,
      zones: zonesWith({ "thumb-pad": "strained" }),
    });
    expect(result.kind).toBe("fit");
    expect(result.change).toBeNull();
    expect(result.zones).toContain("thumb-pad");
  });

  it("gives the technique instruction when the same zone is comfortable", () => {
    const result = gripFeedback({
      pitchId: "four-seam",
      throws: offAxis,
      zones: zonesWith(),
    });
    expect(result.kind).toBe("change");
    expect(result.ruleId).toBe("four-seam-axis");
  });

  it("ignores a fit problem on a zone no firing rule names", () => {
    // The axis rule names the thumb only, so a strained ring finger is not
    // this throw's problem.
    const result = gripFeedback({
      pitchId: "four-seam",
      throws: offAxis,
      zones: zonesWith({ "ring-side": "unreachable" }),
    });
    expect(result.kind).toBe("change");
  });

  it("runs before ranking: a fit problem beats a firing deviation", () => {
    // Axis off (thumb pad, unreachable) and spin per mph low (index and
    // middle, both comfortable). The purchase tip must not be offered.
    const result = gripFeedback({
      pitchId: "four-seam",
      throws: [
        throwRecord({ spinDirectionClock: 1.5, totalSpinRpm: 1440 }),
      ],
      zones: zonesWith({ "thumb-pad": "unreachable" }),
    });
    expect(result.kind).toBe("fit");
    expect(result.ruleId).toBeNull();
  });
});

describe("baseline gate", () => {
  const changeup = [
    throwRecord(
      { velocityMph: 86, totalSpinRpm: 2100, spinDirectionClock: 1.5 },
      "changeup",
    ),
  ];

  it("returns baseline for a changeup with no baseline throws", () => {
    const result = gripFeedback({
      pitchId: "changeup",
      throws: changeup,
      zones: zonesWith(),
    });
    expect(result.kind).toBe("baseline");
    expect(result.change).toBeNull();
    expect(result.zones).toEqual([]);
  });

  it("returns baseline for an empty baseline array too", () => {
    const result = gripFeedback({
      pitchId: "changeup",
      throws: changeup,
      zones: zonesWith(),
      baseline: [],
    });
    expect(result.kind).toBe("baseline");
  });

  it("judges the changeup once a baseline fastball exists", () => {
    const result = gripFeedback({
      pitchId: "changeup",
      throws: changeup,
      zones: zonesWith(),
      baseline: [throwRecord()],
    });
    // 90 against 86 is 4 mph of separation, short of the sourced floor.
    expect(result.kind).toBe("change");
    expect(result.ruleId).toBe("changeup-separation");
  });
});

describe("drift gate", () => {
  it("does not turn missing screenshot heights into a release drift", () => {
    const input = { pitchId: "four-seam", zones: zonesWith(),
      throws: [throwRecord({ releaseHeightFeet: 5 }),
        throwRecord({ releaseHeightFeet: null }), throwRecord({ releaseHeightFeet: 7 })] };
    expect(gripFeedback(input).kind).not.toBe("drift");
  });

  function drifting(heights: readonly number[]): ThrowRecord[] {
    return heights.map((releaseHeightFeet) =>
      throwRecord({ releaseHeightFeet }),
    );
  }

  it("returns drift and names no finger", () => {
    const result = gripFeedback({
      pitchId: "four-seam",
      throws: drifting([6, 6.2, 6.8]),
      zones: zonesWith(),
    });
    expect(result.kind).toBe("drift");
    expect(result.zones).toEqual([]);
    expect(result.change).toBeNull();
    expect(result.ruleId).toBeNull();
  });

  it("does not fire at or below the shipped half-foot spread", () => {
    const result = gripFeedback({
      pitchId: "four-seam",
      throws: drifting([6, 6.25, 6.5]),
      zones: zonesWith(),
    });
    expect(result.kind).toBe("on-target");
  });

  it("needs three throws, like the shipped behaviour", () => {
    const result = gripFeedback({
      pitchId: "four-seam",
      throws: drifting([6, 8]),
      zones: zonesWith(),
    });
    expect(result.kind).not.toBe("drift");
  });

  it("outranks a firing deviation, because drift is an arm problem", () => {
    const result = gripFeedback({
      pitchId: "four-seam",
      throws: [
        throwRecord({ releaseHeightFeet: 6, spinDirectionClock: 1.5 }),
        throwRecord({ releaseHeightFeet: 6.4, spinDirectionClock: 1.5 }),
        throwRecord({ releaseHeightFeet: 6.9, spinDirectionClock: 1.5 }),
      ],
      zones: zonesWith(),
    });
    expect(result.kind).toBe("drift");
  });
});

describe("ranking", () => {
  it("returns exactly one change, the largest normalised deviation", () => {
    // Axis 1:30 misses by one hour (magnitude 1). Spin per mph of 16 misses
    // the floor by 6 (magnitude 3). The bigger miss wins.
    const result = gripFeedback({
      pitchId: "four-seam",
      throws: [
        throwRecord({ spinDirectionClock: 1.5, totalSpinRpm: 1440 }),
      ],
      zones: zonesWith(),
    });
    expect(result.kind).toBe("change");
    expect(result.ruleId).toBe("four-seam-purchase");
    expect(result.change).toBe(
      GRIP_RULES.find((r) => r.id === "four-seam-purchase")!.change,
    );
    expect(result.expect).not.toBeNull();
    expect(result.source).not.toBeNull();
  });

  it("lets the axis win when its miss is the larger one", () => {
    // Axis 4:00 misses by 3.5 hours. Spin per mph of 21 misses by 1.
    const result = gripFeedback({
      pitchId: "four-seam",
      throws: [
        throwRecord({ spinDirectionClock: 4, totalSpinRpm: 1890 }),
      ],
      zones: zonesWith(),
    });
    expect(result.ruleId).toBe("four-seam-axis");
  });

  it("breaks ties by GRIP_RULES table order", () => {
    // Spin per mph 20 is 2 under its floor, scaled to 1. Horizontal break 7
    // is 4 past its range, also scaled to 1. four-seam-purchase is the
    // earlier row, so it wins.
    const input = {
      pitchId: "four-seam",
      throws: [throwRecord({ totalSpinRpm: 1800, horizontalBreakInches: 7 })],
      zones: zonesWith(),
    };
    const result = gripFeedback(input);
    expect(result.ruleId).toBe("four-seam-purchase");
    const purchase = GRIP_RULES.findIndex((r) => r.id === "four-seam-purchase");
    const cut = GRIP_RULES.findIndex((r) => r.id === "four-seam-cut");
    expect(purchase).toBeLessThan(cut);
    expect(gripFeedback(input)).toEqual(result);
  });

  it("returns on-target when rules exist for the pitch and none fire", () => {
    const result = gripFeedback({
      pitchId: "four-seam",
      throws: [throwRecord()],
      zones: zonesWith(),
    });
    expect(result.kind).toBe("on-target");
    expect(result.change).toBeNull();
    expect(result.ruleId).toBeNull();
    expect(result.zones).toEqual([]);
  });
});

describe("handedness", () => {
  // A left-hander's two-seam runs to the other side and spins the other way
  // round the clock. targetFor mirrors both, so the same readings must read
  // on target for a lefty and off axis for a righty.
  const lefty = [
    throwRecord(
      {
        spinDirectionClock: 10.5,
        spinEfficiencyPercent: 85,
        horizontalBreakInches: -15,
        verticalBreakInches: 12,
      },
      "two-seam",
    ),
  ];

  it("threads handedness through to targetFor and changes the verdict", () => {
    const asLeft = gripFeedback({
      pitchId: "two-seam",
      throws: lefty,
      zones: zonesWith(),
      handedness: "left",
    });
    const asRight = gripFeedback({
      pitchId: "two-seam",
      throws: lefty,
      zones: zonesWith(),
      handedness: "right",
    });
    expect(asLeft.kind).toBe("on-target");
    expect(asRight.kind).toBe("change");
    expect(asRight.ruleId).toBe("two-seam-axis");
  });

  it("defaults to right-handed when the field is omitted", () => {
    const omitted = gripFeedback({
      pitchId: "two-seam",
      throws: lefty,
      zones: zonesWith(),
    });
    const explicit = gripFeedback({
      pitchId: "two-seam",
      throws: lefty,
      zones: zonesWith(),
      handedness: "right",
    });
    expect(omitted).toEqual(explicit);
  });
});

describe("every outcome", () => {
  const cases: { kind: string; result: ReturnType<typeof gripFeedback> }[] = [
    {
      kind: "no-data",
      result: gripFeedback({
        pitchId: "four-seam",
        throws: [],
        zones: zonesWith(),
      }),
    },
    {
      kind: "fit",
      result: gripFeedback({
        pitchId: "four-seam",
        throws: [throwRecord({ spinDirectionClock: 1.5 })],
        zones: zonesWith({ "thumb-pad": "unreachable" }),
      }),
    },
    {
      kind: "baseline",
      result: gripFeedback({
        pitchId: "changeup",
        throws: [throwRecord({}, "changeup")],
        zones: zonesWith(),
      }),
    },
    {
      kind: "drift",
      result: gripFeedback({
        pitchId: "four-seam",
        throws: [
          throwRecord({ releaseHeightFeet: 6 }),
          throwRecord({ releaseHeightFeet: 6.3 }),
          throwRecord({ releaseHeightFeet: 6.9 }),
        ],
        zones: zonesWith(),
      }),
    },
    {
      kind: "change",
      result: gripFeedback({
        pitchId: "four-seam",
        throws: [throwRecord({ spinDirectionClock: 1.5 })],
        zones: zonesWith(),
      }),
    },
    {
      kind: "on-target",
      result: gripFeedback({
        pitchId: "four-seam",
        throws: [throwRecord()],
        zones: zonesWith(),
      }),
    },
  ];

  it("covers all six kinds", () => {
    expect(cases.map((c) => c.result.kind)).toEqual(cases.map((c) => c.kind));
  });

  it("populates measured, headline and ruleVersion everywhere", () => {
    for (const { kind, result } of cases) {
      expect(result.measured.trim(), kind).not.toBe("");
      expect(result.headline.trim(), kind).not.toBe("");
      expect(result.ruleVersion, kind).toBe(GRIP_RULE_VERSION);
    }
  });

  it("never names the wrist", () => {
    for (const { kind, result } of cases) {
      expect(result.zones, kind).not.toContain("wrist");
    }
  });
});

describe("demo paths", () => {
  // The three paths the demo is shown on. The property worth protecting is
  // not any single rule id but that the three differ: one engine, three
  // inputs, three different changes naming three different contacts.
  const pathOne = gripFeedback({
    pitchId: "four-seam",
    throws: rapsodo2Throws("four-seam"),
    zones: zonesWith(),
  });
  const pathTwo = gripFeedback({
    pitchId: "two-seam",
    throws: rapsodo2Throws("two-seam"),
    zones: zonesWith(),
  });
  const pathThree = gripFeedback({
    pitchId: "four-seam",
    throws: sampleSessionThrows("four-seam"),
    zones: zonesWith(),
  });

  it("path one: the rapsodo2 reading as a four-seam names the thumb", () => {
    expect(pathOne.kind).toBe("change");
    expect(pathOne.ruleId).toBe("four-seam-axis");
    expect(pathOne.zones).toEqual(["thumb-pad"]);
    expect(pathOne.change).toMatch(/thumb/i);
  });

  it("path two: the same reading as a two-seam cites seam purchase", () => {
    expect(pathTwo.kind).toBe("change");
    expect(pathTwo.ruleId).toBe("two-seam-purchase");
    expect(pathTwo.zones).toContain("index-pad");
    expect(pathTwo.zones).toContain("middle-pad");
    expect(pathTwo.change).toMatch(/seam/i);
    expect(pathTwo.change).toMatch(/pad/i);
    // Same numbers, different intent, different change to try.
    expect(pathTwo.ruleId).not.toBe(pathOne.ruleId);
  });

  // The design predicts this path fires the seam-orientation rule,
  // four-seam-efficiency. It returns four-seam-cut instead, and the cause is
  // the fixture rather than the rules.
  //
  // sampleThrowSession() originally carried no break values: its first row
  // was ["82.4", "2180", "12:30", "84", "5.8"]. Commit f731f7a ("Add
  // complete Rapsodo throw measurements") pasted 18.6 inches of horizontal
  // and 13.8 of vertical break into all three rows. Those are rapsodo2.webp's
  // break numbers, off a different pitch. A four-seam spinning at 12:30
  // cannot produce 18.6 inches of arm-side run, so the sample fixture is
  // physically self-contradictory and four-seam-cut is correctly flagging
  // the largest symptom in it.
  //
  // This asserts what the engine actually does. Neither the sample rows nor
  // any SCALE value is being bent to make the design's prediction come true:
  // tuning a ranking constant so a demo matches a document would hide the
  // bad fixture instead of fixing it. shared/throwEntry.ts is Carter's file.
  // Change this assertion to four-seam-efficiency once those break values
  // are corrected there.
  it("path three: the sample session as a four-seam is a third rule", () => {
    expect(pathThree.kind).toBe("change");
    expect(pathThree.ruleId).toBe("four-seam-cut");
  });

  it("returns three different rule ids, which is the point of the demo", () => {
    const ids = [pathOne.ruleId, pathTwo.ruleId, pathThree.ruleId];
    expect(ids.every((id) => id !== null)).toBe(true);
    expect(new Set(ids).size).toBe(3);
  });

  it("never names the wrist on any demo path", () => {
    for (const result of [pathOne, pathTwo, pathThree]) {
      expect(result.zones).not.toContain("wrist");
    }
  });

  it("is deterministic across rebuilt fixtures", () => {
    const again = gripFeedback({
      pitchId: "four-seam",
      throws: rapsodo2Throws("four-seam"),
      zones: zonesWith(),
    });
    expect(again).toEqual(pathOne);
  });
});

describe("determinism", () => {
  it("returns deeply equal results and does not mutate its input", () => {
    const throws = [
      throwRecord({ spinDirectionClock: 1.5, totalSpinRpm: 1440 }),
      throwRecord({ spinDirectionClock: 1.6, totalSpinRpm: 1460 }),
    ];
    const zones = zonesWith();
    const baseline = [throwRecord()];
    const input = { pitchId: "four-seam", throws, zones, baseline };
    const before = JSON.stringify(input);

    const first = gripFeedback(input);
    const second = gripFeedback(input);

    expect(second).toEqual(first);
    expect(JSON.stringify(second)).toBe(JSON.stringify(first));
    expect(JSON.stringify(input)).toBe(before);
  });
});
