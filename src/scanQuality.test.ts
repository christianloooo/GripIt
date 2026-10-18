import { it, expect } from "vitest";
import { assessDetection, stableMeasurements } from "./scanQuality";
import { DEFAULT_MEASUREMENTS } from "./grip";
it("gives specific feedback for missing and multiple hands", () => {
  expect(
    assessDetection({ landmarks: [], worldLandmarks: [], handedness: [] })
      .message,
  ).toMatch("No hand");
  expect(
    assessDetection({
      landmarks: [[], []],
      worldLandmarks: [[], []],
      handedness: [],
    }).message,
  ).toMatch("only one");
});
it("requires enough stable measurements instead of accepting a noisy scan", () => {
  expect(stableMeasurements(Array(7).fill(DEFAULT_MEASUREMENTS))).toBe(false);
  expect(stableMeasurements(Array(10).fill(DEFAULT_MEASUREMENTS))).toBe(true);
  const bad = structuredClone(DEFAULT_MEASUREMENTS);
  bad.segments.middle = [60, 40, 35];
  expect(
    stableMeasurements([
      ...Array(5).fill(DEFAULT_MEASUREMENTS),
      ...Array(5).fill(bad),
    ]),
  ).toBe(false);
  const sameReference = structuredClone(DEFAULT_MEASUREMENTS);
  sameReference.segments.index = [60, 40, 30];
  expect(
    stableMeasurements([
      ...Array(5).fill(DEFAULT_MEASUREMENTS),
      ...Array(5).fill(sameReference),
    ]),
  ).toBe(false);
});
it("rejects moving thumb attachments even when segment lengths stay stable", () => {
  const first = structuredClone(DEFAULT_MEASUREMENTS);
  first.knuckles = {
    thumb: [28, -50, -24],
    index: [30, 0, -24],
    middle: [8, 0, -24],
    ring: [-14, -3, -24],
    pinky: [-29, -10, -24],
  };
  const shifted = structuredClone(first);
  shifted.knuckles!.thumb[0] += 24;
  expect(
    stableMeasurements([...Array(5).fill(first), ...Array(5).fill(shifted)]),
  ).toBe(false);
});
it("rejects incomplete landmark sets without crashing the scan", () => {
  expect(
    assessDetection({ landmarks: [[]], worldLandmarks: [[]], handedness: [] })
      .message,
  ).toMatch("Incomplete");
});
