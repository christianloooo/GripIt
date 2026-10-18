/** Step 3 owns entry only. This is the v1 boundary consumed by Step 4. */
export interface ThrowRecord {
  schemaVersion: "1.0.0";
  throwId: string;
  sessionId: string;
  pitchId: string;
  recordedAt: string;
  measurements: {
    velocityMph: number;
    totalSpinRpm: number;
    /** Decimal clock hours, e.g. 12:30 = 12.5, matching the v1 fixture. */
    spinDirectionClock: number;
    spinEfficiencyPercent: number | null;
    gyroDegree: number | null;
    /** Inches, from the Rapsodo break chart. Positive = arm-side for a RHP. */
    horizontalBreakInches: number | null;
    /** Inches, induced vertical break. Positive = ride. */
    verticalBreakInches: number | null;
    releaseHeightFeet: number;
    rapsodoScore: number | null;
  };
  source: "manual" | "sample";
  extensions: Record<string, unknown>;
}

export interface ThrowDraft {
  id: string;
  velocityMph: string;
  totalSpinRpm: string;
  spinDirectionClock: string;
  spinEfficiencyPercent: string;
  gyroDegree: string;
  horizontalBreakInches: string;
  verticalBreakInches: string;
  releaseHeightFeet: string;
  rapsodoScore: string;
}
export interface ThrowSessionDraft {
  sessionId: string;
  source: ThrowRecord["source"];
  rows: ThrowDraft[];
}
export type EntryField = Exclude<keyof ThrowDraft, "id">;
export type EntryErrors = Partial<Record<EntryField, string>>;

export function emptyThrow(
  source: ThrowRecord["source"] = "manual",
): ThrowDraft {
  return {
    id: `${source === "sample" ? "sample-" : ""}throw-${crypto.randomUUID()}`,
    velocityMph: "",
    totalSpinRpm: "",
    spinDirectionClock: "",
    spinEfficiencyPercent: "",
    gyroDegree: "",
    horizontalBreakInches: "",
    verticalBreakInches: "",
    releaseHeightFeet: "",
    rapsodoScore: "",
  };
}

export function newThrowSession(
  source: ThrowRecord["source"] = "manual",
): ThrowSessionDraft {
  return {
    sessionId: `${source === "sample" ? "sample-" : ""}session-${crypto.randomUUID()}`,
    source,
    rows: [emptyThrow(source)],
  };
}

export function parseClock(value: string): number | null {
  const match = /^(0?[1-9]|1[0-2]):([0-5]\d)$/.exec(value.trim());
  return match ? Number(match[1]) + Number(match[2]) / 60 : null;
}

export function completeSpinMeasurements(
  spinEfficiencyPercent: number | null,
  gyroDegree: number | null,
): {
  spinEfficiencyPercent: number | null;
  gyroDegree: number | null;
} {
  if (spinEfficiencyPercent === null && gyroDegree !== null) {
    spinEfficiencyPercent = Math.cos((gyroDegree * Math.PI) / 180) * 100;
  } else if (gyroDegree === null && spinEfficiencyPercent !== null) {
    gyroDegree = (Math.acos(spinEfficiencyPercent / 100) * 180) / Math.PI;
  }
  return { spinEfficiencyPercent, gyroDegree };
}

export function validateThrow(row: ThrowDraft): {
  errors: EntryErrors;
  measurements: ThrowRecord["measurements"] | null;
} {
  const errors: EntryErrors = {};
  const number = (
    field: EntryField,
    label: string,
    min: number,
    max?: number,
    optional = false,
  ): number | null => {
    const raw = row[field].trim();
    if (!raw) {
      if (!optional) errors[field] = `Enter ${label}.`;
      return null;
    }
    const value = Number(raw);
    if (
      !/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(raw) ||
      !Number.isFinite(value)
    ) {
      errors[field] = "Enter a valid number.";
    } else if (value < min || (max !== undefined && value > max)) {
      errors[field] =
        max === undefined
          ? `Use ${min} or more.`
          : `Use ${min} to ${max}. Check the units.`;
    }
    return value;
  };
  // Broad typo checks only. These are not coaching thresholds or scoring ranges.
  const velocityMph = number("velocityMph", "velocity", 1, 120);
  const totalSpinRpm = number("totalSpinRpm", "total spin", 0, 5000);
  const releaseHeightFeet = number(
    "releaseHeightFeet",
    "release height",
    0,
    10,
  );
  const enteredSpinEfficiency = number(
    "spinEfficiencyPercent",
    "spin efficiency",
    0,
    100,
    true,
  );
  const enteredGyroDegree = number("gyroDegree", "gyro degree", -90, 90, true);
  const horizontalBreakInches = number(
    "horizontalBreakInches",
    "horizontal break",
    -30,
    30,
    true,
  );
  const verticalBreakInches = number(
    "verticalBreakInches",
    "vertical break",
    -30,
    30,
    true,
  );
  const rapsodoScore = number(
    "rapsodoScore",
    "Rapsodo score",
    0,
    undefined,
    true,
  );
  const spinDirectionClock = parseClock(row.spinDirectionClock);
  if (spinDirectionClock === null)
    errors.spinDirectionClock = "Use clock time, e.g. 12:30 (1:00 to 12:59).";
  const { spinEfficiencyPercent, gyroDegree } = completeSpinMeasurements(
    enteredSpinEfficiency,
    enteredGyroDegree,
  );
  return {
    errors,
    measurements: Object.keys(errors).length
      ? null
      : {
          velocityMph: velocityMph!,
          totalSpinRpm: totalSpinRpm!,
          spinDirectionClock: spinDirectionClock!,
          spinEfficiencyPercent,
          gyroDegree,
          horizontalBreakInches,
          verticalBreakInches,
          releaseHeightFeet: releaseHeightFeet!,
          rapsodoScore,
        },
  };
}

export function makeThrowRecords(
  session: ThrowSessionDraft,
  pitchId: string,
  options: { handProfileId?: string; recordedAt?: string } = {},
): ThrowRecord[] {
  if (!pitchId.trim() || !session.rows.length)
    throw new Error("A pitch and at least one throw are required.");
  const recordedAt = options.recordedAt ?? new Date().toISOString();
  return session.rows.map((row) => {
    const { measurements } = validateThrow(row);
    if (!measurements)
      throw new Error("Correct the highlighted fields before saving.");
    return {
      schemaVersion: "1.0.0",
      throwId: row.id,
      sessionId: session.sessionId,
      pitchId,
      recordedAt,
      measurements,
      source: session.source,
      extensions: options.handProfileId
        ? { "gripit.throwEntry": { handProfileId: options.handProfileId } }
        : {},
    };
  });
}

export function sampleThrowSession(): ThrowSessionDraft {
  const session = newThrowSession("sample");
  session.rows = [
    ["82.4", "2180", "12:30", "84", "18.6", "13.8", "5.8"],
    ["83.1", "2220", "12:40", "86", "18.2", "14.1", "5.7"],
    ["81.8", "2140", "12:20", "83", "19.0", "13.5", "5.8"],
  ].map(
    ([
      velocityMph,
      totalSpinRpm,
      spinDirectionClock,
      spinEfficiencyPercent,
      horizontalBreakInches,
      verticalBreakInches,
      releaseHeightFeet,
    ]) => ({
      ...emptyThrow("sample"),
      velocityMph,
      totalSpinRpm,
      spinDirectionClock,
      spinEfficiencyPercent,
      horizontalBreakInches,
      verticalBreakInches,
      releaseHeightFeet,
    }),
  );
  return session;
}
