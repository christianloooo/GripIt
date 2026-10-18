import { describe, expect, it } from "vitest";
import type { ThrowRecord } from "../throwEntry";
import { clockHoursApart, deriveMetrics, efficiencyFromGyro } from "./metrics";

type Measurements = Partial<
  Record<keyof ThrowRecord["measurements"], number | null>
>;

// Absent fields default to null so each test names only what it cares about.
// The cast is deliberate: it lets tests feed nulls where the record type is stricter.
function makeThrow(m: Measurements): ThrowRecord {
  return {
    schemaVersion: "1.0.0",
    throwId: "t",
    sessionId: "s",
    pitchId: "p",
    recordedAt: "2026-01-01T00:00:00.000Z",
    measurements: {
      velocityMph: null,
      totalSpinRpm: null,
      spinDirectionClock: null,
      spinEfficiencyPercent: null,
      gyroDegree: null,
      horizontalBreakInches: null,
      verticalBreakInches: null,
      releaseHeightFeet: null,
      rapsodoScore: null,
      ...m,
    },
    source: "manual",
    extensions: {},
  } as unknown as ThrowRecord;
}

// Real baseball screenshot.
const baseball: Measurements = {
  velocityMph: 77.3,
  totalSpinRpm: 1642,
  spinDirectionClock: 1 + 56 / 60,
  spinEfficiencyPercent: 93.8,
  verticalBreakInches: 13.8,
  horizontalBreakInches: 18.6,
};

describe("efficiencyFromGyro", () => {
  it("reproduces the Rapsodo anchor: -18.2 degrees is 95.0 percent", () => {
    expect(efficiencyFromGyro(-18.2)).toBe(95.0);
  });

  it("gives the same efficiency for negative and positive gyro", () => {
    expect(efficiencyFromGyro(18.2)).toBe(efficiencyFromGyro(-18.2));
  });

  it("is 100 at zero gyro and 0 at 90 degrees", () => {
    expect(efficiencyFromGyro(0)).toBe(100);
    expect(efficiencyFromGyro(90)).toBe(0);
  });
});

describe("clockHoursApart", () => {
  it("is circular: 12:30 against 11:30 is 1.0, not 11.0", () => {
    expect(clockHoursApart(12.5, 11.5)).toBeCloseTo(1.0, 6);
  });

  it("measures 1:56 against 12:15 as about 1.68", () => {
    expect(clockHoursApart(1 + 56 / 60, 12.25)).toBeCloseTo(1.68, 2);
  });

  it("is symmetric and zero for equal times", () => {
    expect(clockHoursApart(3, 9)).toBe(clockHoursApart(9, 3));
    expect(clockHoursApart(4.5, 4.5)).toBe(0);
  });

  it("never exceeds 6", () => {
    expect(clockHoursApart(12, 6)).toBe(6);
    for (let a = 0.5; a <= 12; a += 0.5) {
      for (let b = 0.5; b <= 12; b += 0.5) {
        expect(clockHoursApart(a, b)).toBeLessThanOrEqual(6);
      }
    }
  });
});

describe("deriveMetrics", () => {
  it("derives from one baseball throw", () => {
    const m = deriveMetrics([makeThrow(baseball)]);
    expect(m.throwCount).toBe(1);
    expect(m.velocityMph).toBe(77.3);
    expect(m.totalSpinRpm).toBe(1642);
    expect(m.spinEfficiencyPercent).toBe(93.8);
    expect(m.activeSpinRpm).toBe(1540);
    expect(m.spinPerMph).toBe(21.2);
    expect(m.spinDirectionClock).toBeCloseTo(1.93, 2);
    expect(m.verticalBreakInches).toBe(13.8);
    expect(m.horizontalBreakInches).toBe(18.6);
  });

  it("anchors active spin on the softball screenshot: 1077 at 95% is 1023", () => {
    const m = deriveMetrics([
      makeThrow({ totalSpinRpm: 1077, spinEfficiencyPercent: 95.0 }),
    ]);
    expect(m.activeSpinRpm).toBe(1023);
  });

  it("takes the median of three throws, not the mean", () => {
    const m = deriveMetrics([
      makeThrow({ velocityMph: 70, totalSpinRpm: 1500 }),
      makeThrow({ velocityMph: 72, totalSpinRpm: 1600 }),
      makeThrow({ velocityMph: 90, totalSpinRpm: 2600 }),
    ]);
    expect(m.throwCount).toBe(3);
    expect(m.velocityMph).toBe(72);
    expect(m.totalSpinRpm).toBe(1600);
  });

  it("averages the two middle values for an even count", () => {
    const m = deriveMetrics([
      makeThrow({ velocityMph: 70 }),
      makeThrow({ velocityMph: 80 }),
    ]);
    expect(m.velocityMph).toBe(75);
  });

  it("ignores null values when taking a median", () => {
    const m = deriveMetrics([
      makeThrow({ horizontalBreakInches: 10 }),
      makeThrow({ horizontalBreakInches: null }),
      makeThrow({ horizontalBreakInches: 14 }),
    ]);
    expect(m.horizontalBreakInches).toBe(12);
  });

  it("derives active spin and spin per mph from the aggregated medians", () => {
    const m = deriveMetrics([
      makeThrow({
        velocityMph: 80,
        totalSpinRpm: 2000,
        spinEfficiencyPercent: 90,
      }),
      makeThrow({
        velocityMph: 80,
        totalSpinRpm: 2000,
        spinEfficiencyPercent: 90,
      }),
      makeThrow({
        velocityMph: 40,
        totalSpinRpm: 4000,
        spinEfficiencyPercent: 10,
      }),
    ]);
    expect(m.activeSpinRpm).toBe(1800);
    expect(m.spinPerMph).toBe(25);
  });

  it("fills efficiency from gyro when only gyro is present", () => {
    const m = deriveMetrics([
      makeThrow({ totalSpinRpm: 1077, gyroDegree: -18.2 }),
    ]);
    expect(m.spinEfficiencyPercent).toBe(95.0);
    expect(m.activeSpinRpm).toBe(1023);
  });

  it("backfills efficiency per throw, before taking the median", () => {
    const m = deriveMetrics([
      makeThrow({ spinEfficiencyPercent: 80 }),
      makeThrow({ gyroDegree: 0 }), // 100
      makeThrow({ spinEfficiencyPercent: 90 }),
    ]);
    expect(m.spinEfficiencyPercent).toBe(90);
  });

  it("prefers a reported efficiency over gyro", () => {
    const m = deriveMetrics([
      makeThrow({ spinEfficiencyPercent: 90, gyroDegree: 0 }),
    ]);
    expect(m.spinEfficiencyPercent).toBe(90);
  });

  it("returns throwCount 0 and all null for an empty array", () => {
    expect(deriveMetrics([])).toEqual({
      throwCount: 0,
      velocityMph: null,
      totalSpinRpm: null,
      spinEfficiencyPercent: null,
      activeSpinRpm: null,
      spinPerMph: null,
      spinDirectionClock: null,
      horizontalBreakInches: null,
      verticalBreakInches: null,
    });
  });

  it("returns null, not NaN or 0, for every field when inputs are absent", () => {
    const m = deriveMetrics([makeThrow({}), makeThrow({})]);
    expect(m.throwCount).toBe(2);
    for (const [key, value] of Object.entries(m)) {
      if (key !== "throwCount") expect(value).toBeNull();
    }
  });

  it("leaves derived values null when an input is missing", () => {
    const noVelocity = deriveMetrics([
      makeThrow({ totalSpinRpm: 1600, spinEfficiencyPercent: 90 }),
    ]);
    expect(noVelocity.spinPerMph).toBeNull();
    expect(noVelocity.activeSpinRpm).toBe(1440);

    const noSpin = deriveMetrics([
      makeThrow({ velocityMph: 80, spinEfficiencyPercent: 90 }),
    ]);
    expect(noSpin.activeSpinRpm).toBeNull();
    expect(noSpin.spinPerMph).toBeNull();

    const noEfficiency = deriveMetrics([
      makeThrow({ velocityMph: 80, totalSpinRpm: 1600 }),
    ]);
    expect(noEfficiency.activeSpinRpm).toBeNull();
    expect(noEfficiency.spinPerMph).toBe(20);
  });

  it("returns null for spin per mph when velocity is zero", () => {
    const m = deriveMetrics([
      makeThrow({ velocityMph: 0, totalSpinRpm: 1600 }),
    ]);
    expect(m.spinPerMph).toBeNull();
  });
});
