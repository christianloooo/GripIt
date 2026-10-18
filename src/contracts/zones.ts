/**
 * The shared zone vocabulary for GripIt v1.
 *
 * Three workstreams meet on `ZoneId` and nothing else:
 *
 * - Step 2 (grip model) decides where each zone sits on the hand and what the
 *   player should do with it.
 * - Step 4 (focus assessment) decides what colour each zone is and why.
 * - The viewer merges the two by `zoneId`.
 *
 * Neither side reads the other's internals. Changing this file changes every
 * workstream, so it changes only by agreement across all three.
 */

export const ZONE_IDS = [
  "index-pad",
  "middle-pad",
  "ring-side",
  "pinky",
  "thumb-pad",
  "palm",
  "wrist",
] as const;

export type ZoneId = (typeof ZONE_IDS)[number];

/** Green looks fine. Yellow is worth a look. Red is where to start. */
export type Severity = "green" | "yellow" | "red";

/** How hard the zone presses. `none` means the zone stays clear of the ball. */
export type Pressure = "none" | "light" | "medium" | "firm";

/** What the zone is for in this grip. */
export type ZoneRole = "drive" | "support" | "clear";

/**
 * Step 2 output, one per zone. Describes the intended grip. Carries no
 * assessment: a zone reads the same whether or not the player has thrown yet.
 */
export interface InstructionZone {
  zoneId: ZoneId;
  /** Short label for the panel heading, e.g. "Index finger". */
  title: string;
  /** One sentence the player can act on, e.g. "Pad across the seam". */
  instruction: string;
  pressure: Pressure;
  role: ZoneRole;
}

/**
 * Step 4 output, one per zone the rules had something to say about. Zones the
 * rules did not reach are absent rather than green, so "no opinion" and
 * "checked and fine" stay distinguishable.
 */
export interface FocusZone {
  zoneId: ZoneId;
  severity: Severity;
  /** Why this colour, in plain words, naming the number that triggered it. */
  reason: string;
  /** The ThrowRecord measurement key that triggered the rule. */
  triggeringMeasurement: string;
  /** Inclusive 0...1. Drops when the triggering measurement was null. */
  confidence: number;
}

/** What the viewer needs to tint the model. Absent means step 2 mode. */
export type ZoneSeverityMap = Partial<Record<ZoneId, Severity>>;

export function isZoneId(value: string): value is ZoneId {
  return (ZONE_IDS as readonly string[]).includes(value);
}

/** Collapses assessed zones into the map the viewer takes. */
export function toSeverityMap(zones: readonly FocusZone[]): ZoneSeverityMap {
  const map: ZoneSeverityMap = {};
  for (const zone of zones) map[zone.zoneId] = zone.severity;
  return map;
}
