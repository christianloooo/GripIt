import { it, expect } from "vitest";
import { createHandSurface } from "./handSurface";
import { DEFAULT_MEASUREMENTS, PITCHES, solveGrip } from "./grip";
it("builds finite smooth geometry covering the palm and finger chains", () => {
  const geometry = createHandSurface(
    solveGrip(DEFAULT_MEASUREMENTS, PITCHES[0]).fingers,
    DEFAULT_MEASUREMENTS,
  );
  expect(geometry.drawRange.count).toBeGreaterThan(1000);
  const positions = geometry.attributes.position,
    normals = geometry.attributes.normal;
  for (let i = 0; i < geometry.drawRange.count; i++) {
    expect(
      Number.isFinite(
        positions.getX(i) + positions.getY(i) + positions.getZ(i),
      ),
    ).toBe(true);
    expect(
      Number.isFinite(normals.getX(i) + normals.getY(i) + normals.getZ(i)),
    ).toBe(true);
  }
  geometry.dispose();
});

it("keeps large hands closed instead of cutting fingers and wrists at a fixed box boundary", () => {
  const measurements = structuredClone(DEFAULT_MEASUREMENTS);
  measurements.palmWidth = 110;
  measurements.palmLength = 115;
  for (const name of ["index", "middle", "ring", "pinky", "thumb"] as const)
    measurements.segments[name] = measurements.segments[name].map(
      (n) => n * 1.25,
    ) as [number, number, number];
  const geometry = createHandSurface(
    solveGrip(measurements, PITCHES[0]).fingers,
    measurements,
  );
  const p = geometry.getAttribute("position");
  const edges = new Map<string, number>();
  const vertex = (i: number) =>
    [p.getX(i), p.getY(i), p.getZ(i)]
      .map((n) => Math.round(n * 1000))
      .join(",");
  for (let i = 0; i < p.count; i += 3) {
    const v = [vertex(i), vertex(i + 1), vertex(i + 2)];
    for (let j = 0; j < 3; j++) {
      const a = v[j],
        b = v[(j + 1) % 3];
      if (a === b) continue;
      const key = [a, b].sort().join("/");
      edges.set(key, (edges.get(key) ?? 0) + 1);
    }
  }
  expect([...edges.values()].filter((n) => n === 1)).toHaveLength(0);
  expect(geometry.boundingBox!.min.y).toBeLessThan(-140);
  geometry.dispose();
});
