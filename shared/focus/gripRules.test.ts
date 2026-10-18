import { describe, expect, it } from "vitest";
import { isZoneId } from "../contracts/zones";
import { GRIP_RULES, GRIP_RULE_VERSION, type GripRule } from "./gripRules";
import type { DerivedMetrics } from "./metrics";
import { targetFor } from "./targets";

// On-target four-seam reading. Each test overrides only the field it exercises.
function metrics(overrides: Partial<DerivedMetrics> = {}): DerivedMetrics {
  return {
    throwCount: 5,
    velocityMph: 90,
    totalSpinRpm: 2200,
    spinEfficiencyPercent: 97,
    activeSpinRpm: 2134,
    spinPerMph: 24.4,
    spinDirectionClock: 12.2,
    horizontalBreakInches: 0,
    verticalBreakInches: 17,
    ...overrides,
  };
}

const target = targetFor("four-seam", "right")!;

function rule(id: string): GripRule {
  const found = GRIP_RULES.find((r) => r.id === id);
  if (!found) throw new Error(`missing rule ${id}`);
  return found;
}

function detect(id: string, m: DerivedMetrics) {
  return rule(id).detect(m, target, null);
}

describe("rule shape", () => {
  it("has a version", () => {
    expect(GRIP_RULE_VERSION).toBe("demo-rules-1");
  });

  it("has unique ids", () => {
    const ids = GRIP_RULES.map((r) => r.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("gives every rule zones, change, expect and source", () => {
    for (const r of GRIP_RULES) {
      expect(r.pitchIds.length).toBeGreaterThan(0);
      expect(r.zones.length).toBeGreaterThan(0);
      expect(r.change.trim()).not.toBe("");
      expect(r.expect.trim()).not.toBe("");
      expect(r.source.trim()).not.toBe("");
    }
  });

  it("uses only real zone ids", () => {
    for (const r of GRIP_RULES) {
      for (const zone of r.zones) expect(isZoneId(zone)).toBe(true);
    }
  });

  it("never names the wrist, which is not a grip contact", () => {
    for (const r of GRIP_RULES) expect(r.zones).not.toContain("wrist");
  });
});

describe("four-seam rules", () => {
  it("returns null for every rule on on-target metrics", () => {
    for (const r of GRIP_RULES) expect(detect(r.id, metrics())).toBeNull();
  });

  it("axis: fires outside the range and not inside", () => {
    expect(detect("four-seam-axis", metrics({ spinDirectionClock: 1.5 })))
      .not.toBeNull();
    expect(detect("four-seam-axis", metrics({ spinDirectionClock: 12.4 })))
      .toBeNull();
  });

  it("axis: handles the clock wrap", () => {
    // 0.2 is 12:12 on the dial, which is inside 12:00 to 12:30.
    expect(detect("four-seam-axis", metrics({ spinDirectionClock: 0.2 })))
      .toBeNull();
    const d = detect("four-seam-axis", metrics({ spinDirectionClock: 11 }))!;
    expect(d.magnitude).toBeCloseTo(1, 5);
  });

  it("axis: stays quiet when the reading is missing", () => {
    expect(detect("four-seam-axis", metrics({ spinDirectionClock: null })))
      .toBeNull();
  });

  it("efficiency: fires when low and axis fine, null otherwise", () => {
    const d = detect("four-seam-efficiency", metrics({ spinEfficiencyPercent: 85 }));
    expect(d).not.toBeNull();
    expect(d!.summary).toContain("85");
    expect(detect("four-seam-efficiency", metrics({ spinEfficiencyPercent: 96 })))
      .toBeNull();
  });

  it("efficiency: defers to the axis rule when the axis is off", () => {
    const m = metrics({ spinEfficiencyPercent: 85, spinDirectionClock: 1.5 });
    expect(detect("four-seam-efficiency", m)).toBeNull();
    expect(detect("four-seam-axis", m)).not.toBeNull();
  });

  it("purchase: fires when spin per mph is low, null otherwise", () => {
    expect(detect("four-seam-purchase", metrics({ spinPerMph: 19 })))
      .not.toBeNull();
    expect(detect("four-seam-purchase", metrics({ spinPerMph: 23 })))
      .toBeNull();
    expect(detect("four-seam-purchase", metrics({ spinPerMph: null })))
      .toBeNull();
  });

  it("cut: fires on sideways break either way, null near zero", () => {
    expect(detect("four-seam-cut", metrics({ horizontalBreakInches: 8 })))
      .not.toBeNull();
    expect(detect("four-seam-cut", metrics({ horizontalBreakInches: -8 })))
      .not.toBeNull();
    expect(detect("four-seam-cut", metrics({ horizontalBreakInches: 2 })))
      .toBeNull();
  });

  it("buried: fires on low vertical break with good efficiency", () => {
    expect(detect("four-seam-buried", metrics({ verticalBreakInches: 10 })))
      .not.toBeNull();
    expect(detect("four-seam-buried", metrics({ verticalBreakInches: 16 })))
      .toBeNull();
  });

  it("buried: defers when efficiency is outside target", () => {
    const m = metrics({ verticalBreakInches: 10, spinEfficiencyPercent: 85 });
    expect(detect("four-seam-buried", m)).toBeNull();
    expect(detect("four-seam-efficiency", m)).not.toBeNull();
  });

  it("buried: stays silent when the axis is off, even with very low vertical break", () => {
    const m = metrics({ verticalBreakInches: 8, spinDirectionClock: 1.5 });
    expect(detect("four-seam-buried", m)).toBeNull();
  });
});

describe("magnitude", () => {
  it("is zero on target by returning null, and rises with distance", () => {
    const near = detect("four-seam-purchase", metrics({ spinPerMph: 21 }))!;
    const far = detect("four-seam-purchase", metrics({ spinPerMph: 16 }))!;
    expect(far.magnitude).toBeGreaterThan(near.magnitude);
    expect(near.magnitude).toBeGreaterThan(0);
  });

  it("is comparable across units: one scale unit of error scores 1", () => {
    // 1 hour past 12:30, 2 below spin per mph, 5 points below efficiency,
    // 4 inches past the break range.
    const axis = detect("four-seam-axis", metrics({ spinDirectionClock: 1.5 }))!;
    const purchase = detect("four-seam-purchase", metrics({ spinPerMph: 20 }))!;
    const eff = detect("four-seam-efficiency", metrics({ spinEfficiencyPercent: 90 }))!;
    const cut = detect("four-seam-cut", metrics({ horizontalBreakInches: 7 }))!;
    for (const d of [axis, purchase, eff, cut]) {
      expect(d.magnitude).toBeCloseTo(1, 5);
    }
  });

  it("ranks the real anchor: axis outranks purchase", () => {
    const anchor = metrics({
      velocityMph: 77.3,
      totalSpinRpm: 1642,
      spinDirectionClock: 1.9333,
      spinEfficiencyPercent: 93.8,
      verticalBreakInches: 13.8,
      horizontalBreakInches: 18.6,
      spinPerMph: 21.2,
    });
    const axis = detect("four-seam-axis", anchor)!;
    const purchase = detect("four-seam-purchase", anchor)!;
    expect(axis.magnitude).toBeGreaterThan(purchase.magnitude);
  });
});

describe("two-seam rules", () => {
  // On-target two-seam reading for a right-handed pitcher.
  function twoSeam(overrides: Partial<DerivedMetrics> = {}): DerivedMetrics {
    return metrics({
      spinEfficiencyPercent: 85,
      spinPerMph: 24,
      spinDirectionClock: 1.5,
      horizontalBreakInches: 15,
      verticalBreakInches: 12,
      ...overrides,
    });
  }
  const twoSeamRight = targetFor("two-seam", "right")!;
  const twoSeamLeft = targetFor("two-seam", "left")!;

  function detectTwo(
    id: string,
    m: DerivedMetrics,
    t = twoSeamRight,
  ) {
    return rule(id).detect(m, t, null);
  }

  const TWO_SEAM_IDS = [
    "two-seam-axis",
    "two-seam-run",
    "two-seam-efficiency",
    "two-seam-purchase",
  ];

  it("is silent on every two-seam rule for on-target metrics", () => {
    for (const id of TWO_SEAM_IDS) expect(detectTwo(id, twoSeam())).toBeNull();
  });

  it("names index and middle (or thumb for efficiency), never the wrist", () => {
    for (const id of TWO_SEAM_IDS) {
      const r = rule(id);
      expect(r.pitchIds).toEqual(["two-seam"]);
      expect(r.zones).not.toContain("wrist");
    }
    expect(rule("two-seam-axis").zones).toEqual(["index-pad", "middle-pad"]);
    expect(rule("two-seam-run").zones).toEqual(["index-pad", "middle-pad"]);
    expect(rule("two-seam-purchase").zones).toEqual(["index-pad", "middle-pad"]);
    expect(rule("two-seam-efficiency").zones).toEqual(["thumb-pad"]);
  });

  it("axis: fires at a four-seam axis and not inside the range", () => {
    expect(detectTwo("two-seam-axis", twoSeam({ spinDirectionClock: 12.2 })))
      .not.toBeNull();
    expect(detectTwo("two-seam-axis", twoSeam({ spinDirectionClock: 1.8 })))
      .toBeNull();
    expect(detectTwo("two-seam-axis", twoSeam({ spinDirectionClock: null })))
      .toBeNull();
  });

  it("run: fires when break is low and axis is fine", () => {
    const d = detectTwo("two-seam-run", twoSeam({ horizontalBreakInches: 4 }))!;
    expect(d).not.toBeNull();
    expect(d.summary).toContain("4");
    expect(detectTwo("two-seam-run", twoSeam({ horizontalBreakInches: 15 })))
      .toBeNull();
    expect(detectTwo("two-seam-run", twoSeam({ horizontalBreakInches: null })))
      .toBeNull();
  });

  it("run: defers to the axis rule when the axis is off", () => {
    const m = twoSeam({ horizontalBreakInches: 4, spinDirectionClock: 12.2 });
    expect(detectTwo("two-seam-run", m)).toBeNull();
    expect(detectTwo("two-seam-axis", m)).not.toBeNull();
  });

  it("run: measures against the mirrored range for a left-handed pitcher", () => {
    const weak = twoSeam({ horizontalBreakInches: -4, spinDirectionClock: 10.5 });
    const good = twoSeam({ horizontalBreakInches: -15, spinDirectionClock: 10.5 });
    expect(detectTwo("two-seam-run", weak, twoSeamLeft)).not.toBeNull();
    expect(detectTwo("two-seam-run", good, twoSeamLeft)).toBeNull();
    // +4 is the wrong way for a lefty, so the run is weak there too.
    expect(
      detectTwo(
        "two-seam-run",
        twoSeam({ horizontalBreakInches: 4, spinDirectionClock: 10.5 }),
        twoSeamLeft,
      ),
    ).not.toBeNull();
  });

  it("run: does not tell a pitcher with plenty of run to add more", () => {
    expect(detectTwo("two-seam-run", twoSeam({ horizontalBreakInches: 24 })))
      .toBeNull();
    expect(
      detectTwo(
        "two-seam-run",
        twoSeam({ horizontalBreakInches: -24, spinDirectionClock: 10.5 }),
        twoSeamLeft,
      ),
    ).toBeNull();
  });

  it("efficiency: fires when low and axis fine, defers when axis is off", () => {
    expect(detectTwo("two-seam-efficiency", twoSeam({ spinEfficiencyPercent: 60 })))
      .not.toBeNull();
    expect(detectTwo("two-seam-efficiency", twoSeam({ spinEfficiencyPercent: 80 })))
      .toBeNull();
    const off = twoSeam({ spinEfficiencyPercent: 60, spinDirectionClock: 12.2 });
    expect(detectTwo("two-seam-efficiency", off)).toBeNull();
    expect(detectTwo("two-seam-axis", off)).not.toBeNull();
  });

  it("purchase: fires when spin per mph is low, regardless of axis", () => {
    expect(detectTwo("two-seam-purchase", twoSeam({ spinPerMph: 19 })))
      .not.toBeNull();
    expect(
      detectTwo("two-seam-purchase", twoSeam({ spinPerMph: 19, spinDirectionClock: 12.2 })),
    ).not.toBeNull();
    expect(detectTwo("two-seam-purchase", twoSeam({ spinPerMph: 23 })))
      .toBeNull();
    expect(detectTwo("two-seam-purchase", twoSeam({ spinPerMph: null })))
      .toBeNull();
  });
});

describe("slider rules", () => {
  // Gyro slider: low efficiency is correct for this pitch.
  function slider(overrides: Partial<DerivedMetrics> = {}): DerivedMetrics {
    return metrics({
      velocityMph: 84,
      spinEfficiencyPercent: 8,
      spinDirectionClock: 3,
      horizontalBreakInches: -2,
      verticalBreakInches: 2,
      ...overrides,
    });
  }
  const sliderTarget = targetFor("slider", "right")!;
  const detectSlider = (id: string, m: DerivedMetrics) =>
    rule(id).detect(m, sliderTarget, null);
  const sliderRules = GRIP_RULES.filter((r) => r.pitchIds.includes("slider"));

  it("has exactly the efficiency rule, since no spin-per-mph or break target exists", () => {
    expect(sliderRules.map((r) => r.id)).toEqual(["slider-efficiency"]);
  });

  it("efficiency: fires above the ceiling and names the reading", () => {
    const d = detectSlider(
      "slider-efficiency",
      slider({ spinEfficiencyPercent: 70 }),
    )!;
    expect(d).not.toBeNull();
    expect(d.summary).toContain("70");
    expect(
      detectSlider("slider-efficiency", slider({ spinEfficiencyPercent: 36 })),
    ).not.toBeNull();
  });

  it("efficiency: is silent at a genuine gyro slider reading and at the ceiling", () => {
    expect(detectSlider("slider-efficiency", slider())).toBeNull();
    expect(
      detectSlider("slider-efficiency", slider({ spinEfficiencyPercent: 35 })),
    ).toBeNull();
    expect(
      detectSlider("slider-efficiency", slider({ spinEfficiencyPercent: null })),
    ).toBeNull();
  });

  it("targets the index pad and never the wrist", () => {
    expect(rule("slider-efficiency").zones).toEqual(["index-pad"]);
    for (const r of sliderRules) expect(r.zones).not.toContain("wrist");
  });

  it("never asks the index finger to drive, press or get purchase", () => {
    for (const r of sliderRules) {
      if (!/index/i.test(r.change)) continue;
      expect(r.change).toMatch(/rest|relax/i);
      expect(r.change).not.toMatch(/drive|press|squeeze|push|purchase|grip/i);
    }
  });
});

describe("changeup rules", () => {
  // A changeup has no absolute target. Every reading below is judged against
  // the same pitcher's own fastball in the same session.
  function changeup(overrides: Partial<DerivedMetrics> = {}): DerivedMetrics {
    return metrics({
      velocityMph: 78,
      totalSpinRpm: 1700,
      spinEfficiencyPercent: 90,
      spinPerMph: 21.8,
      spinDirectionClock: 1.5,
      horizontalBreakInches: 14,
      verticalBreakInches: 8,
      ...overrides,
    });
  }
  // The pitcher's own fastball: 90 mph, 2200 rpm, 24.4 spin per mph.
  const fastball = metrics();
  const changeupRight = targetFor("changeup", "right")!;
  const changeupLeft = targetFor("changeup", "left")!;

  function detectChangeup(
    id: string,
    m: DerivedMetrics,
    baseline: DerivedMetrics | null = fastball,
    t = changeupRight,
  ) {
    return rule(id).detect(m, t, baseline);
  }

  const changeupRules = GRIP_RULES.filter((r) =>
    r.pitchIds.includes("changeup"),
  );
  // Fade needs a break direction the changeup target does not carry, and a
  // squeezed loop cannot be seen from ball flight. Both are cut, so two rows.
  const CHANGEUP_IDS = ["changeup-separation", "changeup-spin"];

  it("has exactly the separation and spin rules", () => {
    expect(changeupRules.map((r) => r.id)).toEqual(CHANGEUP_IDS);
  });

  it("is silent on every changeup rule for an on-target changeup", () => {
    for (const id of CHANGEUP_IDS) expect(detectChangeup(id, changeup())).toBeNull();
  });

  it("names only the changeup's own contacts, never the wrist", () => {
    // Per handInstructions the changeup's drivers are middle and ring, not
    // the index-middle pair, and the index-thumb loop sits off the top.
    const CHANGEUP_ZONES = [
      "middle-pad",
      "ring-side",
      "index-pad",
      "thumb-pad",
      "palm",
      "pinky",
    ];
    for (const r of changeupRules) {
      expect(r.pitchIds).toEqual(["changeup"]);
      expect(r.zones).not.toContain("wrist");
      for (const zone of r.zones) {
        expect(isZoneId(zone)).toBe(true);
        expect(CHANGEUP_ZONES).toContain(zone);
      }
    }
    expect(rule("changeup-separation").zones).toEqual(["palm"]);
    expect(rule("changeup-spin").zones).toEqual(["index-pad"]);
  });

  it("every changeup rule needs a baseline and is silent without one", () => {
    for (const id of CHANGEUP_IDS) {
      expect(detectChangeup(id, changeup({ velocityMph: 88, spinPerMph: 30 }), null))
        .toBeNull();
    }
  });

  it("separation: fires when the changeup is under 8 mph off the fastball", () => {
    const d = detectChangeup("changeup-separation", changeup({ velocityMph: 86 }))!;
    expect(d).not.toBeNull();
    expect(d.summary).toContain("4");
  });

  it("separation: is silent when the separation is comfortably over", () => {
    expect(detectChangeup("changeup-separation", changeup({ velocityMph: 76 })))
      .toBeNull();
  });

  it("separation: is silent at exactly 8 mph, as every other rule is at its bound", () => {
    expect(detectChangeup("changeup-separation", changeup({ velocityMph: 82 })))
      .toBeNull();
    // One tenth inside the bound does fire, so the boundary is the only quiet
    // point, matching how distanceOutside treats the slider ceiling at 35.
    expect(detectChangeup("changeup-separation", changeup({ velocityMph: 82.1 })))
      .not.toBeNull();
  });

  it("separation: grows as the changeup creeps toward the fastball", () => {
    const near = detectChangeup("changeup-separation", changeup({ velocityMph: 84 }))!;
    const far = detectChangeup("changeup-separation", changeup({ velocityMph: 90 }))!;
    expect(far.magnitude).toBeGreaterThan(near.magnitude);
  });

  it("separation: is silent when either velocity is missing", () => {
    expect(detectChangeup("changeup-separation", changeup({ velocityMph: null })))
      .toBeNull();
    expect(
      detectChangeup(
        "changeup-separation",
        changeup({ velocityMph: 88 }),
        metrics({ velocityMph: null }),
      ),
    ).toBeNull();
  });

  it("separation: reads identically for a left-handed pitcher", () => {
    // The 8 mph is a difference, not a direction, so mirroring must not touch
    // it. A mirrored threshold would quietly change the verdict here.
    const m = changeup({ velocityMph: 86 });
    const right = detectChangeup("changeup-separation", m, fastball, changeupRight)!;
    const left = detectChangeup("changeup-separation", m, fastball, changeupLeft)!;
    expect(left).toEqual(right);
    expect(left.magnitude).toBeGreaterThan(0);
    // And an on-target changeup stays quiet for a lefty too.
    expect(
      detectChangeup("changeup-separation", changeup(), fastball, changeupLeft),
    ).toBeNull();
  });

  it("spin: fires when spin per mph sits above the pitcher's own fastball", () => {
    const d = detectChangeup("changeup-spin", changeup({ spinPerMph: 26.4 }))!;
    expect(d).not.toBeNull();
    expect(d.summary).toContain("26.4");
    expect(d.magnitude).toBeCloseTo(1, 5);
  });

  it("spin: is silent at or below the fastball's spin per mph", () => {
    expect(detectChangeup("changeup-spin", changeup({ spinPerMph: 24.4 })))
      .toBeNull();
    expect(detectChangeup("changeup-spin", changeup({ spinPerMph: 20 })))
      .toBeNull();
  });

  it("spin: is silent when either spin per mph is missing", () => {
    expect(detectChangeup("changeup-spin", changeup({ spinPerMph: null })))
      .toBeNull();
    expect(
      detectChangeup(
        "changeup-spin",
        changeup({ spinPerMph: 30 }),
        metrics({ spinPerMph: null }),
      ),
    ).toBeNull();
  });
});
