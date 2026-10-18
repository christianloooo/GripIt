import { FINGERS, LANDMARK_CHAINS } from "./grip";
import type { Landmark, Measurements } from "./grip";
import { validateMeasurements } from "./handDiagnostics";
import { measureWithBaseball } from "./ballReference";
import type { BallReference } from "./ballReference";
export type ScanFeedback = {
  progress: number;
  accepted: number;
  message: string;
  landmarks?: Landmark[];
  hand?: string;
  ball?: BallReference | null;
};
export type Detection = {
  worldLandmarks: Landmark[][];
  landmarks: Landmark[][];
  ball?: BallReference | null;
  handedness: { categoryName: string; score: number }[][];
};
export function assessDetection(result: Detection): {
  message: string;
  measurements?: Measurements;
  hand?: string;
  landmarks?: Landmark[];
} {
  if (result.worldLandmarks.length === 0)
    return {
      message: "No hand found. Keep your entire palm and fingertips in view.",
    };
  if (result.worldLandmarks.length !== 1)
    return {
      message: "Show only one hand so its measurements stay consistent.",
    };
  if (
    result.landmarks[0]?.length !== 21 ||
    result.worldLandmarks[0]?.length !== 21 ||
    [...result.landmarks[0], ...result.worldLandmarks[0]].some(
      (p) => !Number.isFinite(p.x + p.y + p.z),
    )
  )
    return {
      message:
        "Incomplete hand landmarks. Keep every fingertip and thumb visible.",
    };
  const image = result.landmarks[0],
    world = result.worldLandmarks[0],
    category = result.handedness[0]?.[0];
  if (!category || category.score < 0.75)
    return {
      message: "Turn your palm toward the camera so the hand is clear.",
      landmarks: image,
    };
  const xs = image.map((p) => p.x),
    ys = image.map((p) => p.y);
  if (
    Math.min(...xs) < 0.025 ||
    Math.max(...xs) > 0.975 ||
    Math.min(...ys) < 0.025 ||
    Math.max(...ys) > 0.975
  )
    return {
      message:
        "Move back a little. Your whole hand needs to fit inside the frame.",
      landmarks: image,
    };
  if (Math.max(...ys) - Math.min(...ys) < 0.28)
    return {
      message: "Move your hand closer to the camera.",
      landmarks: image,
    };
  const dist = (a: number, b: number) =>
    Math.hypot(
      world[a].x - world[b].x,
      world[a].y - world[b].y,
      world[a].z - world[b].z,
    );
  const open = Object.entries(LANDMARK_CHAINS)
    .filter(([name]) => name !== "thumb")
    .every(
      ([, chain]) =>
        dist(chain[0], chain[3]) /
          (dist(chain[0], chain[1]) +
            dist(chain[1], chain[2]) +
            dist(chain[2], chain[3])) >
        0.88,
    );
  const thumb = LANDMARK_CHAINS.thumb;
  const thumbStraight =
    dist(thumb[0], thumb[3]) /
    (dist(thumb[0], thumb[1]) +
      dist(thumb[1], thumb[2]) +
      dist(thumb[2], thumb[3]));
  if (!open || !Number.isFinite(thumbStraight) || thumbStraight < 0.78)
    return {
      message:
        "Straighten and spread your fingers. Relax the thumb to the side.",
      landmarks: image,
    };
  // A near-edge-on palm gives an unstable width calibration.
  const a = world[5],
    b = world[17];
  if (Math.abs(a.z - b.z) > dist(5, 17) * 0.6)
    return {
      message:
        "Face the palm toward the camera instead of turning it sideways.",
      landmarks: image,
    };
  if (!result.ball || result.ball.confidence < 0.78)
    return {
      message:
        "Baseball not clear. Place a regulation baseball beside your hand on a dark background, fully in view.",
      landmarks: image,
    };
  try {
    const measurements = measureWithBaseball(image, result.ball);
    validateMeasurements(measurements);
    return {
      measurements,
      hand: category.categoryName,
      landmarks: image,
      message: "Good view. Hold steady while the measurements settle.",
    };
  } catch (error) {
    return {
      message:
        error instanceof Error
          ? error.message
          : "Try a clearer open-hand view.",
      landmarks: image,
    };
  }
}
export function stableMeasurements(samples: Measurements[]) {
  if (samples.length < 8) return false;
  const stable = (values: number[], tolerance: number) => {
    const mean = values.reduce((a, b) => a + b, 0) / values.length;
    return (
      values.every(Number.isFinite) &&
      Math.sqrt(
        values.reduce((sum, n) => sum + (n - mean) ** 2, 0) / values.length,
      ) < tolerance
    );
  };
  const meanWidth =
    samples.reduce((sum, m) => sum + m.palmWidth, 0) / samples.length;
  if (
    !stable(
      samples.map((m) => m.palmWidth),
      meanWidth * 0.08,
    ) ||
    !stable(
      samples.map((m) => m.palmLength ?? 72),
      meanWidth * 0.08,
    )
  )
    return false;
  if (samples.some((m) => m.knuckles)) {
    if (!samples.every((m) => m.knuckles)) return false;
    for (const finger of FINGERS)
      for (const axis of [0, 1, 2])
        if (
          !stable(
            samples.map((m) => m.knuckles![finger][axis]),
            meanWidth * 0.06,
          )
        )
          return false;
  }
  return FINGERS.every((finger) =>
    [0, 1, 2].every((joint) => {
      const values = samples.map((s) => s.segments[finger][joint]);
      const mean = values.reduce((a, b) => a + b, 0) / values.length;
      return mean > 0 && stable(values, mean * 0.12);
    }),
  );
}
