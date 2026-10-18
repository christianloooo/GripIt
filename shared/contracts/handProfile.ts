/**
 * The scanner's output, as step 4 reads it.
 *
 * Only the measurements matter here. Landmarks, capture metadata and the raw
 * geometry are deliberately typed as opaque: nothing downstream of the scanner
 * should be reconstructing a hand from points.
 */

export type Handedness = "left" | "right";

export interface PalmMeasurements {
  widthMm: number | null;
  lengthMm: number | null;
  /** Null until the scanner measures thickness rather than deriving it. */
  thicknessMm: number | null;
}

export interface FingerMeasurements {
  /** Proximal, middle, distal. The thumb has no middle phalanx by this naming. */
  segmentsMm: number[];
  diameterMm: number | null;
}

export type FingerName = "index" | "middle" | "ring" | "pinky" | "thumb";

export interface HandMeasurements {
  palm: PalmMeasurements;
  fingers: Record<FingerName, FingerMeasurements>;
}

export interface HandProfile {
  schemaVersion: "1.0.0";
  profileId: string;
  createdAt: string;
  handedness: Handedness;
  units: "millimeters";
  coordinateSystem: string;
  measurements: HandMeasurements;
  landmarks: Record<string, unknown>;
  capture: {
    method: string;
    coverage?: { fraction: number };
    confidence: number;
  };
  extensions: Record<string, unknown>;
}

/** Total length of a finger, or null when a segment is missing. */
export function fingerLengthMm(finger: FingerMeasurements): number | null {
  if (!finger.segmentsMm.length) return null;
  if (finger.segmentsMm.some((value) => !Number.isFinite(value))) return null;
  return finger.segmentsMm.reduce((sum, value) => sum + value, 0);
}

/**
 * How much longer the middle finger is than the index, in millimetres.
 *
 * Worth surfacing because it changes how the two pads sit on a seam: a bigger
 * difference puts the middle pad deeper on the ball than the index at the same
 * wrist angle. One small study also links finger length discrepancy to spin
 * rate, which is suggestive rather than settled.
 */
export function middleIndexDifferenceMm(
  profile: HandProfile,
): number | null {
  const middle = fingerLengthMm(profile.measurements.fingers.middle);
  const index = fingerLengthMm(profile.measurements.fingers.index);
  if (middle === null || index === null) return null;
  return Number((middle - index).toFixed(1));
}
