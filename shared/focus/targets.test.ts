import { describe, expect, it } from "vitest";
import {
  PITCH_TARGETS,
  targetFor,
  type PitchTarget,
  type Range,
} from "./targets";

const PITCH_IDS = ["four-seam", "two-seam", "slider", "changeup"];
const HANDS = ["left", "right"] as const;
const RANGE_KEYS = [
  "axisClock",
  "efficiencyPercent",
  "horizontalBreakInches",
  "verticalBreakInches",
  "spinPerMph",
] as const;

function rangesOf(target: PitchTarget): Range[] {
  return RANGE_KEYS.map((key) => target[key]).filter(
    (range): range is Range => range !== undefined,
  );
}

describe("PITCH_TARGETS", () => {
  it("covers exactly the four pitches", () => {
    expect(Object.keys(PITCH_TARGETS).sort()).toEqual([...PITCH_IDS].sort());
  });

  it("names a source for every entry", () => {
    for (const id of PITCH_IDS) {
      expect(PITCH_TARGETS[id].pitchId).toBe(id);
      expect(PITCH_TARGETS[id].source.trim()).not.toBe("");
    }
  });

  it("caps the slider efficiency at 35 percent with no floor", () => {
    const efficiency = PITCH_TARGETS["slider"].efficiencyPercent;
    expect(efficiency?.max).toBeLessThanOrEqual(35);
    expect(efficiency?.min).toBeUndefined();
  });

  it("holds the four-seam efficiency floor at 95 or more", () => {
    expect(
      PITCH_TARGETS["four-seam"].efficiencyPercent?.min,
    ).toBeGreaterThanOrEqual(95);
  });

  it("gives the changeup no absolute ranges", () => {
    for (const hand of HANDS) {
      expect(rangesOf(targetFor("changeup", hand)!)).toEqual([]);
    }
  });
});

describe("targetFor", () => {
  it("returns null for an unknown pitch", () => {
    expect(targetFor("knuckleball", "right")).toBeNull();
  });

  it("never inverts a range, for either hand", () => {
    for (const id of PITCH_IDS) {
      for (const hand of HANDS) {
        for (const range of rangesOf(targetFor(id, hand)!)) {
          if (range.min !== undefined && range.max !== undefined) {
            expect(range.min).toBeLessThanOrEqual(range.max);
          }
        }
      }
    }
  });

  it("returns the stored right-handed values unchanged", () => {
    for (const id of PITCH_IDS) {
      expect(targetFor(id, "right")).toEqual(PITCH_TARGETS[id]);
    }
  });

  it("mirrors the two-seam axis 1:00-2:00 to 10:00-11:00 for lefties", () => {
    expect(targetFor("two-seam", "left")!.axisClock).toEqual({
      min: 10,
      max: 11,
    });
  });

  it("mirrors the four-seam axis across 12 without landing on 0", () => {
    expect(targetFor("four-seam", "left")!.axisClock).toEqual({
      min: 11.5,
      max: 12,
    });
  });

  it("negates horizontal break and swaps its bounds for lefties", () => {
    const right = targetFor("two-seam", "right")!.horizontalBreakInches!;
    const left = targetFor("two-seam", "left")!.horizontalBreakInches!;
    expect(left.min).toBe(-right.max!);
    expect(left.max).toBe(-right.min!);
  });

  it("leaves efficiency, vertical break and spin per mph unchanged", () => {
    for (const id of PITCH_IDS) {
      const right = targetFor(id, "right")!;
      const left = targetFor(id, "left")!;
      expect(left.efficiencyPercent).toEqual(right.efficiencyPercent);
      expect(left.verticalBreakInches).toEqual(right.verticalBreakInches);
      expect(left.spinPerMph).toEqual(right.spinPerMph);
    }
  });

  it("returns to the original when mirrored twice", () => {
    for (const id of PITCH_IDS) {
      const once = targetFor(id, "left")!;
      // Feed the mirrored values back through the same mirror.
      const twice = mirrorTwice(once);
      expect(twice.axisClock).toEqual(PITCH_TARGETS[id].axisClock);
      expect(twice.horizontalBreakInches).toEqual(
        PITCH_TARGETS[id].horizontalBreakInches,
      );
    }
  });
});

// Mirrors via a temporary table entry so the public function is the only
// mirroring code under test.
function mirrorTwice(target: PitchTarget): PitchTarget {
  const key = "__roundtrip__";
  (PITCH_TARGETS as Record<string, PitchTarget>)[key] = {
    ...target,
    pitchId: key,
  };
  try {
    return targetFor(key, "left")!;
  } finally {
    delete (PITCH_TARGETS as Record<string, PitchTarget>)[key];
  }
}
