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
