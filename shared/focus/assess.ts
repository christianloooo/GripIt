import type {
  AssessInput,
  AssessmentClassification,
  AssessmentRule,
  ConsistencyReport,
  FocusAssessment,
  NextAction,
  RuleCondition,
  RuleSet,
  RuleZone,
  ThrowMeasurementKey,
} from "../contracts/assessment";
import {
  unreachableZones,
  type FocusZone,
  type InstructionZone,
  type Severity,
  type ZoneId,
} from "../contracts/zones";
import type { ThrowRecord } from "../throwEntry";
import { DEFAULT_RULE_SET, SAMPLE_RULE_SET } from "./rules";

export type {
  AssessInput,
  AssessmentRule,
  RuleCondition,
  RuleSet,
  RuleZone,
  ThrowMeasurementKey,
};
export { DEFAULT_RULE_SET, SAMPLE_RULE_SET };

const SEVERITY_RANK: Record<Severity, number> = {
  green: 1,
  yellow: 2,
  red: 3,
};

const DEFAULT_RELEASE_HEIGHT_DRIFT_FEET = 0.5;
const DEFAULT_VELOCITY_SPREAD_MPH = 3;
const DEFAULT_TOTAL_SPIN_SPREAD_RPM = 200;

function roundNumber(value: number, decimals = 2): number {
  const factor = 10 ** decimals;
  return Math.round((value + Number.EPSILON) * factor) / factor;
}

function clampConfidence(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return roundNumber(Math.min(1, Math.max(0, value)), 2);
}

function formatMetricValue(value: number): string {
  return Number.isInteger(value)
    ? String(value)
    : String(roundNumber(value, 1));
}

function primaryThreshold(when: RuleCondition): number | undefined {
  return (
    when.target ?? when.below ?? when.atLeast ?? when.above ?? when.atMost
  );
}

function interpolateReason(
  template: string,
  value: number,
  when: RuleCondition,
): string {
  const formattedValue = formatMetricValue(value);
  const thresholdBound =
    when.target ?? when.below ?? when.atLeast ?? when.above ?? when.atMost;
  const targetBound = primaryThreshold(when);

  return template
    .replaceAll("{value}", formattedValue)
    .replaceAll(
      "{threshold}",
      thresholdBound !== undefined ? formatMetricValue(thresholdBound) : "",
    )
    .replaceAll(
      "{target}",
      targetBound !== undefined ? formatMetricValue(targetBound) : "",
    );
}

function matchesCondition(value: number, when: RuleCondition): boolean {
  const hasBound =
    when.below !== undefined ||
    when.atLeast !== undefined ||
    when.above !== undefined ||
    when.atMost !== undefined;
  if (!hasBound || !Number.isFinite(value)) return false;

  if (when.below !== undefined && !(value < when.below)) return false;
  if (when.atLeast !== undefined && !(value >= when.atLeast)) return false;
  if (when.above !== undefined && !(value > when.above)) return false;
  if (when.atMost !== undefined && !(value <= when.atMost)) return false;
  return true;
}

function resolveZoneBaseConfidence(
  rule: AssessmentRule,
  ruleZone: RuleZone,
): number {
  if (
    typeof ruleZone.confidence === "number" &&
    Number.isFinite(ruleZone.confidence)
  ) {
    return ruleZone.confidence;
  }
  if (ruleZone.severity === "red") {
    return ruleZone.zoneId === rule.nextAction.zoneId
      ? rule.confidence
      : roundNumber(Math.max(0, rule.confidence - 0.1));
  }
  if (ruleZone.severity === "yellow") {
    return roundNumber(Math.max(0, rule.confidence - 0.2));
  }
  return rule.confidence;
}

function mentionsUnreachableZone(
  text: string,
  unreachableSet: ReadonlySet<ZoneId>,
): boolean {
  const lowered = text.toLowerCase();
  for (const zoneId of unreachableSet) {
    if (lowered.includes(zoneId) || lowered.includes(zoneId.replace("-", " "))) {
      return true;
    }
  }
  return false;
}

function computeConsistency(
  throws: readonly ThrowRecord[],
  ruleSet: RuleSet,
): ConsistencyReport | null {
  if (throws.length < 3) return null;

  const velocities = throws
    .map((t) => t.measurements.velocityMph)
    .filter((v): v is number => typeof v === "number" && Number.isFinite(v));
  const spins = throws
    .map((t) => t.measurements.totalSpinRpm)
    .filter((v): v is number => typeof v === "number" && Number.isFinite(v));

  const velocitySpreadMph =
    velocities.length >= 2
      ? roundNumber(Math.max(...velocities) - Math.min(...velocities), 2)
      : 0;
  const totalSpinSpreadRpm =
    spins.length >= 2
      ? roundNumber(Math.max(...spins) - Math.min(...spins), 2)
      : 0;

  const velocityLimit =
    ruleSet.velocitySpreadThresholdMph ?? DEFAULT_VELOCITY_SPREAD_MPH;
  const spinLimit =
    ruleSet.totalSpinSpreadThresholdRpm ?? DEFAULT_TOTAL_SPIN_SPREAD_RPM;

  return {
    throwCount: throws.length,
    velocitySpreadMph,
    totalSpinSpreadRpm,
    inconsistent:
      velocitySpreadMph > velocityLimit || totalSpinSpreadRpm > spinLimit,
  };
}

function isReleaseHeightDrifting(
  throws: readonly ThrowRecord[],
  ruleSet: RuleSet,
): boolean {
  if (throws.length < 3) return false;
  const heights = throws
    .map((t) => t.measurements.releaseHeightFeet)
    .filter((v): v is number => typeof v === "number" && Number.isFinite(v));
  if (heights.length < 3) return false;

  const spread = roundNumber(Math.max(...heights) - Math.min(...heights), 2);
  const threshold =
    ruleSet.releaseHeightDriftFeet ?? DEFAULT_RELEASE_HEIGHT_DRIFT_FEET;
  return spread > threshold;
}

function deriveGripPlanId(
  pitchId: string,
  throws: readonly ThrowRecord[],
  explicitId?: string,
): string {
  if (explicitId && explicitId.trim()) return explicitId;
  const isSample =
    throws.length === 0 ||
    throws.some(
      (t) => t.source === "sample" || t.throwId.startsWith("sample-"),
    );
  return `${isSample ? "sample-" : ""}${pitchId}-average-right`;
}

function deriveAssessmentId(
  pitchId: string,
  throws: readonly ThrowRecord[],
  explicitId?: string,
): string {
  if (explicitId && explicitId.trim()) return explicitId;
  if (throws.length === 1 && throws[0].throwId === "sample-throw-1") {
    return "sample-assessment-1";
  }
  const isSample =
    throws.length > 0 &&
    throws.every(
      (t) => t.source === "sample" || t.throwId.startsWith("sample-"),
    );
  const ids = throws.map((t) => t.throwId).join("-");
  return `${isSample ? "sample-" : ""}assessment-${pitchId}${ids ? `-${ids}` : ""}`;
}

function fallbackNotGripAction(
  pitchId: string,
  reason: "unreachable" | "null-measurement" | "release-drift" | "no-finding",
): NextAction {
  if (reason === "release-drift") {
    return {
      zoneId: null,
      summary: "Steady your release point",
      detail:
        "Release height drifted across this session, which points to arm slot and timing rather than finger placement.",
      rewritten: false,
    };
  }
  if (reason === "unreachable") {
    return {
      zoneId: null,
      summary: "Adjust grip for hand fit",
      detail:
        "This hand cannot reach every required contact for this grip. Adjust the grip fit before changing release technique.",
      rewritten: false,
    };
  }
  if (reason === "null-measurement") {
    return {
      zoneId: null,
      summary: "Record spin efficiency on the next throw",
      detail:
        "The measurement needed to evaluate this grip was not provided, so no finger adjustment is suggested yet.",
      rewritten: false,
    };
  }
  if (pitchId === "changeup") {
    return {
      zoneId: null,
      summary: "Compare against your fastball",
      detail:
        "Changeup evaluation needs fastball velocity from the same session to judge separation, so no grip change is suggested from changeup throws alone.",
      rewritten: false,
    };
  }
  if (pitchId === "slider") {
    return {
      zoneId: null,
      summary: "Keep working the slider release",
      detail:
        "Slider spin metrics are within the expected low-efficiency range, so no grip adjustment is flagged.",
      rewritten: false,
    };
  }
  return {
    zoneId: null,
    summary: "Keep the current grip",
    detail:
      "Available throw numbers do not point to a grip adjustment on this pitch.",
    rewritten: false,
  };
}

/**
 * Pure, deterministic Step 4 rule engine.
 *
 * Evaluates Rapsodo `ThrowRecord` values against versioned `RuleSet` data and
 * Step 2 `InstructionZone` reach constraints without network calls, clocks,
 * randomness, or mutation of any input.
 */
export function assess(input: AssessInput): FocusAssessment {
  const { pitchId, throws, zones, ruleSet } = input;
  const ruleVersion =
    ruleSet.ruleVersion?.trim() || ruleSet.version?.trim() || "sample-rules-1";
  const prototypeAdvice = ruleSet.prototypeAdvice ?? true;
  const throwIds = throws.map((t) => t.throwId);
  const gripPlanId = deriveGripPlanId(pitchId, throws, input.gripPlanId);
  const assessmentId = deriveAssessmentId(pitchId, throws, input.assessmentId);

  const unreachable = unreachableZones(zones);
  const unreachableSet = new Set<ZoneId>(unreachable);

  // Zones explicitly present in the plan with empty instruction text stay untinted.
  const silentZoneSet = new Set<ZoneId>(
    zones
      .filter((z: InstructionZone) => z.instruction.trim() === "")
      .map((z: InstructionZone) => z.zoneId),
  );

  const consistency = computeConsistency(throws, ruleSet);

  // Safety Rule 3: Release-height drift across 3+ throws is `not-grip` and colors nothing.
  if (isReleaseHeightDrifting(throws, ruleSet)) {
    return {
      schemaVersion: "1.0.0",
      assessmentId,
      gripPlanId,
      throwIds,
      ruleVersion,
      classification: "not-grip",
      zones: [],
      nextAction: fallbackNotGripAction(pitchId, "release-drift"),
      confidence: 0.5,
      unreachableZones: unreachable,
      consistency,
      prototypeAdvice,
      extensions: {},
    };
  }

  const pitchRules = ruleSet.rules.filter((rule) =>
    rule.pitchIds.includes(pitchId),
  );

  if (throws.length === 0 || pitchRules.length === 0) {
    return {
      schemaVersion: "1.0.0",
      assessmentId,
      gripPlanId,
      throwIds,
      ruleVersion,
      classification: "not-grip",
      zones: [],
      nextAction: fallbackNotGripAction(pitchId, "no-finding"),
      confidence: throws.length === 0 ? 0 : 0.25,
      unreachableZones: unreachable,
      consistency,
      prototypeAdvice,
      extensions: {},
    };
  }

  // Safety Rule 2: Track measurement availability across applicable rules.
  // A rule whose measurement is null never fires, and missing measurements lower confidence.
  const referencedMeasurements = Array.from(
    new Set<ThrowMeasurementKey>(pitchRules.map((rule) => rule.measurement)),
  );
  const measurementValues = new Map<ThrowMeasurementKey, number[]>();
  let totalCoverageSum = 0;
  let hadNullMeasurement = false;

  for (const key of referencedMeasurements) {
    const valid = throws
      .map((t) => t.measurements[key])
      .filter((v): v is number => typeof v === "number" && Number.isFinite(v));
    measurementValues.set(key, valid);
    const coverage = valid.length / throws.length;
    if (coverage < 1) hadNullMeasurement = true;
    totalCoverageSum += coverage;
  }

  const evidenceCoverage =
    referencedMeasurements.length > 0
      ? totalCoverageSum / referencedMeasurements.length
      : 1;

  interface FiredRuleCandidate {
    rule: AssessmentRule;
    ruleIndex: number;
    maxSeverityRank: number;
    effectiveRuleConfidence: number;
    emittedZones: FocusZone[];
    canSupplyNextAction: boolean;
  }

  const firedCandidates: FiredRuleCandidate[] = [];
  let suppressedByUnreachable = false;

  for (let ruleIndex = 0; ruleIndex < ruleSet.rules.length; ruleIndex += 1) {
    const rule = ruleSet.rules[ruleIndex];
    if (!rule.pitchIds.includes(pitchId)) continue;

    const values = measurementValues.get(rule.measurement) ?? [];
    // Safety Rule 2: If measurement is null across all throws, skip the rule.
    if (values.length === 0) continue;

    const meanValue =
      values.reduce((sum, current) => sum + current, 0) / values.length;
    if (!matchesCondition(meanValue, rule.when)) continue;

    // Safety Rule 1: An unreachable zone never gets technique advice.
    // If a rule's primary nextAction zone is unreachable, suppress that rule's advice.
    const primaryTargetUnreachable =
      rule.nextAction.zoneId !== null &&
      unreachableSet.has(rule.nextAction.zoneId);
    const textNamesUnreachable =
      mentionsUnreachableZone(rule.nextAction.summary, unreachableSet) ||
      mentionsUnreachableZone(rule.nextAction.detail, unreachableSet);

    if (primaryTargetUnreachable) {
      suppressedByUnreachable = true;
      continue;
    }

    const ruleMeasurementCoverage = values.length / throws.length;
    const confidenceScale =
      hadNullMeasurement
        ? Math.min(ruleMeasurementCoverage, 0.5 + 0.5 * evidenceCoverage)
        : 1;

    const reachableZones: FocusZone[] = [];
    for (const ruleZone of rule.zones) {
      if (unreachableSet.has(ruleZone.zoneId)) {
        suppressedByUnreachable = true;
        continue;
      }
      if (silentZoneSet.has(ruleZone.zoneId)) {
        continue;
      }
      const baseConf = resolveZoneBaseConfidence(rule, ruleZone);
      const zoneConf = clampConfidence(baseConf * confidenceScale);
      const reason = interpolateReason(
        ruleZone.reason ?? rule.reason,
        meanValue,
        rule.when,
      );
      reachableZones.push({
        zoneId: ruleZone.zoneId,
        severity: ruleZone.severity,
        reason,
        triggeringMeasurement: rule.measurement,
        confidence: zoneConf,
      });
    }

    if (reachableZones.length === 0 && rule.zones.length > 0) {
      suppressedByUnreachable = true;
      continue;
    }

    const maxSeverityRank = reachableZones.reduce(
      (max, z) => Math.max(max, SEVERITY_RANK[z.severity]),
      0,
    );

    firedCandidates.push({
      rule,
      ruleIndex,
      maxSeverityRank,
      effectiveRuleConfidence: clampConfidence(
        rule.confidence * confidenceScale,
      ),
      emittedZones: reachableZones,
      canSupplyNextAction: !textNamesUnreachable,
    });
  }

  if (firedCandidates.length === 0) {
    const baseFallbackConfidence = pitchRules[0]?.confidence ?? 0.4;
    const fallbackConfidence = hadNullMeasurement
      ? clampConfidence(baseFallbackConfidence * 0.4 * evidenceCoverage)
      : suppressedByUnreachable
        ? clampConfidence(baseFallbackConfidence * 0.5)
        : 0.25;

    const reasonKind = suppressedByUnreachable
      ? "unreachable"
      : hadNullMeasurement
        ? "null-measurement"
        : "no-finding";

    return {
      schemaVersion: "1.0.0",
      assessmentId,
      gripPlanId,
      throwIds,
      ruleVersion,
      classification: "not-grip",
      zones: [],
      nextAction: fallbackNotGripAction(pitchId, reasonKind),
      confidence: fallbackConfidence,
      unreachableZones: unreachable,
      consistency,
      prototypeAdvice,
      extensions: {},
    };
  }

  // Merge zones across firing rules: higher severity wins, then higher confidence, then rule order.
  const mergedZones: FocusZone[] = [];
  const zoneIndexById = new Map<ZoneId, number>();

  for (const candidate of firedCandidates) {
    for (const focusZone of candidate.emittedZones) {
      const existingIdx = zoneIndexById.get(focusZone.zoneId);
      if (existingIdx === undefined) {
        zoneIndexById.set(focusZone.zoneId, mergedZones.length);
        mergedZones.push(focusZone);
      } else {
        const existing = mergedZones[existingIdx];
        const newRank = SEVERITY_RANK[focusZone.severity];
        const oldRank = SEVERITY_RANK[existing.severity];
        if (
          newRank > oldRank ||
          (newRank === oldRank && focusZone.confidence > existing.confidence)
        ) {
          mergedZones[existingIdx] = focusZone;
        }
      }
    }
  }

  // Safety Rule 4: Exactly one next action.
  // Highest severity wins, then highest confidence, then rule order.
  const rankedForAction = [...firedCandidates].sort((a, b) => {
    if (b.maxSeverityRank !== a.maxSeverityRank) {
      return b.maxSeverityRank - a.maxSeverityRank;
    }
    if (b.effectiveRuleConfidence !== a.effectiveRuleConfidence) {
      return b.effectiveRuleConfidence - a.effectiveRuleConfidence;
    }
    return a.ruleIndex - b.ruleIndex;
  });

  const winningCandidate =
    rankedForAction.find((c) => c.canSupplyNextAction) ?? rankedForAction[0];

  const nextAction: NextAction = winningCandidate.canSupplyNextAction
    ? {
        zoneId: winningCandidate.rule.nextAction.zoneId,
        summary: winningCandidate.rule.nextAction.summary,
        detail: winningCandidate.rule.nextAction.detail,
        rewritten: false,
      }
    : fallbackNotGripAction(pitchId, "unreachable");

  const classification: AssessmentClassification =
    mergedZones.length === 0 || !winningCandidate.canSupplyNextAction
      ? "not-grip"
      : winningCandidate.rule.classification;

  // Overall confidence is the mean confidence of the highest-severity emitted zones
  // (e.g. wrist 0.6 and middle-pad 0.5 -> 0.55 for the Maya fixture), or the winning rule's confidence.
  let overallConfidence = winningCandidate.effectiveRuleConfidence;
  if (mergedZones.length > 0) {
    const topRank = mergedZones.reduce(
      (max, z) => Math.max(max, SEVERITY_RANK[z.severity]),
      0,
    );
    const topZones = mergedZones.filter(
      (z) => SEVERITY_RANK[z.severity] === topRank,
    );
    const meanTopConfidence =
      topZones.reduce((sum, z) => sum + z.confidence, 0) / topZones.length;
    overallConfidence = clampConfidence(meanTopConfidence);
  }

  return {
    schemaVersion: "1.0.0",
    assessmentId,
    gripPlanId,
    throwIds,
    ruleVersion,
    classification,
    zones: mergedZones,
    nextAction,
    confidence: overallConfidence,
    unreachableZones: unreachable,
    consistency,
    prototypeAdvice,
    extensions: {},
  };
}
