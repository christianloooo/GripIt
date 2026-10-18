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
 * Whether this hand can actually make the contact the pitch asks for.
 *
 * `role` and `pressure` come from the pitch and describe coaching intent. They
 * do not change with hand size: an index finger drives a four-seam whether the
 * hand is large or small. What changes with hand size is whether the intended
 * contact is reachable at all, and that is this field.
 *
 * Step 4 must not tell a player to press harder on a zone they cannot reach.
 */
export type ZoneReach = "comfortable" | "strained" | "unreachable";

/** Which part of the finger makes the contact. */
export type ContactSurface = "pad" | "tip" | "side" | "curl" | "none";

/**
 * Roughly where on the ball the contact sits, in the frame of the hand's
 * approach rather than the ball's own axes. The ball is re-oriented per pitch,
 * so an absolute ball coordinate would mean nothing without that orientation.
 */
export type BallRegion =
  | "top"
  | "underside"
  | "thumb-side"
  | "pinky-side"
  | "off-ball";

/**
 * How the contact sits relative to the nearest seam.
 *
 * `across` means the stitching runs perpendicular to the finger and passes
 * under the pad. `along` means the stitching runs parallel to the finger.
 * That distinction is the whole difference between a four-seam and a two-seam.
 */
export type SeamRelation = "across" | "along" | "beside" | "off" | "none";

/**
 * Where to put the finger, as opposed to how hard to press. Null on zones that
 * are not finger contacts, such as the palm and the wrist.
 *
 * This is a specification, not a solution. It says what the grip requires; the
 * step 2 solver decides the actual joint angles and ball pose that satisfy it.
 */
export interface ZonePlacement {
  surface: ContactSurface;
  region: BallRegion;
  seam: SeamRelation;
  /**
   * Millimetres from the seam centre line. `0` means directly on the
   * stitching. Null where the source describes the relationship but gives no
   * distance, leaving the solver to choose a comfortable one.
   */
  seamOffsetMm: number | null;
  /**
   * Zones this contact sits opposite across the ball. Several entries mean it
   * opposes the midpoint between them: a four-seam thumb sits under the gap
   * between the index and middle fingers, not under either one.
   */
  opposes: ZoneId[];
}

/**
 * Step 2 output, one per zone. Describes the intended grip for one pitch,
 * fitted to one hand. Carries no assessment: a zone reads the same whether or
 * not the player has thrown yet.
 *
 * Roles are per pitch, not fixed per finger. On a four-seam the index pad
 * drives and the pinky stays clear; on a circle change the index curls into a
 * loop with the thumb and the pinky wraps the far side to stabilise. A
 * `GripPlan` therefore carries its own zone set rather than referring to one
 * baked into the model.
 */
export interface InstructionZone {
  zoneId: ZoneId;
  /** Short label for the panel heading, e.g. "Index finger". */
  title: string;
  /** One sentence the player can act on, e.g. "Pad across the seam". */
  instruction: string;
  /** From the pitch. Not scaled by hand size. */
  pressure: Pressure;
  /** From the pitch. Not scaled by hand size. */
  role: ZoneRole;
  /** From fitting the pitch to this hand. This is where hand size lands. */
  reach: ZoneReach;
  /** Where the contact goes. Null for the palm and wrist, which are not finger contacts. */
  placement: ZonePlacement | null;
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
  /** Short action for a firing rule; absent on clean checks and old records. */
  action?: string;
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

/**
 * Zones whose contact this hand cannot make. Step 4 suppresses pressure and
 * technique advice for these and reports a fit problem instead.
 */
export function unreachableZones(
  zones: readonly InstructionZone[],
): ZoneId[] {
  return zones.filter((zone) => zone.reach === "unreachable").map((z) => z.zoneId);
}

/** Collapses assessed zones into the map the viewer takes. */
export function toSeverityMap(zones: readonly FocusZone[]): ZoneSeverityMap {
  const map: ZoneSeverityMap = {};
  for (const zone of zones) map[zone.zoneId] = zone.severity;
  return map;
}
