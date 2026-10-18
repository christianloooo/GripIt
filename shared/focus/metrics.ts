import type { ThrowRecord } from "../throwEntry";

/**
 * Pure arithmetic over throw records. No thresholds, targets or pitch types:
 * judging these numbers belongs to later modules.
 */
export interface DerivedMetrics {
  throwCount: number;
  velocityMph: number | null;
  totalSpinRpm: number | null;
  spinEfficiencyPercent: number | null; // filled from gyro when absent
  activeSpinRpm: number | null;
  spinPerMph: number | null;
  spinDirectionClock: number | null;
  horizontalBreakInches: number | null;
  verticalBreakInches: number | null;
}

// Rounding is for stable, readable output, not precision. Whole rpm matches how
// Rapsodo displays spin (1077 * 0.95 = 1023.15 shows as 1023). One decimal
// matches mph, percent, inches and spin per mph. Two decimals keep clock
// positions to about a third of a minute.
function round(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

function isNumber(value: number | null | undefined): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

// Even counts average the two middle values. Returns null when nothing to rank.
function median(values: readonly (number | null | undefined)[]): number | null {
  const present = values.filter(isNumber).sort((a, b) => a - b);
  if (!present.length) return null;
  const mid = Math.floor(present.length / 2);
  return present.length % 2
    ? present[mid]
    : (present[mid - 1] + present[mid]) / 2;
}

/** Efficiency is cos(gyro). Cosine is even, so the gyro sign does not matter. */
export function efficiencyFromGyro(gyroDegree: number): number {
  return round(Math.cos((gyroDegree * Math.PI) / 180) * 100, 1);
}

/** Shortest distance between two clock positions. The clock wraps, so max is 6. */
export function clockHoursApart(a: number, b: number): number {
  const diff = Math.abs(a - b) % 12;
  return Math.min(diff, 12 - diff);
}

export function deriveMetrics(throws: readonly ThrowRecord[]): DerivedMetrics {
  const column = (key: keyof ThrowRecord["measurements"]) =>
    throws.map((t) => t.measurements[key]);

  // Backfill per throw so one throw's gyro cannot be lost in an aggregate.
  const efficiencies = throws.map(({ measurements: m }) => {
    if (isNumber(m.spinEfficiencyPercent)) return m.spinEfficiencyPercent;
    return isNumber(m.gyroDegree) ? efficiencyFromGyro(m.gyroDegree) : null;
  });

  const velocity = median(column("velocityMph"));
  const totalSpin = median(column("totalSpinRpm"));
  const efficiency = median(efficiencies);
  const direction = median(column("spinDirectionClock"));
  const horizontal = median(column("horizontalBreakInches"));
  const vertical = median(column("verticalBreakInches"));

  // Derived from the aggregated medians, never by averaging per-throw ratios.
  const activeSpin =
    totalSpin !== null && efficiency !== null
      ? (totalSpin * efficiency) / 100
      : null;
  const spinPerMph =
    totalSpin !== null && velocity !== null && velocity > 0
      ? totalSpin / velocity
      : null;

  const rounded = (value: number | null, decimals: number) =>
    value === null ? null : round(value, decimals);

  return {
    throwCount: throws.length,
    velocityMph: rounded(velocity, 1),
    totalSpinRpm: rounded(totalSpin, 0),
    spinEfficiencyPercent: rounded(efficiency, 1),
    activeSpinRpm: rounded(activeSpin, 0),
    spinPerMph: rounded(spinPerMph, 1),
    spinDirectionClock: rounded(direction, 2),
    horizontalBreakInches: rounded(horizontal, 1),
    verticalBreakInches: rounded(vertical, 1),
  };
}
