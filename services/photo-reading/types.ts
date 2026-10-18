export const PHOTO_FIELDS = [
  "velocityMph", "totalSpinRpm", "spinDirectionClock", "spinEfficiencyPercent",
  "gyroDegree", "horizontalBreakInches", "verticalBreakInches", "releaseHeightFeet", "rapsodoScore",
] as const;

export type PhotoField = typeof PHOTO_FIELDS[number];
export type PhotoReadings = { [K in PhotoField]: K extends "spinDirectionClock" ? string | null : number | null };
export type PhotoExtraction = {
  schemaVersion: "1.0.0";
  model: "perceptron-mk1.5";
  readings: PhotoReadings;
  warnings: string[];
};
export type ExtractPhotoInput = {
  bytes: Uint8Array;
  contentType: "image/jpeg" | "image/png";
  signal?: AbortSignal;
};
export type PhotoExtractor = (input: ExtractPhotoInput) => Promise<PhotoExtraction>;
