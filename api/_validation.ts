import { z } from "zod";
import { ZONE_IDS } from "../shared/contracts/zones";
import type { CoachRequestBody } from "./coach";
import type { FitInput } from "../shared/focus/fitPrompt";

const text = z.string().min(1).max(2000);
const confidence = z.number().min(0).max(1);
const zoneId = z.enum(ZONE_IDS);
const assessment = z.object({
  schemaVersion: z.literal("1.0.0"),
  assessmentId: text,
  gripPlanId: text,
  ruleVersion: text,
  throwIds: z.array(text).min(1).max(200),
  classification: z.enum(["grip-focus", "not-grip"]),
  confidence,
  zones: z
    .array(
      z.object({
        zoneId,
        severity: z.enum(["green", "yellow", "red"]),
        reason: text,
        confidence,
        triggeringMeasurement: text,
      }),
    )
    .max(7),
  nextAction: z.object({
    zoneId: zoneId.nullable(),
    summary: text,
    detail: text,
    rewritten: z.boolean(),
  }),
  unreachableZones: z.array(zoneId).max(7),
  prototypeAdvice: z.boolean(),
  consistency: z
    .object({
      throwCount: z.number().int().min(3).max(200),
      velocitySpreadMph: z.number().nonnegative(),
      totalSpinSpreadRpm: z.number().nonnegative(),
      inconsistent: z.boolean(),
    })
    .nullable(),
});
const finger = z.object({
  segmentsMm: z.array(z.number().positive().max(200)).max(3),
  diameterMm: z.number().positive().max(100).nullable(),
});
const profile = z.object({
  profileId: text,
  handedness: z.enum(["left", "right"]),
  measurements: z.object({
    palm: z.object({
      widthMm: z.number().positive().max(300).nullable(),
      lengthMm: z.number().positive().max(300).nullable(),
      thicknessMm: z.number().positive().max(200).nullable(),
    }),
    fingers: z.object({
      index: finger,
      middle: finger,
      ring: finger,
      pinky: finger,
      thumb: finger,
    }),
  }),
});
const plan = z.object({
  gripPlanId: text,
  handProfileId: text,
  pitchId: z.enum(["four-seam", "two-seam", "slider", "changeup"]),
  instructionZones: z
    .array(
      z.object({
        zoneId,
        instruction: text,
        pressure: z.enum(["none", "light", "medium", "firm"]),
        role: z.enum(["drive", "support", "clear"]),
        reach: z.enum(["comfortable", "strained", "unreachable"]),
      }),
    )
    .max(7),
  fit: z.object({ confidence: confidence.nullable() }),
});
const throwRecord = z.object({
  schemaVersion: z.literal("1.0.0"),
  throwId: text,
  sessionId: text,
  pitchId: z.enum(["four-seam", "two-seam", "slider", "changeup"]),
  recordedAt: text,
  source: z.enum(["manual", "sample"]),
  measurements: z
    .object({
      velocityMph: z.number().min(1).max(120),
      totalSpinRpm: z.number().min(0).max(5000),
      spinDirectionClock: z.number().min(1).lt(13),
      spinEfficiencyPercent: z.number().min(0).max(100).nullable(),
      gyroDegree: z.number().min(-90).max(90).nullable(),
      releaseHeightFeet: z.number().min(0).max(10),
      rapsodoScore: z.number().min(0).nullable(),
    })
    .refine(
      (m) => (m.gyroDegree === null) !== (m.spinEfficiencyPercent === null),
    ),
});
const coach = z.object({
  assessment,
  profile: profile.optional(),
  plan: plan.optional(),
  throws: z.array(throwRecord).min(1).max(200).optional(),
});

export function isCoachRequest(value: unknown): value is CoachRequestBody {
  const parsed = coach.safeParse(value);
  if (!parsed.success) return false;
  const body = parsed.data;
  if (
    body.throws &&
    (body.throws.some(
      (t) =>
        !body.assessment.throwIds.includes(t.throwId) ||
        t.pitchId !== body.throws![0].pitchId ||
        (body.plan && t.pitchId !== body.plan.pitchId),
    ) ||
      new Set(body.throws.map((t) => t.throwId)).size !== body.throws.length ||
      body.throws.length !== body.assessment.throwIds.length)
  )
    return false;
  if (!body.profile && !body.plan) return true;
  return (
    !!body.profile &&
    !!body.plan &&
    body.profile.profileId === body.plan.handProfileId &&
    body.assessment.gripPlanId === body.plan.gripPlanId
  );
}

export function isAskRequest(
  value: unknown,
): value is FitInput & { question: string } {
  return (
    isCoachRequest(value) &&
    !!value.profile &&
    !!value.plan &&
    z.object({ question: z.string().trim().min(3).max(300) }).safeParse(value)
      .success
  );
}
