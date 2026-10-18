import {
  makeThrowRecords,
  newThrowSession,
  sampleThrowSession,
  type ThrowRecord,
} from "../throwEntry";

/**
 * The two inputs the demo is driven with, as ThrowRecords.
 *
 * Both are built through makeThrowRecords() so they go through the same
 * parsing and validation a hand-typed session does. A fixture that bypassed
 * validateThrow() could hold a reading the app will never actually produce,
 * which is the opposite of what a demo fixture is for.
 *
 * No target, threshold or expected rule id lives here. This module is
 * readings only; what the engine makes of them belongs to the tests.
 */

/** Fixed so a fixture built twice is byte-identical apart from its ids. */
const RECORDED_AT = "2026-10-18T00:00:00.000Z";

/**
 * `rapsodo2.webp`, transcribed: 77.3 mph, 1642 rpm, axis 1:56, 93.8 percent
 * efficiency, 13.8 inch vertical and 18.6 inch horizontal break. One throw,
 * because the screenshot is one pitch.
 *
 * The pitch is a parameter because the demo runs this same reading as both a
 * four-seam and a two-seam. That is the point of the first two demo paths:
 * one set of numbers, two intents, two different changes to try.
 *
 * Release height is not on the transcribed screenshot and is not a reading.
 * It is required by ThrowRecord, and with a single throw the release-drift
 * gate never looks at it, since that gate needs three throws.
 */
export function rapsodo2Throws(pitchId: string): ThrowRecord[] {
  const session = newThrowSession("sample");
  session.rows = [
    {
      ...session.rows[0],
      velocityMph: "77.3",
      totalSpinRpm: "1642",
      spinDirectionClock: "1:56",
      spinEfficiencyPercent: "93.8",
      horizontalBreakInches: "18.6",
      verticalBreakInches: "13.8",
      releaseHeightFeet: "5.8",
    },
  ];
  return makeThrowRecords(session, pitchId, { recordedAt: RECORDED_AT });
}

/**
 * The three rows `sampleThrowSession()` already ships, unchanged. Taken from
 * that function rather than retyped here so the demo always reads whatever
 * the sample session actually holds, and a correction there reaches this
 * fixture without anyone remembering to copy it across.
 *
 * `shared/throwEntry.ts` is not ours to edit, which is exactly why this
 * fixture defers to it.
 */
export function sampleSessionThrows(pitchId: string): ThrowRecord[] {
  return makeThrowRecords(sampleThrowSession(), pitchId, {
    recordedAt: RECORDED_AT,
  });
}
