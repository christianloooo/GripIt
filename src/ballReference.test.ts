import { it, expect } from "vitest";
import { detectBaseball, measureWithBaseball } from "./ballReference";
import type { Landmark } from "./grip";
function frame(w = 320, h = 240, cx = 245, cy = 120, r = 37) {
  const pixels = new Uint8ClampedArray(w * h * 4);
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4,
        inside = Math.hypot(x - cx, y - cy) <= r;
      const color = inside ? [232, 222, 200] : [38, 48, 40];
      pixels.set([...color, 255], i);
    }
  return pixels;
}
it("detects a circular ball, measures its diameter, and rejects an empty background", () => {
  const b = detectBaseball(frame(), 320, 240, []);
  expect(b).not.toBeNull();
  expect(Math.abs(b!.x * 320 - 245)).toBeLessThan(2);
  expect(Math.abs(b!.y * 240 - 120)).toBeLessThan(2);
  expect(Math.abs(b!.radius * 320 - 37)).toBeLessThan(2);
  expect(
    detectBaseball(new Uint8ClampedArray(320 * 240 * 4).fill(80), 320, 240, []),
  ).toBeNull();
});
it("refuses a circle overlapping the detected hand", () => {
  const hand = [
    { x: 0.65, y: 0.3, z: 0 },
    { x: 0.95, y: 0.7, z: 0 },
  ];
  expect(detectBaseball(frame(), 320, 240, hand)).toBeNull();
});
it("derives millimeters directly from the ball, without typed measurements", () => {
  const p: Array<Landmark> = Array.from({ length: 21 }, () => ({
    x: 0.3,
    y: 0.8,
    z: 0,
  }));
  const chains = [
    [1, 2, 3, 4],
    [5, 6, 7, 8],
    [9, 10, 11, 12],
    [13, 14, 15, 16],
    [17, 18, 19, 20],
  ];
  chains.forEach((chain, f) =>
    chain.forEach(
      (id, j) => (p[id] = { x: 0.42 - f * 0.065, y: 0.45 - j * 0.09, z: 0 }),
    ),
  );
  const a = measureWithBaseball(p, {
    x: 0.8,
    y: 0.6,
    radius: 0.14,
    confidence: 1,
    imageWidth: 640,
    imageHeight: 640,
  });
  const b = measureWithBaseball(p, {
    x: 0.8,
    y: 0.6,
    radius: 0.16,
    confidence: 1,
    imageWidth: 640,
    imageHeight: 640,
  });
  expect(a.segments.index[0]).toBeCloseTo((0.09 * 73) / 0.28);
  expect(a.segments.index[0] / b.segments.index[0]).toBeCloseTo(0.16 / 0.14);
  expect(a.calibration?.method).toBe("baseball");
  expect(a.knuckles?.index[0]).toBeGreaterThan(a.knuckles!.pinky[0]);
});
