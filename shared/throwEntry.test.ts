import { describe, expect, it } from "vitest";
import fixture from "../docs/contracts/v1/fixtures/throw-record-four-seam.json";
import {
  completeSpinMeasurements,
  emptyThrow,
  makeThrowRecords,
  newThrowSession,
  parseClock,
  sampleThrowSession,
  validateThrow,
} from "./throwEntry";

describe("v1 throw entry boundary", () => {
  it("accepts screenshot readings without inventing a release height", () => {
    const row = { ...emptyThrow(), velocityMph: "77.3", totalSpinRpm: "1642",
      spinDirectionClock: "01:56", spinEfficiencyPercent: "93.8",
      horizontalBreakInches: "18.6", verticalBreakInches: "13.8" };
    const result = validateThrow(row);
    expect(result.errors).toEqual({});
    expect(result.measurements?.releaseHeightFeet).toBeNull();
    expect(validateThrow({ ...row, releaseHeightFeet: "0" }).measurements?.releaseHeightFeet).toBe(0);
    expect(validateThrow({ ...row, releaseHeightFeet: "11" }).errors).toHaveProperty("releaseHeightFeet");
  });

  it("uses decimal clock hours, including 12:30 = 12.5", () => {
    expect(parseClock("12:30")).toBe(12.5);
    expect(parseClock("1:15")).toBe(1.25);
    expect(parseClock("09:00")).toBe(9);
    for (const value of ["", "00:00", "13:00", "12:60", "12:3", "12.5"])
      expect(parseClock(value)).toBeNull();
  });
  it("matches the shared fixture shape and numeric measurements", () => {
    const records = makeThrowRecords(sampleThrowSession(), "four-seam", {
      recordedAt: fixture.recordedAt,
    });
    expect(Object.keys(records[0]).sort()).toEqual(Object.keys(fixture).sort());
    expect(records[0].measurements).toEqual(fixture.measurements);
    expect(
      records.every(
        (record) =>
          record.source === "sample" && record.schemaVersion === "1.0.0",
      ),
    ).toBe(true);
    expect(new Set(records.map((record) => record.sessionId)).size).toBe(1);
    expect(new Set(records.map((record) => record.throwId)).size).toBe(3);
  });
  it("keeps missing optionals null and preserves zero", () => {
    const row = sampleThrowSession().rows[0];
    expect(
      validateThrow({
        ...row,
        spinEfficiencyPercent: "0",
        gyroDegree: "",
        horizontalBreakInches: "",
        verticalBreakInches: "",
        rapsodoScore: "0",
      }).measurements,
    ).toMatchObject({
      spinEfficiencyPercent: 0,
      gyroDegree: 90,
      horizontalBreakInches: null,
      verticalBreakInches: null,
      rapsodoScore: 0,
    });
    const gyroOnly = validateThrow({
      ...row,
      spinEfficiencyPercent: "",
      gyroDegree: "-90",
    }).measurements;
    expect(gyroOnly).toMatchObject({ gyroDegree: -90, rapsodoScore: null });
    expect(gyroOnly?.spinEfficiencyPercent).toBeCloseTo(0, 10);
  });
  it("accepts both, either, or neither spin reading and derives the missing value", () => {
    expect(completeSpinMeasurements(null, null)).toEqual({
      spinEfficiencyPercent: null,
      gyroDegree: null,
    });
    expect(completeSpinMeasurements(95, -18.2)).toEqual({
      spinEfficiencyPercent: 95,
      gyroDegree: -18.2,
    });
    expect(
      completeSpinMeasurements(null, -18.2).spinEfficiencyPercent,
    ).toBeCloseTo(95, 2);
    expect(completeSpinMeasurements(95, null).gyroDegree).toBeCloseTo(18.2, 1);

    const row = sampleThrowSession().rows[0];
    expect(
      validateThrow({
        ...row,
        spinEfficiencyPercent: "",
        gyroDegree: "",
      }).measurements,
    ).toMatchObject({ spinEfficiencyPercent: null, gyroDegree: null });
    expect(
      validateThrow({
        ...row,
        spinEfficiencyPercent: "95",
        gyroDegree: "-18.2",
      }).measurements,
    ).toMatchObject({ spinEfficiencyPercent: 95, gyroDegree: -18.2 });
  });
  it("accepts nullable break readings from -30 to 30 inches", () => {
    const row = sampleThrowSession().rows[0];
    expect(
      validateThrow({
        ...row,
        horizontalBreakInches: "-30",
        verticalBreakInches: "30",
      }).measurements,
    ).toMatchObject({
      horizontalBreakInches: -30,
      verticalBreakInches: 30,
    });
    expect(
      validateThrow({ ...row, horizontalBreakInches: "-30.1" }).errors,
    ).toHaveProperty("horizontalBreakInches");
    expect(
      validateThrow({ ...row, verticalBreakInches: "30.1" }).errors,
    ).toHaveProperty("verticalBreakInches");
  });
  it("rejects blanks, non-numbers and likely unit mistakes without changing drafts", () => {
    expect(Object.keys(validateThrow(emptyThrow()).errors)).toHaveLength(3);
    const row = {
      ...sampleThrowSession().rows[0],
      velocityMph: "900",
      totalSpinRpm: "Infinity",
      spinEfficiencyPercent: "101",
      releaseHeightFeet: "165",
      rapsodoScore: "-1",
    };
    expect(Object.keys(validateThrow(row).errors)).toHaveLength(5);
    expect(row.velocityMph).toBe("900");
    expect(() =>
      makeThrowRecords({ ...newThrowSession(), rows: [row] }, "four-seam"),
    ).toThrow();
    expect(() =>
      makeThrowRecords({ ...newThrowSession(), rows: [] }, "four-seam"),
    ).toThrow();
    expect(
      validateThrow({ ...sampleThrowSession().rows[0], velocityMph: "0x50" })
        .measurements,
    ).toBeNull();
  });
  it("keeps manual IDs and optional hand-profile linkage separate from sample records", () => {
    const session = newThrowSession();
    session.rows[0] = {
      ...sampleThrowSession().rows[0],
      id: session.rows[0].id,
    };
    const first = makeThrowRecords(session, "slider", {
      handProfileId: "profile-123",
    })[0];
    const again = makeThrowRecords(session, "slider")[0];
    expect(first.source).toBe("manual");
    expect(first.throwId).not.toMatch(/^sample-/);
    expect(first.sessionId).not.toMatch(/^sample-/);
    expect(again.throwId).toBe(first.throwId);
    expect(again.sessionId).toBe(first.sessionId);
    expect(first.extensions).toEqual({
      "gripit.throwEntry": { handProfileId: "profile-123" },
    });
    expect(again.extensions).toEqual({});
  });
});
