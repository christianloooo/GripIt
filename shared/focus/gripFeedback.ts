import type { Handedness } from "../contracts/handProfile";
import type { FocusZone, InstructionZone, Severity, ZoneId } from "../contracts/zones";
import type { ThrowRecord } from "../throwEntry";
import {
  GRIP_RULES,
  GRIP_RULE_VERSION,
  clockText,
  checkedRuleReading,
  ruleReadingAvailable,
  type GripRule,
} from "./gripRules";
import { deriveMetrics, type DerivedMetrics } from "./metrics";
import { targetFor } from "./targets";

/**
 * Gates and precedence. Returns exactly one result.
 *
 * This module contains no rule copy and no target number. Every instruction
 * comes from the chosen GripRule and every threshold a rule tests comes from
 * targetFor(). The only number written here is the release-height drift
 * spread, which is lifted from the shipped engine and cited below.
 *
 * Dependencies point one way: metrics -> targets -> gripRules -> gripFeedback.
 * assess.ts sits downstream of this file and is never imported from it.
 */

export type FeedbackKind =
  | "change"
  | "fit"
  | "baseline"
  | "drift"
  | "on-target"
  | "no-data";

export interface GripFeedback {
  kind: FeedbackKind;
  measured: string; // always present, pure arithmetic
  headline: string;
  change: string | null;
  expect: string | null;
  zones: ZoneId[];
  ruleId: string | null;
  ruleVersion: string;
  source: string | null;
}

/**
 * Carried over from assess.ts, where it ships today as
 * DEFAULT_RELEASE_HEIGHT_DRIFT_FEET. Not a new number and not invented here:
 * the drift gate is the existing behaviour, re-expressed. assess.ts is
 * downstream of this module, so the constant is duplicated rather than
 * imported; Task 9 collapses the two when assess.ts starts delegating.
 */
const RELEASE_HEIGHT_DRIFT_FEET = 0.5;

/** Matches the shipped gate: fewer than three throws is not yet a trend. */
const MIN_THROWS_FOR_DRIFT = 3;

/**
 * Pitches judged only against the same pitcher's own fastball in the same
 * session, so they have nothing to say without one.
 *
 * Keyed on the pitch rather than derived from the rules on purpose. GripRule
 * carries no "needs a baseline" flag, and a detect() that returns null with a
 * null baseline is indistinguishable from one that simply did not fire, so
 * the dependency is not observable through the rule interface. The fact comes
 * from the design doc: "Changeup is judged only against the same pitcher's
 * fastball in the same session, so it needs a baseline and says so when it
 * has none."
 */
const PITCH_IDS_NEEDING_BASELINE: readonly string[] = ["changeup"];

function roundTo(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round((value + Number.EPSILON) * factor) / factor;
}

/** Arithmetic on what was entered. No judgement, so no target is consulted. */
function measuredText(m: DerivedMetrics): string {
  if (m.throwCount === 0) return "No throws recorded for this pitch yet.";

  const parts: string[] = [];
  if (m.velocityMph !== null) parts.push(`${m.velocityMph} mph`);
  if (m.totalSpinRpm !== null) parts.push(`${m.totalSpinRpm} rpm total spin`);
  if (m.spinEfficiencyPercent !== null) {
    parts.push(`${m.spinEfficiencyPercent} percent spin efficiency`);
  }
  if (m.activeSpinRpm !== null) {
    parts.push(`${m.activeSpinRpm} rpm active spin`);
  }
  if (m.spinPerMph !== null) parts.push(`${m.spinPerMph} spin per mph`);
  if (m.spinDirectionClock !== null) {
    parts.push(`axis ${clockText(m.spinDirectionClock)}`);
  }
  if (m.horizontalBreakInches !== null) {
    parts.push(`${m.horizontalBreakInches} in horizontal break`);
  }
  if (m.verticalBreakInches !== null) {
    parts.push(`${m.verticalBreakInches} in vertical break`);
  }

  const count = `${m.throwCount} ${m.throwCount === 1 ? "throw" : "throws"}`;
  return parts.length ? `${count}: ${parts.join(", ")}.` : `${count}.`;
}

interface Candidate {
  rule: GripRule;
  summary: string;
  magnitude: number;
}

/**
 * Every rule for this pitch that has something to say, in GRIP_RULES table
 * order. Built before any gate runs, because the fit gate needs to know which
 * zones the advice would have named.
 */
function candidatesFor(
  pitchId: string,
  metrics: DerivedMetrics,
  handedness: Handedness,
  baseline: DerivedMetrics | null,
): Candidate[] {
  // targetFor mirrors axis and horizontal break for a left-hander, so the
  // target is passed through to detect() rather than compared here. A literal
  // comparison in this module would invert the advice for every lefty.
  const target = targetFor(pitchId, handedness);
  if (!target) return [];

  const found: Candidate[] = [];
  for (const rule of GRIP_RULES) {
    if (!rule.pitchIds.includes(pitchId)) continue;
    const deviation = rule.detect(metrics, target, baseline);
    if (!deviation) continue;
    if (!Number.isFinite(deviation.magnitude) || deviation.magnitude <= 0) {
      continue;
    }
    found.push({
      rule,
      summary: deviation.summary,
      magnitude: deviation.magnitude,
    });
  }
  return found;
}

/**
 * Contacts this hand cannot make, among the zones the firing rules name.
 *
 * `strained` counts exactly like `unreachable`. The design says "strained
 * beyond tolerance", but no tolerance number exists in any file or document,
 * and inventing one is how the slider ceiling ended up thirty points wrong.
 * Until a sourced tolerance exists, a strained contact is treated as a fit
 * problem. zones.ts's unreachableZones() is not used because it covers only
 * `unreachable` and does not restrict itself to the zones in question.
 */
function unfittableZones(
  candidates: readonly Candidate[],
  zones: readonly InstructionZone[],
): ZoneId[] {
  const reachById = new Map(zones.map((zone) => [zone.zoneId, zone.reach]));
  const problems: ZoneId[] = [];
  for (const candidate of candidates) {
    for (const zoneId of candidate.rule.zones) {
      // A zone with no reach data is no evidence of a fit problem, so it
      // never suppresses advice.
      const reach = reachById.get(zoneId);
      if (reach !== "unreachable" && reach !== "strained") continue;
      if (!problems.includes(zoneId)) problems.push(zoneId);
    }
  }
  return problems;
}

function titleFor(
  zoneId: ZoneId,
  zones: readonly InstructionZone[],
): string {
  return zones.find((zone) => zone.zoneId === zoneId)?.title ?? zoneId;
}

/** Spread of release height, as the shipped engine measures it. */
function releaseHeightSpreadFeet(
  throws: readonly ThrowRecord[],
): number | null {
  if (throws.length < MIN_THROWS_FOR_DRIFT) return null;
  const heights = throws
    .map((t) => t.measurements.releaseHeightFeet)
    .filter((v): v is number => typeof v === "number" && Number.isFinite(v));
  if (heights.length < MIN_THROWS_FOR_DRIFT) return null;
  return roundTo(Math.max(...heights) - Math.min(...heights), 2);
}

function result(partial: Partial<GripFeedback> & {
  kind: FeedbackKind;
  measured: string;
  headline: string;
}): GripFeedback {
  return {
    change: null,
    expect: null,
    zones: [],
    ruleId: null,
    source: null,
    ruleVersion: GRIP_RULE_VERSION,
    ...partial,
  };
}

export interface GripFeedbackInput {
  pitchId: string;
  throws: readonly ThrowRecord[];
  zones: readonly InstructionZone[];
  baseline?: readonly ThrowRecord[];
  /**
   * Deviation from the plan's signature, added deliberately.
   *
   * targetFor() needs handedness, and its axis and horizontal-break ranges
   * are mirrored for a left-hander. Without this field every pitcher would be
   * judged against right-handed targets, which inverts the advice for every
   * left-hander rather than merely weakening it. Defaults to "right", which
   * is how PITCH_TARGETS is stored.
   */
  handedness?: Handedness;
}

export function gripFeedback(input: GripFeedbackInput): GripFeedback {
  const { pitchId, throws, zones, baseline, handedness = "right" } = input;

  const metrics = deriveMetrics(throws);
  const measured = measuredText(metrics);
  const baselineMetrics =
    baseline && baseline.length ? deriveMetrics(baseline) : null;

  // Gate 1: nothing entered. Names no zone, but still reports the arithmetic.
  if (metrics.throwCount === 0) {
    return result({
      kind: "no-data",
      measured,
      headline: "Record a few throws of this pitch to get a change to try.",
    });
  }

  // Candidates are built before any ranking so that correctness never depends
  // on the order rules come out in. A suppressed rule is suppressed by a
  // gate, never by scoring it lower.
  const candidates = candidatesFor(
    pitchId,
    metrics,
    handedness,
    baselineMetrics,
  );

  // Gate 2: fit, before ranking. If the advice would name a contact this hand
  // cannot make, the grip itself does not fit, so correcting a different
  // finger is premature. Never tell someone to move a finger they cannot
  // reach.
  const unfittable = unfittableZones(candidates, zones);
  if (unfittable.length) {
    const names = unfittable.map((zoneId) => titleFor(zoneId, zones));
    return result({
      kind: "fit",
      measured,
      headline: `This grip does not fit your hand yet: ${names.join(" and ")} cannot make the contact this pitch asks for. Work on the fit before changing technique.`,
      zones: unfittable,
    });
  }

  // Gate 3: a pitch judged against the pitcher's own fastball, with no
  // fastball to judge it against.
  if (PITCH_IDS_NEEDING_BASELINE.includes(pitchId) && !baselineMetrics) {
    return result({
      kind: "baseline",
      measured,
      headline:
        "This pitch is read against your own fastball, so throw some fastballs in the same session before it can be judged.",
    });
  }

  // Gate 4: release-height drift. A moving release point is an arm problem,
  // not a grip problem, so this outcome names no finger.
  const spread = releaseHeightSpreadFeet(throws);
  if (spread !== null && spread > RELEASE_HEIGHT_DRIFT_FEET) {
    return result({
      kind: "drift",
      measured,
      headline: `Your release height moved ${spread} feet across these throws. That is an arm-slot problem rather than a grip problem, so settle the release point first.`,
    });
  }

  // Gate 5: the largest normalised deviation wins. Strictly greater, so the
  // first row in GRIP_RULES order keeps a tie and identical input gives
  // identical output.
  let best: Candidate | null = null;
  for (const candidate of candidates) {
    if (!best || candidate.magnitude > best.magnitude) best = candidate;
  }
  if (best) {
    return result({
      kind: "change",
      measured,
      headline: best.summary,
      change: best.rule.change,
      expect: best.rule.expect,
      zones: [...best.rule.zones],
      ruleId: best.rule.id,
      source: best.rule.source,
    });
  }

  // Gate 6: rules exist for this pitch and none of them fired.
  const hasRules = GRIP_RULES.some((rule) => rule.pitchIds.includes(pitchId));
  return result({
    kind: "on-target",
    measured,
    headline: hasRules
      ? "Every reading for this pitch is inside its target range. Keep throwing it."
      : "No grip rules are written for this pitch yet, so there is nothing to flag.",
  });
}


/**
 * The engine does not score confidence. Reuse assess.ts's shipped 0.5
 * placeholder for every assessed zone and nonempty assessment; this is an
 * unscored value, not a calibrated probability. No-data confidence stays 0.
 */
export const UNSCORED_CONFIDENCE = 0.5;

const SEVERITY_ORDER: Record<Severity, number> = { green: 0, yellow: 1, red: 2 };

/**
 * The existing winner is red, other firing rules yellow, and checked clean
 * rules green. Gates suppress all severity. A missing/suppressed check has
 * no opinion. Equal severity keeps the first rule's reason in table order.
 */
export function gripFocusZones(
  input: GripFeedbackInput,
  feedback: GripFeedback,
): FocusZone[] {
  if (feedback.kind !== "change" && feedback.kind !== "on-target") return [];
  const target = targetFor(input.pitchId, input.handedness ?? "right");
  if (!target) return [];
  const metrics = deriveMetrics(input.throws);
  const baseline = input.baseline?.length ? deriveMetrics(input.baseline) : null;
  const candidates = candidatesFor(input.pitchId, metrics, input.handedness ?? "right", baseline);
  const byRule = new Map(candidates.map((candidate) => [candidate.rule.id, candidate]));
  const found = new Map<ZoneId, FocusZone>();
  for (const rule of GRIP_RULES) {
    if (!rule.pitchIds.includes(input.pitchId)) continue;
    if (!ruleReadingAvailable(rule, metrics, target, baseline)) continue;
    const candidate = byRule.get(rule.id);
    const clean = candidate ? null : checkedRuleReading(rule, metrics, target, baseline);
    if (!candidate && !clean) continue;
    const severity: Severity = candidate
      ? (rule.id === feedback.ruleId ? "red" : "yellow")
      : "green";
    // Efficiency may have come entirely from gyro rather than an entered
    // efficiency reading. Keep the wire key tied to a measurement present.
    const measurement = rule.reading.measurement === "spinEfficiencyPercent" &&
      !input.throws.some((t) => Number.isFinite(t.measurements.spinEfficiencyPercent) &&
        t.measurements.spinEfficiencyPercent !== null)
      ? "gyroDegree" : rule.reading.measurement;
    for (const zoneId of rule.zones) {
      const previous = found.get(zoneId);
      if (previous && SEVERITY_ORDER[previous.severity] >= SEVERITY_ORDER[severity]) continue;
      found.set(zoneId, {
        zoneId,
        severity,
        reason: candidate?.summary ?? clean!.reason,
        triggeringMeasurement: measurement,
        confidence: UNSCORED_CONFIDENCE,
      });
    }
  }
  return [...found.values()];
}
