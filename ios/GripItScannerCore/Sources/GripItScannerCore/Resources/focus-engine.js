"use strict";
var GripItFocus = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // shared/nativeFocus.ts
  var nativeFocus_exports = {};
  __export(nativeFocus_exports, {
    assessJSON: () => assessJSON,
    recordsJSON: () => recordsJSON,
    validateJSON: () => validateJSON
  });

  // shared/throwEntry.ts
  function parseClock(value) {
    const match = /^(0?[1-9]|1[0-2]):([0-5]\d)$/.exec(value.trim());
    return match ? Number(match[1]) + Number(match[2]) / 60 : null;
  }
  function completeSpinMeasurements(spinEfficiencyPercent, gyroDegree) {
    if (spinEfficiencyPercent === null && gyroDegree !== null) {
      spinEfficiencyPercent = Math.cos(gyroDegree * Math.PI / 180) * 100;
    } else if (gyroDegree === null && spinEfficiencyPercent !== null) {
      gyroDegree = Math.acos(spinEfficiencyPercent / 100) * 180 / Math.PI;
    }
    return { spinEfficiencyPercent, gyroDegree };
  }
  function validateThrow(row) {
    const errors = {};
    const number = (field, label, min, max, optional = false) => {
      const raw = row[field].trim();
      if (!raw) {
        if (!optional) errors[field] = `Enter ${label}.`;
        return null;
      }
      const value = Number(raw);
      if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(raw) || !Number.isFinite(value)) {
        errors[field] = "Enter a valid number.";
      } else if (value < min || max !== void 0 && value > max) {
        errors[field] = max === void 0 ? `Use ${min} or more.` : `Use ${min} to ${max}. Check the units.`;
      }
      return value;
    };
    const velocityMph = number("velocityMph", "velocity", 1, 120);
    const totalSpinRpm = number("totalSpinRpm", "total spin", 0, 5e3);
    const releaseHeightFeet = number(
      "releaseHeightFeet",
      "release height",
      0,
      10
    );
    const enteredSpinEfficiency = number(
      "spinEfficiencyPercent",
      "spin efficiency",
      0,
      100,
      true
    );
    const enteredGyroDegree = number("gyroDegree", "gyro degree", -90, 90, true);
    const horizontalBreakInches = number(
      "horizontalBreakInches",
      "horizontal break",
      -30,
      30,
      true
    );
    const verticalBreakInches = number(
      "verticalBreakInches",
      "vertical break",
      -30,
      30,
      true
    );
    const rapsodoScore = number(
      "rapsodoScore",
      "Rapsodo score",
      0,
      void 0,
      true
    );
    const spinDirectionClock = parseClock(row.spinDirectionClock);
    if (spinDirectionClock === null)
      errors.spinDirectionClock = "Use clock time, e.g. 12:30 (1:00 to 12:59).";
    const { spinEfficiencyPercent, gyroDegree } = completeSpinMeasurements(
      enteredSpinEfficiency,
      enteredGyroDegree
    );
    return {
      errors,
      measurements: Object.keys(errors).length ? null : {
        velocityMph,
        totalSpinRpm,
        spinDirectionClock,
        spinEfficiencyPercent,
        gyroDegree,
        horizontalBreakInches,
        verticalBreakInches,
        releaseHeightFeet,
        rapsodoScore
      }
    };
  }
  function makeThrowRecords(session, pitchId, options = {}) {
    if (!pitchId.trim() || !session.rows.length)
      throw new Error("A pitch and at least one throw are required.");
    const recordedAt = options.recordedAt ?? (/* @__PURE__ */ new Date()).toISOString();
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
        extensions: options.handProfileId ? { "gripit.throwEntry": { handProfileId: options.handProfileId } } : {}
      };
    });
  }

  // shared/contracts/zones.ts
  function unreachableZones(zones) {
    return zones.filter((zone) => zone.reach === "unreachable").map((z) => z.zoneId);
  }

  // shared/focus/rules.ts
  var SAMPLE_RULES_LIST = [
    {
      id: "four-seam-low-spin-efficiency",
      pitchIds: ["four-seam"],
      measurement: "spinEfficiencyPercent",
      when: { below: 80, target: 90 },
      zones: [
        { zoneId: "wrist", severity: "red", confidence: 0.6 },
        { zoneId: "middle-pad", severity: "red", confidence: 0.5 },
        { zoneId: "index-pad", severity: "yellow", confidence: 0.4 },
        { zoneId: "thumb-pad", severity: "yellow", confidence: 0.4 }
      ],
      reason: "Spin efficiency {value}% is below the {target}% four-seam target",
      nextAction: {
        zoneId: "wrist",
        summary: "Stay behind the ball",
        detail: "Keep the wrist firm and push through the back of the ball instead of around its side."
      },
      confidence: 0.6,
      classification: "grip-focus"
    },
    {
      id: "four-seam-moderate-spin-efficiency",
      pitchIds: ["four-seam"],
      measurement: "spinEfficiencyPercent",
      when: { atLeast: 80, below: 90, target: 90 },
      zones: [
        { zoneId: "wrist", severity: "yellow", confidence: 0.5 },
        { zoneId: "middle-pad", severity: "yellow", confidence: 0.5 },
        { zoneId: "index-pad", severity: "yellow", confidence: 0.45 },
        { zoneId: "thumb-pad", severity: "yellow", confidence: 0.4 }
      ],
      reason: "Spin efficiency {value}% is below the {target}% four-seam target",
      nextAction: {
        zoneId: "middle-pad",
        summary: "Finish squarely through the horseshoe seam",
        detail: "Keep both upper finger pads even across the stitching and drive straight through release."
      },
      confidence: 0.5,
      classification: "grip-focus"
    },
    {
      id: "four-seam-target-spin-efficiency",
      pitchIds: ["four-seam"],
      measurement: "spinEfficiencyPercent",
      when: { atLeast: 90, target: 90 },
      zones: [
        { zoneId: "wrist", severity: "green", confidence: 0.6 },
        { zoneId: "middle-pad", severity: "green", confidence: 0.6 },
        { zoneId: "index-pad", severity: "green", confidence: 0.55 },
        { zoneId: "thumb-pad", severity: "green", confidence: 0.5 }
      ],
      reason: "Spin efficiency {value}% meets the {target}% four-seam target",
      nextAction: {
        zoneId: "wrist",
        summary: "Repeat this four-seam release",
        detail: "Spin efficiency meets the 90% target. Keep the same wrist position and finger pressure on the next throw."
      },
      confidence: 0.6,
      classification: "grip-focus"
    },
    {
      id: "two-seam-low-spin-efficiency",
      pitchIds: ["two-seam"],
      measurement: "spinEfficiencyPercent",
      when: { below: 65, target: 75 },
      zones: [
        { zoneId: "wrist", severity: "yellow", confidence: 0.4 },
        { zoneId: "index-pad", severity: "yellow", confidence: 0.35 },
        { zoneId: "middle-pad", severity: "yellow", confidence: 0.35 }
      ],
      reason: "Spin efficiency {value}% is below the conservative {threshold}% two-seam floor",
      nextAction: {
        zoneId: "index-pad",
        summary: "Keep pads aligned along the two-seam pair",
        detail: "Rest the index and middle pads along their seams and stay behind the ball before adding extra movement."
      },
      confidence: 0.4,
      classification: "grip-focus"
    },
    {
      id: "slider-excess-spin-efficiency",
      pitchIds: ["slider"],
      measurement: "spinEfficiencyPercent",
      when: { above: 65, target: 65 },
      zones: [
        { zoneId: "middle-pad", severity: "yellow", confidence: 0.35 },
        { zoneId: "wrist", severity: "yellow", confidence: 0.35 }
      ],
      reason: "Spin efficiency {value}% is above the {threshold}% slider ceiling where sliders aim for lower efficiency",
      nextAction: {
        zoneId: "middle-pad",
        summary: "Work the pinky-side seam",
        detail: "A slider wants lower spin efficiency than a fastball. Apply firmer purchase along the pinky-side seam with the middle finger."
      },
      confidence: 0.35,
      classification: "grip-focus"
    }
  ];
  var SAMPLE_RULE_SET = {
    version: "sample-rules-1",
    ruleVersion: "sample-rules-1",
    prototypeAdvice: true,
    releaseHeightDriftFeet: 0.5,
    velocitySpreadThresholdMph: 3,
    totalSpinSpreadThresholdRpm: 200,
    rules: SAMPLE_RULES_LIST
  };
  var DEFAULT_RULE_SET = SAMPLE_RULE_SET;
  var PITCH_INSTRUCTION_ZONES = {
    "four-seam": [
      {
        zoneId: "index-pad",
        title: "Index finger",
        instruction: "Pad across the raised stitching, seam crossing underneath",
        pressure: "medium",
        role: "drive",
        reach: "comfortable",
        placement: {
          surface: "pad",
          region: "top",
          seam: "across",
          seamOffsetMm: 0,
          opposes: []
        }
      },
      {
        zoneId: "middle-pad",
        title: "Middle finger",
        instruction: "Beside the index, pad also crossing the stitching",
        pressure: "firm",
        role: "drive",
        reach: "comfortable",
        placement: {
          surface: "pad",
          region: "top",
          seam: "across",
          seamOffsetMm: 0,
          opposes: []
        }
      },
      {
        zoneId: "ring-side",
        title: "Ring finger",
        instruction: "Side of the finger curled against the ball for light support",
        pressure: "light",
        role: "support",
        reach: "comfortable",
        placement: {
          surface: "side",
          region: "pinky-side",
          seam: "off",
          seamOffsetMm: null,
          opposes: []
        }
      },
      {
        zoneId: "pinky",
        title: "Pinky",
        instruction: "Relaxed beside the ring finger, clear of the ball",
        pressure: "none",
        role: "clear",
        reach: "comfortable",
        placement: {
          surface: "none",
          region: "off-ball",
          seam: "none",
          seamOffsetMm: null,
          opposes: []
        }
      },
      {
        zoneId: "thumb-pad",
        title: "Thumb",
        instruction: "Fleshy pad underneath, on smooth leather",
        pressure: "light",
        role: "support",
        reach: "comfortable",
        placement: {
          surface: "pad",
          region: "underside",
          seam: "off",
          seamOffsetMm: null,
          opposes: ["index-pad", "middle-pad"]
        }
      },
      {
        zoneId: "palm",
        title: "Palm",
        instruction: "Do not bury the ball. Leave a small gap",
        pressure: "none",
        role: "clear",
        reach: "comfortable",
        placement: null
      },
      {
        zoneId: "wrist",
        title: "Wrist",
        instruction: "Stay behind the ball",
        pressure: "firm",
        role: "drive",
        reach: "comfortable",
        placement: null
      }
    ],
    "two-seam": [
      {
        zoneId: "index-pad",
        title: "Index finger",
        instruction: "Pad along the thumb-side seam, following its direction",
        pressure: "medium",
        role: "drive",
        reach: "comfortable",
        placement: {
          surface: "pad",
          region: "top",
          seam: "along",
          seamOffsetMm: 0,
          opposes: []
        }
      },
      {
        zoneId: "middle-pad",
        title: "Middle finger",
        instruction: "Pad along the other seam, toward the pinky side",
        pressure: "medium",
        role: "drive",
        reach: "comfortable",
        placement: {
          surface: "pad",
          region: "top",
          seam: "along",
          seamOffsetMm: 0,
          opposes: []
        }
      },
      {
        zoneId: "ring-side",
        title: "Ring finger",
        instruction: "Curled lightly against the pinky-side surface",
        pressure: "light",
        role: "support",
        reach: "comfortable",
        placement: {
          surface: "side",
          region: "pinky-side",
          seam: "off",
          seamOffsetMm: null,
          opposes: []
        }
      },
      {
        zoneId: "pinky",
        title: "Pinky",
        instruction: "Relaxed beside the ring finger, off the ball",
        pressure: "none",
        role: "clear",
        reach: "comfortable",
        placement: {
          surface: "none",
          region: "off-ball",
          seam: "none",
          seamOffsetMm: null,
          opposes: []
        }
      },
      {
        zoneId: "thumb-pad",
        title: "Thumb",
        instruction: "Fleshy pad underneath, opposite the two upper fingers",
        pressure: "light",
        role: "support",
        reach: "comfortable",
        placement: {
          surface: "pad",
          region: "underside",
          seam: "off",
          seamOffsetMm: null,
          opposes: ["index-pad", "middle-pad"]
        }
      },
      {
        zoneId: "palm",
        title: "Palm",
        instruction: "Similar depth to the four-seam. Do not bury the ball",
        pressure: "none",
        role: "clear",
        reach: "comfortable",
        placement: null
      },
      {
        zoneId: "wrist",
        title: "Wrist",
        instruction: "Stay behind the ball",
        pressure: "firm",
        role: "drive",
        reach: "comfortable",
        placement: null
      }
    ],
    slider: [
      {
        zoneId: "index-pad",
        title: "Index finger",
        instruction: "Rests on smooth leather beside the middle finger, stabilising",
        pressure: "light",
        role: "support",
        reach: "comfortable",
        placement: {
          surface: "pad",
          region: "top",
          seam: "beside",
          seamOffsetMm: null,
          opposes: []
        }
      },
      {
        zoneId: "middle-pad",
        title: "Middle finger",
        instruction: "Pad along the pinky-side seam with definite purchase",
        pressure: "firm",
        role: "drive",
        reach: "comfortable",
        placement: {
          surface: "pad",
          region: "top",
          seam: "along",
          seamOffsetMm: 0,
          opposes: []
        }
      },
      {
        zoneId: "ring-side",
        title: "Ring finger",
        instruction: "Curled against the surface below the middle finger",
        pressure: "light",
        role: "support",
        reach: "comfortable",
        placement: {
          surface: "side",
          region: "pinky-side",
          seam: "off",
          seamOffsetMm: null,
          opposes: []
        }
      },
      {
        zoneId: "pinky",
        title: "Pinky",
        instruction: "Relaxed beside the ring finger, clear of the ball",
        pressure: "none",
        role: "clear",
        reach: "comfortable",
        placement: {
          surface: "none",
          region: "off-ball",
          seam: "none",
          seamOffsetMm: null,
          opposes: []
        }
      },
      {
        zoneId: "thumb-pad",
        title: "Thumb",
        instruction: "Underneath and opposite, slightly off centre, no hard pinch",
        pressure: "light",
        role: "support",
        reach: "comfortable",
        placement: {
          surface: "pad",
          region: "underside",
          seam: "off",
          seamOffsetMm: null,
          opposes: ["middle-pad"]
        }
      },
      {
        zoneId: "wrist",
        title: "Wrist",
        instruction: "Release decides whether this behaves like a slider",
        pressure: "firm",
        role: "drive",
        reach: "comfortable",
        placement: null
      }
    ],
    changeup: [
      {
        zoneId: "index-pad",
        title: "Index finger",
        instruction: "Curled around the thumb-side surface, forming a loop with the thumb",
        pressure: "light",
        role: "support",
        reach: "comfortable",
        placement: {
          surface: "curl",
          region: "thumb-side",
          seam: "off",
          seamOffsetMm: null,
          opposes: ["thumb-pad"]
        }
      },
      {
        zoneId: "middle-pad",
        title: "Middle finger",
        instruction: "Pad along the thumb-side seam",
        pressure: "medium",
        role: "drive",
        reach: "comfortable",
        placement: {
          surface: "pad",
          region: "top",
          seam: "along",
          seamOffsetMm: 0,
          opposes: []
        }
      },
      {
        zoneId: "ring-side",
        title: "Ring finger",
        instruction: "Pad along the pinky-side seam. A principal contact here",
        pressure: "medium",
        role: "drive",
        reach: "comfortable",
        placement: {
          surface: "pad",
          region: "top",
          seam: "along",
          seamOffsetMm: 0,
          opposes: []
        }
      },
      {
        zoneId: "pinky",
        title: "Pinky",
        instruction: "Wrapped lightly around the far side to stabilise",
        pressure: "light",
        role: "support",
        reach: "comfortable",
        placement: {
          surface: "curl",
          region: "pinky-side",
          seam: "off",
          seamOffsetMm: null,
          opposes: []
        }
      },
      {
        zoneId: "thumb-pad",
        title: "Thumb",
        instruction: "Wrapped around the lower thumb-side surface, closing the loop",
        pressure: "light",
        role: "support",
        reach: "comfortable",
        placement: {
          surface: "pad",
          region: "thumb-side",
          seam: "off",
          seamOffsetMm: null,
          opposes: ["index-pad"]
        }
      },
      {
        zoneId: "palm",
        title: "Palm",
        instruction: "Let the ball settle comfortably into the hand",
        pressure: "light",
        role: "support",
        reach: "comfortable",
        placement: null
      }
    ]
  };
  var FOUR_SEAM_INSTRUCTION_ZONES = PITCH_INSTRUCTION_ZONES["four-seam"];

  // shared/focus/assess.ts
  var SEVERITY_RANK = {
    green: 1,
    yellow: 2,
    red: 3
  };
  var DEFAULT_RELEASE_HEIGHT_DRIFT_FEET = 0.5;
  var DEFAULT_VELOCITY_SPREAD_MPH = 3;
  var DEFAULT_TOTAL_SPIN_SPREAD_RPM = 200;
  function roundNumber(value, decimals = 2) {
    const factor = 10 ** decimals;
    return Math.round((value + Number.EPSILON) * factor) / factor;
  }
  function clampConfidence(value) {
    if (!Number.isFinite(value)) return 0;
    return roundNumber(Math.min(1, Math.max(0, value)), 2);
  }
  function formatMetricValue(value) {
    return Number.isInteger(value) ? String(value) : String(roundNumber(value, 1));
  }
  function primaryThreshold(when) {
    return when.target ?? when.below ?? when.atLeast ?? when.above ?? when.atMost;
  }
  function interpolateReason(template, value, when) {
    const formattedValue = formatMetricValue(value);
    const thresholdBound = when.target ?? when.below ?? when.atLeast ?? when.above ?? when.atMost;
    const targetBound = primaryThreshold(when);
    return template.replaceAll("{value}", formattedValue).replaceAll(
      "{threshold}",
      thresholdBound !== void 0 ? formatMetricValue(thresholdBound) : ""
    ).replaceAll(
      "{target}",
      targetBound !== void 0 ? formatMetricValue(targetBound) : ""
    );
  }
  function matchesCondition(value, when) {
    const hasBound = when.below !== void 0 || when.atLeast !== void 0 || when.above !== void 0 || when.atMost !== void 0;
    if (!hasBound || !Number.isFinite(value)) return false;
    if (when.below !== void 0 && !(value < when.below)) return false;
    if (when.atLeast !== void 0 && !(value >= when.atLeast)) return false;
    if (when.above !== void 0 && !(value > when.above)) return false;
    if (when.atMost !== void 0 && !(value <= when.atMost)) return false;
    return true;
  }
  function resolveZoneBaseConfidence(rule, ruleZone) {
    if (typeof ruleZone.confidence === "number" && Number.isFinite(ruleZone.confidence)) {
      return ruleZone.confidence;
    }
    if (ruleZone.severity === "red") {
      return ruleZone.zoneId === rule.nextAction.zoneId ? rule.confidence : roundNumber(Math.max(0, rule.confidence - 0.1));
    }
    if (ruleZone.severity === "yellow") {
      return roundNumber(Math.max(0, rule.confidence - 0.2));
    }
    return rule.confidence;
  }
  function mentionsUnreachableZone(text, unreachableSet) {
    const lowered = text.toLowerCase();
    for (const zoneId of unreachableSet) {
      if (lowered.includes(zoneId) || lowered.includes(zoneId.replace("-", " "))) {
        return true;
      }
    }
    return false;
  }
  function computeConsistency(throws, ruleSet) {
    if (throws.length < 3) return null;
    const velocities = throws.map((t) => t.measurements.velocityMph).filter((v) => typeof v === "number" && Number.isFinite(v));
    const spins = throws.map((t) => t.measurements.totalSpinRpm).filter((v) => typeof v === "number" && Number.isFinite(v));
    const velocitySpreadMph = velocities.length >= 2 ? roundNumber(Math.max(...velocities) - Math.min(...velocities), 2) : 0;
    const totalSpinSpreadRpm = spins.length >= 2 ? roundNumber(Math.max(...spins) - Math.min(...spins), 2) : 0;
    const velocityLimit = ruleSet.velocitySpreadThresholdMph ?? DEFAULT_VELOCITY_SPREAD_MPH;
    const spinLimit = ruleSet.totalSpinSpreadThresholdRpm ?? DEFAULT_TOTAL_SPIN_SPREAD_RPM;
    return {
      throwCount: throws.length,
      velocitySpreadMph,
      totalSpinSpreadRpm,
      inconsistent: velocitySpreadMph > velocityLimit || totalSpinSpreadRpm > spinLimit
    };
  }
  function isReleaseHeightDrifting(throws, ruleSet) {
    if (throws.length < 3) return false;
    const heights = throws.map((t) => t.measurements.releaseHeightFeet).filter((v) => typeof v === "number" && Number.isFinite(v));
    if (heights.length < 3) return false;
    const spread = roundNumber(Math.max(...heights) - Math.min(...heights), 2);
    const threshold = ruleSet.releaseHeightDriftFeet ?? DEFAULT_RELEASE_HEIGHT_DRIFT_FEET;
    return spread > threshold;
  }
  function deriveGripPlanId(pitchId, throws, explicitId) {
    if (explicitId && explicitId.trim()) return explicitId;
    const isSample = throws.length === 0 || throws.some(
      (t) => t.source === "sample" || t.throwId.startsWith("sample-")
    );
    return `${isSample ? "sample-" : ""}${pitchId}-average-right`;
  }
  function deriveAssessmentId(pitchId, throws, explicitId) {
    if (explicitId && explicitId.trim()) return explicitId;
    if (throws.length === 1 && throws[0].throwId === "sample-throw-1") {
      return "sample-assessment-1";
    }
    const isSample = throws.length > 0 && throws.every(
      (t) => t.source === "sample" || t.throwId.startsWith("sample-")
    );
    const ids = throws.map((t) => t.throwId).join("-");
    return `${isSample ? "sample-" : ""}assessment-${pitchId}${ids ? `-${ids}` : ""}`;
  }
  function fallbackNotGripAction(pitchId, reason) {
    if (reason === "release-drift") {
      return {
        zoneId: null,
        summary: "Steady your release point",
        detail: "Release height drifted across this session, which points to arm slot and timing rather than finger placement.",
        rewritten: false
      };
    }
    if (reason === "unreachable") {
      return {
        zoneId: null,
        summary: "Adjust grip for hand fit",
        detail: "This hand cannot reach every required contact for this grip. Adjust the grip fit before changing release technique.",
        rewritten: false
      };
    }
    if (reason === "null-measurement") {
      return {
        zoneId: null,
        summary: "Record spin efficiency on the next throw",
        detail: "The measurement needed to evaluate this grip was not provided, so no finger adjustment is suggested yet.",
        rewritten: false
      };
    }
    if (pitchId === "changeup") {
      return {
        zoneId: null,
        summary: "Compare against your fastball",
        detail: "Changeup evaluation needs fastball velocity from the same session to judge separation, so no grip change is suggested from changeup throws alone.",
        rewritten: false
      };
    }
    if (pitchId === "slider") {
      return {
        zoneId: null,
        summary: "Keep working the slider release",
        detail: "Slider spin metrics are within the expected low-efficiency range, so no grip adjustment is flagged.",
        rewritten: false
      };
    }
    return {
      zoneId: null,
      summary: "Keep the current grip",
      detail: "Available throw numbers do not point to a grip adjustment on this pitch.",
      rewritten: false
    };
  }
  function assess(input) {
    const { pitchId, throws, zones, ruleSet } = input;
    const ruleVersion = ruleSet.ruleVersion?.trim() || ruleSet.version?.trim() || "sample-rules-1";
    const prototypeAdvice = ruleSet.prototypeAdvice ?? true;
    const throwIds = throws.map((t) => t.throwId);
    const gripPlanId = deriveGripPlanId(pitchId, throws, input.gripPlanId);
    const assessmentId = deriveAssessmentId(pitchId, throws, input.assessmentId);
    const unreachable = unreachableZones(zones);
    const unreachableSet = new Set(unreachable);
    const silentZoneSet = new Set(
      zones.filter((z) => z.instruction.trim() === "").map((z) => z.zoneId)
    );
    const consistency = computeConsistency(throws, ruleSet);
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
        extensions: {}
      };
    }
    const pitchRules = ruleSet.rules.filter(
      (rule) => rule.pitchIds.includes(pitchId)
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
        extensions: {}
      };
    }
    const referencedMeasurements = Array.from(
      new Set(pitchRules.map((rule) => rule.measurement))
    );
    const measurementValues = /* @__PURE__ */ new Map();
    let totalCoverageSum = 0;
    let hadNullMeasurement = false;
    for (const key of referencedMeasurements) {
      const valid = throws.map((t) => t.measurements[key]).filter((v) => typeof v === "number" && Number.isFinite(v));
      measurementValues.set(key, valid);
      const coverage = valid.length / throws.length;
      if (coverage < 1) hadNullMeasurement = true;
      totalCoverageSum += coverage;
    }
    const evidenceCoverage = referencedMeasurements.length > 0 ? totalCoverageSum / referencedMeasurements.length : 1;
    const firedCandidates = [];
    let suppressedByUnreachable = false;
    for (let ruleIndex = 0; ruleIndex < ruleSet.rules.length; ruleIndex += 1) {
      const rule = ruleSet.rules[ruleIndex];
      if (!rule.pitchIds.includes(pitchId)) continue;
      const values = measurementValues.get(rule.measurement) ?? [];
      if (values.length === 0) continue;
      const meanValue = values.reduce((sum, current) => sum + current, 0) / values.length;
      if (!matchesCondition(meanValue, rule.when)) continue;
      const primaryTargetUnreachable = rule.nextAction.zoneId !== null && unreachableSet.has(rule.nextAction.zoneId);
      const textNamesUnreachable = mentionsUnreachableZone(rule.nextAction.summary, unreachableSet) || mentionsUnreachableZone(rule.nextAction.detail, unreachableSet);
      if (primaryTargetUnreachable) {
        suppressedByUnreachable = true;
        continue;
      }
      const ruleMeasurementCoverage = values.length / throws.length;
      const confidenceScale = hadNullMeasurement ? Math.min(ruleMeasurementCoverage, 0.5 + 0.5 * evidenceCoverage) : 1;
      const reachableZones = [];
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
          rule.when
        );
        reachableZones.push({
          zoneId: ruleZone.zoneId,
          severity: ruleZone.severity,
          reason,
          triggeringMeasurement: rule.measurement,
          confidence: zoneConf
        });
      }
      if (reachableZones.length === 0 && rule.zones.length > 0) {
        suppressedByUnreachable = true;
        continue;
      }
      const maxSeverityRank = reachableZones.reduce(
        (max, z) => Math.max(max, SEVERITY_RANK[z.severity]),
        0
      );
      firedCandidates.push({
        rule,
        ruleIndex,
        maxSeverityRank,
        effectiveRuleConfidence: clampConfidence(
          rule.confidence * confidenceScale
        ),
        emittedZones: reachableZones,
        canSupplyNextAction: !textNamesUnreachable
      });
    }
    if (firedCandidates.length === 0) {
      const baseFallbackConfidence = pitchRules[0]?.confidence ?? 0.4;
      const fallbackConfidence = hadNullMeasurement ? clampConfidence(baseFallbackConfidence * 0.4 * evidenceCoverage) : suppressedByUnreachable ? clampConfidence(baseFallbackConfidence * 0.5) : 0.25;
      const reasonKind = suppressedByUnreachable ? "unreachable" : hadNullMeasurement ? "null-measurement" : "no-finding";
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
        extensions: {}
      };
    }
    const mergedZones = [];
    const zoneIndexById = /* @__PURE__ */ new Map();
    for (const candidate of firedCandidates) {
      for (const focusZone of candidate.emittedZones) {
        const existingIdx = zoneIndexById.get(focusZone.zoneId);
        if (existingIdx === void 0) {
          zoneIndexById.set(focusZone.zoneId, mergedZones.length);
          mergedZones.push(focusZone);
        } else {
          const existing = mergedZones[existingIdx];
          const newRank = SEVERITY_RANK[focusZone.severity];
          const oldRank = SEVERITY_RANK[existing.severity];
          if (newRank > oldRank || newRank === oldRank && focusZone.confidence > existing.confidence) {
            mergedZones[existingIdx] = focusZone;
          }
        }
      }
    }
    const rankedForAction = [...firedCandidates].sort((a, b) => {
      if (b.maxSeverityRank !== a.maxSeverityRank) {
        return b.maxSeverityRank - a.maxSeverityRank;
      }
      if (b.effectiveRuleConfidence !== a.effectiveRuleConfidence) {
        return b.effectiveRuleConfidence - a.effectiveRuleConfidence;
      }
      return a.ruleIndex - b.ruleIndex;
    });
    const winningCandidate = rankedForAction.find((c) => c.canSupplyNextAction) ?? rankedForAction[0];
    const nextAction = winningCandidate.canSupplyNextAction ? {
      zoneId: winningCandidate.rule.nextAction.zoneId,
      summary: winningCandidate.rule.nextAction.summary,
      detail: winningCandidate.rule.nextAction.detail,
      rewritten: false
    } : fallbackNotGripAction(pitchId, "unreachable");
    const classification = mergedZones.length === 0 || !winningCandidate.canSupplyNextAction ? "not-grip" : winningCandidate.rule.classification;
    let overallConfidence = winningCandidate.effectiveRuleConfidence;
    if (mergedZones.length > 0) {
      const topRank = mergedZones.reduce(
        (max, z) => Math.max(max, SEVERITY_RANK[z.severity]),
        0
      );
      const topZones = mergedZones.filter(
        (z) => SEVERITY_RANK[z.severity] === topRank
      );
      const meanTopConfidence = topZones.reduce((sum, z) => sum + z.confidence, 0) / topZones.length;
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
      extensions: {}
    };
  }

  // shared/nativeFocus.ts
  function validateJSON(json) {
    return JSON.stringify(validateThrow(JSON.parse(json)));
  }
  function recordsJSON(json) {
    const input = JSON.parse(json);
    return JSON.stringify(makeThrowRecords(input.session, input.pitchId, input.options));
  }
  function assessJSON(json) {
    return JSON.stringify(assess({ ...JSON.parse(json), ruleSet: DEFAULT_RULE_SET }));
  }
  return __toCommonJS(nativeFocus_exports);
})();
