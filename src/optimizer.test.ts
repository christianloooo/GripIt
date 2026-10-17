import { describe, it, expect } from "vitest";
import { Vector3 } from "three";
import {
  DEFAULT_MEASUREMENTS,
  FINGERS,
  PITCHES,
  solveGrip,
  handScale,
  jointEnergy,
  JOINT_NEUTRAL,
  OBJECTIVE_WEIGHTS,
  segmentDistance,
  worldSeamPoint,
  BALL_RADIUS,
} from "./grip";
describe("anatomical handedness", () => {
  it("places the right thumb on +X when the palm faces +Z, and mirrors left once", () => {
    const grip = solveGrip(DEFAULT_MEASUREMENTS, PITCHES[0]);
    const root = (name: string) =>
      grip.fingers.find((f) => f.name === name)!.root.x;
    expect(root("thumb")).toBeGreaterThan(root("index"));
    expect(root("index")).toBeGreaterThan(root("middle"));
    expect(root("middle")).toBeGreaterThan(root("ring"));
    expect(root("ring")).toBeGreaterThan(root("pinky"));
    expect(root("thumb") * handScale(false)).toBeGreaterThan(0);
    expect(root("thumb") * handScale(true)).toBeLessThan(0);
  });
});
describe("the requested geometric objective", () => {
  it("uses normalized deviation from neutral angles", () => {
    expect(jointEnergy(JOINT_NEUTRAL)).toBe(0);
    expect(
      jointEnergy([
        JOINT_NEUTRAL[0] + 1.85,
        JOINT_NEUTRAL[1],
        JOINT_NEUTRAL[2],
      ]),
    ).toBeCloseTo(1);
  });
  it("reports the weighted sum of position, joint and collision energies", () => {
    const { objective } = solveGrip(DEFAULT_MEASUREMENTS, PITCHES[0]);
    expect(objective.total).toBeCloseTo(
      objective.position * OBJECTIVE_WEIGHTS.position +
        objective.joint * OBJECTIVE_WEIGHTS.joint +
        objective.collision * OBJECTIVE_WEIGHTS.collision,
    );
  });
  it("attaches index and middle targets to the rendered seam under the optimized ball transform", () => {
    for (const pitch of PITCHES) {
      const solution = solveGrip(DEFAULT_MEASUREMENTS, pitch);
      for (const finger of solution.fingers.slice(0, 2)) {
        let error = Infinity;
        for (let i = 0; i < 240; i++)
          error = Math.min(
            error,
            finger.target.distanceTo(
              worldSeamPoint(
                (i / 240) * Math.PI * 2,
                solution.ball,
                BALL_RADIUS + finger.radius,
              ),
            ),
          );
        expect(error).toBeLessThan(1e-8);
      }
    }
  });
  it("detects crossing, parallel, and degenerate capsule centerlines", () => {
    expect(
      segmentDistance(
        new Vector3(-2, 0, 0),
        new Vector3(2, 0, 0),
        new Vector3(0, -2, 0),
        new Vector3(0, 2, 0),
      ),
    ).toBeCloseTo(0);
    expect(
      segmentDistance(
        new Vector3(0, 0, 0),
        new Vector3(3, 0, 0),
        new Vector3(0, 5, 0),
        new Vector3(3, 5, 0),
      ),
    ).toBeCloseTo(5);
    expect(
      segmentDistance(
        new Vector3(),
        new Vector3(),
        new Vector3(0, 3, 0),
        new Vector3(0, 3, 0),
      ),
    ).toBeCloseTo(3);
  });
  it("changes the pose and ball placement for different measured hands", () => {
    const small = structuredClone(DEFAULT_MEASUREMENTS);
    small.palmWidth = 70;
    for (const f of FINGERS)
      small.segments[f] = small.segments[f].map((n) => n * 0.85) as [
        number,
        number,
        number,
      ];
    const a = solveGrip(small, PITCHES[0]),
      b = solveGrip(DEFAULT_MEASUREMENTS, PITCHES[0]);
    expect(a.fingers[0].angles).not.toEqual(b.fingers[0].angles);
    expect(a.ball.position.toArray()).not.toEqual(b.ball.position.toArray());
  });
});
