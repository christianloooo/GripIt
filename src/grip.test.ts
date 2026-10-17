import { describe, expect, it } from "vitest";
import { Vector3 } from "three";
import {
  clearance,
  DEFAULT_MEASUREMENTS,
  FINGERS,
  forward,
  LANDMARK_CHAINS,
  measureLandmarks,
  medianMeasurements,
  PITCHES,
  solveFinger,
} from "./grip";

describe("calibrated hand measurements", () => {
  const points = () => {
    const p = Array.from({ length: 21 }, () => ({ x: 0, y: 0, z: 0 }));
    Object.values(LANDMARK_CHAINS).forEach((chain, finger) =>
      chain.forEach((index, joint) => {
        p[index] = { x: finger * 0.02, y: joint * 0.02, z: 0 };
      }),
    );
    return p;
  };
  it("uses measured palm width to calibrate every segment", () => {
    const a = measureLandmarks(points(), 60),
      b = measureLandmarks(points(), 90);
    expect(a.segments.index[0]).toBeCloseTo(20);
    for (const f of FINGERS)
      for (let i = 0; i < 3; i++)
        expect(b.segments[f][i] / a.segments[f][i]).toBeCloseTo(1.5);
  });
  it("rejects degenerate and invalid landmark data", () => {
    expect(() => measureLandmarks([], 82)).toThrow();
    expect(() =>
      measureLandmarks(Array(21).fill({ x: 0, y: 0, z: 0 }), 82),
    ).toThrow();
    const p = points();
    p[0].x = NaN;
    expect(() => measureLandmarks(p, 82)).toThrow();
    expect(() => medianMeasurements([])).toThrow();
  });
  it("suppresses a bad frame using the median across frames", () => {
    const base = measureLandmarks(points(), 82),
      outlier = structuredClone(base);
    outlier.segments.index[0] = 60;
    expect(medianMeasurements([base, outlier, base]).segments.index[0]).toBe(
      base.segments.index[0],
    );
  });
});
describe("finger kinematics", () => {
  it("preserves measured bone lengths after articulation", () => {
    const points = forward(
      new Vector3(3, 4, 5),
      0.7,
      [38, 24, 18],
      [0.4, 0.8, 0.6],
    );
    [38, 24, 18].forEach((length, i) =>
      expect(points[i].distanceTo(points[i + 1])).toBeCloseTo(length),
    );
  });
  it("detects a segment passing through the baseball", () => {
    expect(
      clearance([new Vector3(0, -40, 24), new Vector3(0, 80, 24)], 6),
    ).toBeLessThan(-36);
  });
  it("fits the sample four-seam grip without significant sphere penetration", () => {
    for (const f of FINGERS) {
      const rig = solveFinger(f, DEFAULT_MEASUREMENTS, PITCHES[0]);
      expect(rig.error).toBeLessThan(8);
      expect(rig.clearance).toBeGreaterThan(-1);
    }
  });
  it("returns finite, bounded poses and honest fit diagnostics for each pitch and hand size", () => {
    for (const pitch of PITCHES)
      for (const scale of [0.75, 1, 1.25]) {
        const m = structuredClone(DEFAULT_MEASUREMENTS);
        m.palmWidth *= scale;
        for (const f of FINGERS)
          m.segments[f] = m.segments[f].map((n) => n * scale) as [
            number,
            number,
            number,
          ];
        for (const f of FINGERS) {
          const rig = solveFinger(f, m, pitch);
          expect(Number.isFinite(rig.error)).toBe(true);
          expect(Number.isFinite(rig.clearance)).toBe(true);
          expect(rig.error).toBeCloseTo(rig.points[3].distanceTo(rig.target));
          rig.angles.forEach((angle, i) => {
            expect(angle).toBeGreaterThanOrEqual(i === 0 ? -0.35 : 0);
            expect(angle).toBeLessThanOrEqual(i === 0 ? 1.5 : 1.85);
          });
          rig.lengths.forEach((length, i) =>
            expect(rig.points[i].distanceTo(rig.points[i + 1])).toBeCloseTo(
              length,
            ),
          );
        }
      }
  });
});
