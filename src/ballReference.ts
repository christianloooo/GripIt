import type { Landmark, Measurements } from "./grip";
import { BALL_RADIUS, FINGERS, LANDMARK_CHAINS } from "./grip";

export type BallReference = {
  x: number;
  y: number;
  radius: number;
  confidence: number;
  imageWidth: number;
  imageHeight: number;
};
// Detect a bright, approximately circular baseball beside (not overlapping) the
// hand. This is a geometric reference detector, not a semantic ball classifier.
export function detectBaseball(
  data: Uint8ClampedArray,
  width: number,
  height: number,
  hand: Landmark[],
): BallReference | null {
  const gray = new Float32Array(width * height),
    gx = new Float32Array(width * height),
    gy = new Float32Array(width * height),
    mag = new Float32Array(width * height);
  for (let i = 0; i < gray.length; i++)
    gray[i] =
      data[i * 4] * 0.299 + data[i * 4 + 1] * 0.587 + data[i * 4 + 2] * 0.114;
  const edges: number[] = [];
  const box = hand.length
    ? {
        minX: Math.min(...hand.map((p) => p.x)) * width - 10,
        maxX: Math.max(...hand.map((p) => p.x)) * width + 10,
        minY: Math.min(...hand.map((p) => p.y)) * height - 10,
        maxY: Math.max(...hand.map((p) => p.y)) * height + 10,
      }
    : null;
  for (let y = 2; y < height - 2; y++)
    for (let x = 2; x < width - 2; x++) {
      const i = y * width + x;
      gx[i] =
        gray[i - width + 1] +
        2 * gray[i + 1] +
        gray[i + width + 1] -
        gray[i - width - 1] -
        2 * gray[i - 1] -
        gray[i + width - 1];
      gy[i] =
        gray[i + width - 1] +
        2 * gray[i + width] +
        gray[i + width + 1] -
        gray[i - width - 1] -
        2 * gray[i - width] -
        gray[i - width + 1];
      mag[i] = Math.hypot(gx[i], gy[i]);
      if (
        mag[i] > 65 &&
        !(
          box &&
          x > box.minX &&
          x < box.maxX &&
          y > box.minY &&
          y < box.maxY
        ) &&
        (x + y) % 2 === 0
      )
        edges.push(i);
    }
  let best: BallReference | null = null,
    bestScore = 0;
  const maxRadius = Math.min(width, height) * 0.24;
  for (let radius = 14; radius <= maxRadius; radius += 3) {
    const votes = new Uint16Array(width * height);
    for (const i of edges) {
      const x = i % width,
        y = Math.floor(i / width),
        nx = gx[i] / mag[i],
        ny = gy[i] / mag[i];
      for (const sign of [-1, 1]) {
        const cx = Math.round(x + nx * radius * sign),
          cy = Math.round(y + ny * radius * sign);
        if (
          cx > radius + 2 &&
          cx < width - radius - 2 &&
          cy > radius + 2 &&
          cy < height - radius - 2
        )
          votes[cy * width + cx]++;
      }
    }
    const candidates: { x: number; y: number; v: number }[] = [];
    for (let y = Math.ceil(radius + 3); y < height - radius - 3; y++)
      for (let x = Math.ceil(radius + 3); x < width - radius - 3; x++) {
        const i = y * width + x,
          v =
            votes[i] +
            votes[i - 1] +
            votes[i + 1] +
            votes[i - width] +
            votes[i + width];
        if (v < 12) continue;
        if (
          box &&
          x + radius > box.minX &&
          x - radius < box.maxX &&
          y + radius > box.minY &&
          y - radius < box.maxY
        )
          continue;
        if (candidates.length < 5 || v > candidates[4].v) {
          candidates.push({ x, y, v });
          candidates.sort((a, b) => b.v - a.v);
          candidates.length = Math.min(candidates.length, 5);
        }
      }
    for (const c of candidates) {
      let coverage = 0,
        inside = 0,
        outside = 0,
        bright = 0;
      for (let a = 0; a < 64; a++) {
        const angle = (a / 64) * Math.PI * 2,
          nx = Math.cos(angle),
          ny = Math.sin(angle);
        let edge = 0;
        for (let dr = -2; dr <= 2; dr++) {
          const x = Math.round(c.x + nx * (radius + dr)),
            y = Math.round(c.y + ny * (radius + dr)),
            i = y * width + x;
          const radial = Math.abs(
            (gx[i] * nx + gy[i] * ny) / Math.max(1, mag[i]),
          );
          if (radial > 0.75) edge = Math.max(edge, mag[i]);
        }
        if (edge > 70) coverage++;
        const ii =
          (Math.round(c.y + ny * radius * 0.65) * width +
            Math.round(c.x + nx * radius * 0.65)) *
          4;
        const oi =
          (Math.round(c.y + ny * (radius + 4)) * width +
            Math.round(c.x + nx * (radius + 4))) *
          4;
        inside += (data[ii] + data[ii + 1] + data[ii + 2]) / 3;
        outside += (data[oi] + data[oi + 1] + data[oi + 2]) / 3;
        if (
          Math.min(data[ii], data[ii + 1], data[ii + 2]) > 95 &&
          Math.max(data[ii], data[ii + 1], data[ii + 2]) -
            Math.min(data[ii], data[ii + 1], data[ii + 2]) <
            90
        )
          bright++;
      }
      const score = (coverage / 64) * 0.8 + (bright / 64) * 0.2;
      if (
        coverage / 64 < 0.76 ||
        bright / 64 < 0.65 ||
        (inside - outside) / 64 < 9 ||
        score <= bestScore
      )
        continue;
      bestScore = score;
      best = {
        x: c.x / width,
        y: c.y / height,
        radius: radius / width,
        confidence: score,
        imageWidth: width,
        imageHeight: height,
      };
    }
  }
  if (!best) return null;
  // Refine radius from local radial gradients; robust median ignores seam edges.
  const distances: number[] = [];
  const cx = best.x * width,
    cy = best.y * height,
    r = best.radius * width;
  for (let a = 0; a < 96; a++) {
    const angle = (a / 96) * Math.PI * 2,
      nx = Math.cos(angle),
      ny = Math.sin(angle);
    let peak = 0,
      rr = r;
    for (let dr = -3; dr <= 3; dr += 0.5) {
      const x = Math.round(cx + nx * (r + dr)),
        y = Math.round(cy + ny * (r + dr)),
        i = y * width + x;
      const strength = Math.abs(gx[i] * nx + gy[i] * ny);
      if (strength > peak) {
        peak = strength;
        rr = r + dr;
      }
    }
    if (peak > 65) distances.push(rr);
  }
  distances.sort((a, b) => a - b);
  if (distances.length >= 50)
    best.radius = distances[Math.floor(distances.length / 2)] / width;
  return best;
}
export function measureWithBaseball(
  points: Landmark[],
  ball: BallReference,
): Measurements {
  if (points.length !== 21 || !Number.isFinite(ball.radius) || ball.radius <= 0)
    throw new Error("A full hand and baseball must both be visible.");
  const scale = (BALL_RADIUS * 2) / (ball.radius * 2),
    aspect = ball.imageHeight / ball.imageWidth;
  const p = points.map((v) => ({ x: v.x, y: -v.y * aspect, z: -v.z }));
  const delta = (a: number, b: number) => ({
    x: p[a].x - p[b].x,
    y: p[a].y - p[b].y,
    z: p[a].z - p[b].z,
  });
  const distance = (a: number, b: number) => {
    const d = delta(a, b);
    return Math.hypot(d.x, d.y, d.z) * scale;
  };
  const segments = {} as Measurements["segments"];
  for (const f of FINGERS) {
    const chain = LANDMARK_CHAINS[f];
    segments[f] = [0, 1, 2].map((i) => distance(chain[i], chain[i + 1])) as [
      number,
      number,
      number,
    ];
    if (segments[f].some((v) => !Number.isFinite(v) || v < 6 || v > 65))
      throw new Error(
        "The hand and ball appear at different scales. Hold them side by side at the same distance from the camera.",
      );
  }
  const span = distance(5, 17),
    palmWidth = span * 1.18,
    palmLength = distance(0, 9);
  if (palmWidth < 45 || palmWidth > 125 || palmLength < 40 || palmLength > 125)
    throw new Error(
      "Keep your open palm beside the baseball, at the same distance from the camera.",
    );
  const y = delta(9, 0),
    yn = Math.hypot(y.x, y.y, y.z);
  y.x /= yn;
  y.y /= yn;
  y.z /= yn;
  const x = delta(5, 17),
    dot = x.x * y.x + x.y * y.y + x.z * y.z;
  x.x -= dot * y.x;
  x.y -= dot * y.y;
  x.z -= dot * y.z;
  const xn = Math.hypot(x.x, x.y, x.z);
  if (xn < 1e-6)
    throw new Error(
      "Turn the palm toward the camera so the knuckles are clearly separated.",
    );
  x.x /= xn;
  x.y /= xn;
  x.z /= xn;
  const center = {
    x: (p[5].x + p[17].x) / 2,
    y: (p[5].y + p[17].y) / 2,
    z: (p[5].z + p[17].z) / 2,
  };
  const knuckles = {} as NonNullable<Measurements["knuckles"]>;
  for (const f of FINGERS) {
    const i = LANDMARK_CHAINS[f][0],
      d = { x: p[i].x - center.x, y: p[i].y - p[9].y, z: p[i].z - center.z };
    knuckles[f] = [
      (d.x * x.x + (p[i].y - center.y) * x.y + d.z * x.z) * scale,
      (delta(i, 9).x * y.x + delta(i, 9).y * y.y + delta(i, 9).z * y.z) * scale,
      -24,
    ];
  }
  return {
    palmWidth,
    palmLength,
    segments,
    knuckles,
    calibration: {
      method: "baseball",
      diameterMm: BALL_RADIUS * 2,
      pixelsPerMm: (ball.radius * 2 * ball.imageWidth) / (BALL_RADIUS * 2),
    },
  };
}
