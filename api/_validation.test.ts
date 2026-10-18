import { describe, expect, it } from "vitest";
import assessment from "../shared/contracts/fixtures/focus-assessment-four-seam.json";
import record from "../docs/contracts/v1/fixtures/throw-record-four-seam.json";
import { isCoachRequest } from "./_validation";

describe("throw record API validation", () => {
  const request = { assessment, throws: [record] };

  it("accepts records with both, either, or neither spin reading", () => {
    expect(isCoachRequest(request)).toBe(true);
    for (const measurements of [
      { ...record.measurements, spinEfficiencyPercent: 95, gyroDegree: null },
      {
        ...record.measurements,
        spinEfficiencyPercent: null,
        gyroDegree: -18.2,
      },
      { ...record.measurements, spinEfficiencyPercent: null, gyroDegree: null },
    ]) {
      expect(
        isCoachRequest({
          ...request,
          throws: [{ ...record, measurements }],
        }),
      ).toBe(true);
    }
  });

  it("requires nullable break fields in their -30 to 30 inch range", () => {
    expect(
      isCoachRequest({
        ...request,
        throws: [
          {
            ...record,
            measurements: {
              ...record.measurements,
              horizontalBreakInches: null,
              verticalBreakInches: null,
            },
          },
        ],
      }),
    ).toBe(true);
    expect(
      isCoachRequest({
        ...request,
        throws: [
          {
            ...record,
            measurements: {
              ...record.measurements,
              horizontalBreakInches: 30.1,
            },
          },
        ],
      }),
    ).toBe(false);
  });
});
