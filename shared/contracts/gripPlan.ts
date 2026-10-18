import type { InstructionZone } from "./zones";

/**
 * Step 2's output, as step 4 reads it.
 *
 * The geometry fields are typed `unknown` on purpose. Step 4 has no business
 * reconstructing the pose, and making that a type error is cheaper than a
 * review comment.
 */
export interface GripPlan {
  schemaVersion: "1.0.0";
  gripPlanId: string;
  handProfileId: string;
  pitchId: string;
  ballTransform: unknown;
  jointTransforms: unknown;
  contacts: unknown;
  instructionZones: InstructionZone[];
  fit: {
    /** Inclusive 0...1. How well the pitch fits this hand overall. */
    confidence: number | null;
    /** Contacts the solver could not satisfy, in its own words. */
    unresolved?: string[];
  };
  extensions: Record<string, unknown>;
}
