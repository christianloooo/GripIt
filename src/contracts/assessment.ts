import type { FocusZone, ZoneId } from "./zones";

/**
 * The boundary between the deterministic rule engine and everything that
 * presents its result.
 *
 * The engine decides every colour, reason and confidence. The language model
 * downstream rewrites `nextAction.detail` into something that sounds like a
 * coach; it never changes a severity, picks a zone, or invents a number. That
 * separation is what keeps the same inputs producing the same assessment.
 */

/** Whether the throw data justifies grip advice at all. */
export type AssessmentClassification = "grip-focus" | "not-grip";

/**
 * The one thing to change before the next throw. Exactly one per assessment,
 * because a player cannot work on five things at once.
 */
export interface NextAction {
  /** The zone to work on, or null when the finding is not about the grip. */
  zoneId: ZoneId | null;
  /** Short imperative, e.g. "Stay behind the ball". */
  summary: string;
  /**
   * The coachable detail. The rule set supplies a deterministic sentence here
   * and the language model may rewrite it. If the model is unavailable this
   * text ships unchanged, so the product never depends on a network call.
   */
  detail: string;
  /** True once a model has rewritten `detail`, so the UI can label it. */
  rewritten: boolean;
}

/** Spread across a session. Only meaningful with three or more throws. */
export interface ConsistencyReport {
  throwCount: number;
  velocitySpreadMph: number;
  totalSpinSpreadRpm: number;
  /** True when spread is wide enough that single-throw advice is unreliable. */
  inconsistent: boolean;
}

export interface FocusAssessment {
  schemaVersion: "1.0.0";
  assessmentId: string;
  gripPlanId: string;
  throwIds: string[];
  /** Which rule set produced this. Shown in the UI and stored with the result. */
  ruleVersion: string;
  classification: AssessmentClassification;
  /** Only zones a rule actually reached. Absent is not the same as green. */
  zones: FocusZone[];
  nextAction: NextAction;
  /** Inclusive 0...1 over the assessment as a whole. */
  confidence: number;
  /**
   * Zones the grip asks for but this hand cannot reach, copied from the plan.
   * Present so the UI can explain a fit problem instead of a technique fault.
   */
  unreachableZones: ZoneId[];
  consistency: ConsistencyReport | null;
  /** True while the rule set has not been reviewed by a pitching coach. */
  prototypeAdvice: boolean;
  extensions: Record<string, unknown>;
}
