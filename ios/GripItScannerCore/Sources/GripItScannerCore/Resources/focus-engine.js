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
      10,
      true
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

  // shared/focus/metrics.ts
  function round(value, decimals) {
    const factor = 10 ** decimals;
    return Math.round(value * factor) / factor;
  }
  function isNumber(value) {
    return typeof value === "number" && Number.isFinite(value);
  }
  function median(values) {
    const present = values.filter(isNumber).sort((a, b) => a - b);
    if (!present.length) return null;
    const mid = Math.floor(present.length / 2);
    return present.length % 2 ? present[mid] : (present[mid - 1] + present[mid]) / 2;
  }
  function efficiencyFromGyro(gyroDegree) {
    return round(Math.cos(gyroDegree * Math.PI / 180) * 100, 1);
  }
  function clockHoursApart(a, b) {
    const diff = Math.abs(a - b) % 12;
    return Math.min(diff, 12 - diff);
  }
  function deriveMetrics(throws) {
    const column = (key) => throws.map((t) => t.measurements[key]);
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
    const activeSpin = totalSpin !== null && efficiency !== null ? totalSpin * efficiency / 100 : null;
    const spinPerMph = totalSpin !== null && velocity !== null && velocity > 0 ? totalSpin / velocity : null;
    const rounded = (value, decimals) => value === null ? null : round(value, decimals);
    return {
      throwCount: throws.length,
      velocityMph: rounded(velocity, 1),
      totalSpinRpm: rounded(totalSpin, 0),
      spinEfficiencyPercent: rounded(efficiency, 1),
      activeSpinRpm: rounded(activeSpin, 0),
      spinPerMph: rounded(spinPerMph, 1),
      spinDirectionClock: rounded(direction, 2),
      horizontalBreakInches: rounded(horizontal, 1),
      verticalBreakInches: rounded(vertical, 1)
    };
  }

  // shared/focus/gripRules.ts
  var GRIP_RULE_VERSION = "demo-rules-1";
  var SCALE = {
    axisHours: 1,
    efficiencyPoints: 5,
    spinPerMph: 2,
    breakInches: 4,
    separationMph: 2
  };
  function distanceOutside(value, range) {
    if (value === null || value === void 0 || !range) return 0;
    if (range.min !== void 0 && value < range.min) return range.min - value;
    if (range.max !== void 0 && value > range.max) return value - range.max;
    return 0;
  }
  function axisDistance(axis, range) {
    if (axis === null || !range) return 0;
    const ends = [range.min, range.max].filter(
      (end) => end !== void 0
    );
    if (!ends.length) return 0;
    const mid = (Math.min(...ends) + Math.max(...ends)) / 2;
    let unwrapped = axis;
    while (unwrapped < mid - 6) unwrapped += 12;
    while (unwrapped > mid + 6) unwrapped -= 12;
    if (distanceOutside(unwrapped, range) === 0) return 0;
    return Math.min(...ends.map((end) => clockHoursApart(axis, end)));
  }
  function clockText(clock) {
    const mod = clock % 12;
    const wrapped = mod < 1 ? mod + 12 : mod;
    let hours = Math.floor(wrapped);
    let minutes = Math.round((wrapped - hours) * 60);
    if (minutes === 60) {
      hours = hours === 12 ? 1 : hours + 1;
      minutes = 0;
    }
    return `${hours}:${String(minutes).padStart(2, "0")}`;
  }
  function deviation(summary, distance, scale) {
    return distance > 0 ? { summary, magnitude: distance / scale } : null;
  }
  var FOUR_SEAM = ["four-seam"];
  var TWO_SEAM = ["two-seam"];
  var SLIDER = ["slider"];
  var CHANGEUP = ["changeup"];
  function runShortfall(value, range) {
    if (value === null || !range) return 0;
    const ends = [range.min, range.max].filter(
      (end) => end !== void 0
    );
    if (!ends.length) return 0;
    const mid = (Math.min(...ends) + Math.max(...ends)) / 2;
    const nearZeroEnd = mid >= 0 ? { min: range.min } : { max: range.max };
    return distanceOutside(value, nearZeroEnd);
  }
  var RAPSODO_SOURCE = "Rapsodo, 'Understanding the Three Fastball Movement Profiles' and the fastball spin-rate/efficiency profile article";
  var PRP_SOURCE = "PRP Baseball published pitch-grading cues";
  var RAPSODO_SLIDER_SOURCE = "Rapsodo curveball/slider/changeup article: gyro sliders under 10 percent, topspin and sidespin sliders near 35 percent with 65 to 75 gyro degrees";
  var CHANGEUP_BASELINE_SOURCE = "A changeup has no absolute target, so both rules compare it to the same pitcher's own fastball in the same session";
  var GRIP_RULES = [
    {
      id: "four-seam-axis",
      pitchIds: FOUR_SEAM,
      reading: { metric: "spinDirectionClock", measurement: "spinDirectionClock", label: "Spin axis", target: "axisClock" },
      detect(m, t) {
        if (m.spinDirectionClock === null) return null;
        const miss = axisDistance(m.spinDirectionClock, t.axisClock);
        return deviation(
          `Spin axis reads ${clockText(m.spinDirectionClock)}, off the target clock range.`,
          miss,
          SCALE.axisHours
        );
      },
      change: "Set the thumb pad under the space between the index and middle fingers, on smooth leather.",
      zones: ["thumb-pad"],
      expect: "Axis moves toward 12 o'clock and spin efficiency rises.",
      source: `${RAPSODO_SOURCE} (axis target); ${PRP_SOURCE}; handInstructions.md (thumb approximately opposite the space between the two upper fingers, initially on smooth leather). Centring the thumb squares the hand behind the ball.`
    },
    {
      id: "four-seam-efficiency",
      pitchIds: FOUR_SEAM,
      reading: { metric: "spinEfficiencyPercent", measurement: "spinEfficiencyPercent", label: "Spin efficiency", unit: " percent", target: "efficiencyPercent", guard: "axis" },
      detect(m, t) {
        if (axisDistance(m.spinDirectionClock, t.axisClock) > 0) return null;
        const eff = m.spinEfficiencyPercent;
        if (eff === null) return null;
        return deviation(
          `Spin efficiency reads ${eff} percent, below target.`,
          distanceOutside(eff, t.efficiencyPercent),
          SCALE.efficiencyPoints
        );
      },
      change: "Rotate the ball so the stitching crosses underneath both pads rather than running along them.",
      zones: ["index-pad", "middle-pad"],
      expect: "Spin efficiency rises.",
      source: `${RAPSODO_SOURCE} (efficiency target); ${PRP_SOURCE}; handInstructions.md (pad across the raised stitching, seam crossing underneath).`
    },
    {
      id: "four-seam-purchase",
      pitchIds: FOUR_SEAM,
      reading: { metric: "spinPerMph", measurement: "totalSpinRpm", label: "Spin per mph", target: "spinPerMph" },
      detect(m, t) {
        const spm = m.spinPerMph;
        if (spm === null) return null;
        return deviation(
          `Spin per mph reads ${spm}, below target. The pads may be on smooth leather.`,
          distanceOutside(spm, t.spinPerMph),
          SCALE.spinPerMph
        );
      },
      change: "Move both pads onto the raised stitching.",
      zones: ["index-pad", "middle-pad"],
      expect: "Total spin rises.",
      source: `Spin per mph target from PitchLogic via targets.ts; ${PRP_SOURCE}; handInstructions.md (pad across the raised stitching).`
    },
    {
      id: "four-seam-cut",
      pitchIds: FOUR_SEAM,
      reading: { metric: "horizontalBreakInches", measurement: "horizontalBreakInches", label: "Horizontal break", unit: " inches", target: "horizontalBreakInches", guard: "axis" },
      detect(m, t) {
        if (axisDistance(m.spinDirectionClock, t.axisClock) > 0) return null;
        const h = m.horizontalBreakInches;
        if (h === null) return null;
        return deviation(
          `Horizontal break reads ${h} inches. A four-seam should run near straight.`,
          distanceOutside(h, t.horizontalBreakInches),
          SCALE.breakInches
        );
      },
      change: "Bring the index and middle fingers closer, to a comfortable, small separation.",
      zones: ["index-pad", "middle-pad"],
      expect: "Sideways movement drops and vertical break rises.",
      source: `${RAPSODO_SOURCE} (backspin profile has near-zero horizontal break); ${PRP_SOURCE}; handInstructions.md (a comfortable, small separation between the fingers).`
    },
    {
      id: "four-seam-buried",
      pitchIds: FOUR_SEAM,
      reading: { metric: "verticalBreakInches", measurement: "verticalBreakInches", label: "Vertical break", unit: " inches", target: "verticalBreakInches", guard: "axis-and-efficiency", requiresMinimum: true },
      detect(m, t) {
        if (axisDistance(m.spinDirectionClock, t.axisClock) > 0) return null;
        const eff = m.spinEfficiencyPercent;
        if (distanceOutside(eff, t.efficiencyPercent) > 0) return null;
        const v = m.verticalBreakInches;
        if (v === null || (t.verticalBreakInches?.min ?? -Infinity) <= v) {
          return null;
        }
        return deviation(
          `Vertical break reads ${v} inches, below target. The ball may be buried in the palm.`,
          distanceOutside(v, t.verticalBreakInches),
          SCALE.breakInches
        );
      },
      change: "Hold the ball between the upper pads and thumb, without deliberately burying it in your palm.",
      zones: ["palm"],
      expect: "Vertical break rises.",
      source: `${RAPSODO_SOURCE} (vertical break target); ${PRP_SOURCE}; handInstructions.md (without deliberately burying it in your palm).`
    },
    {
      id: "two-seam-axis",
      pitchIds: TWO_SEAM,
      reading: { metric: "spinDirectionClock", measurement: "spinDirectionClock", label: "Spin axis", target: "axisClock" },
      detect(m, t) {
        if (m.spinDirectionClock === null) return null;
        const miss = axisDistance(m.spinDirectionClock, t.axisClock);
        return deviation(
          `Spin axis reads ${clockText(m.spinDirectionClock)}, off the target clock range. The ball may still be set like a four-seamer.`,
          miss,
          SCALE.axisHours
        );
      },
      change: "Rotate the ball so the two close stretches of stitching run from your wrist toward your fingertips.",
      zones: ["index-pad", "middle-pad"],
      expect: "Axis moves into the arm-side range and the ball starts running.",
      source: `${RAPSODO_SOURCE} (axis target); ${PRP_SOURCE}; handInstructions.md (rotate the ball until the seams run approximately from the wrist toward the fingertips).`
    },
    {
      id: "two-seam-run",
      pitchIds: TWO_SEAM,
      reading: { metric: "horizontalBreakInches", measurement: "horizontalBreakInches", label: "Horizontal break", unit: " inches", target: "horizontalBreakInches", guard: "axis" },
      detect(m, t) {
        if (axisDistance(m.spinDirectionClock, t.axisClock) > 0) return null;
        const h = m.horizontalBreakInches;
        if (h === null) return null;
        return deviation(
          `Horizontal break reads ${h} inches, below target. The pitch is not running.`,
          runShortfall(h, t.horizontalBreakInches),
          SCALE.breakInches
        );
      },
      change: "Set the index pad along the thumb-side seam and the middle pad along the other seam. Rotate the ball slightly until both pads engage stitching.",
      zones: ["index-pad", "middle-pad"],
      expect: "Horizontal run increases.",
      source: `${RAPSODO_SOURCE} (horizontal break target); ${PRP_SOURCE}; handInstructions.md (index pad on the thumb-side seam, middle pad on the other seam, each following the stitching).`
    },
    {
      id: "two-seam-efficiency",
      pitchIds: TWO_SEAM,
      reading: { metric: "spinEfficiencyPercent", measurement: "spinEfficiencyPercent", label: "Spin efficiency", unit: " percent", target: "efficiencyPercent", guard: "axis" },
      detect(m, t) {
        if (axisDistance(m.spinDirectionClock, t.axisClock) > 0) return null;
        const eff = m.spinEfficiencyPercent;
        if (eff === null) return null;
        return deviation(
          `Spin efficiency reads ${eff} percent, below target. The hand may have slipped to the side of the ball.`,
          distanceOutside(eff, t.efficiencyPercent),
          SCALE.efficiencyPoints
        );
      },
      change: "Bring the thumb back under the two upper fingers, supporting the underside with its fleshy pad.",
      zones: ["thumb-pad"],
      expect: "Spin efficiency rises.",
      source: `${RAPSODO_SOURCE} (75 to 100 percent efficiency, wide because different efficiencies suit different spin directions, arm slots and grips); ${PRP_SOURCE}; handInstructions.md (thumb supports the underside, approximately opposite the two upper fingers).`
    },
    {
      id: "two-seam-purchase",
      pitchIds: TWO_SEAM,
      reading: { metric: "spinPerMph", measurement: "totalSpinRpm", label: "Spin per mph", target: "spinPerMph" },
      detect(m, t) {
        const spm = m.spinPerMph;
        if (spm === null) return null;
        return deviation(
          `Spin per mph reads ${spm}, below target. The pads may be on smooth leather.`,
          distanceOutside(spm, t.spinPerMph),
          SCALE.spinPerMph
        );
      },
      change: "Set both pads onto their seams so each follows its own stitching.",
      zones: ["index-pad", "middle-pad"],
      expect: "Total spin rises.",
      source: `Spin per mph target from PitchLogic via targets.ts; ${PRP_SOURCE}; handInstructions.md (each upper finger follows its own seam).`
    },
    // Only one slider rule. "Fingers too far apart" cannot be observed from ball
    // flight or a static scan. "Not enough sweep" has no target because the app
    // does not know whether a sweeper or a gyro slider was intended, and
    // targetFor("slider") carries no break range. Spin per mph has no slider
    // target either, so there is no purchase rule.
    {
      id: "slider-efficiency",
      pitchIds: SLIDER,
      reading: { metric: "spinEfficiencyPercent", measurement: "spinEfficiencyPercent", label: "Spin efficiency", unit: " percent", target: "efficiencyPercent" },
      detect(m, t) {
        const eff = m.spinEfficiencyPercent;
        if (eff === null) return null;
        return deviation(
          `Spin efficiency reads ${eff} percent, above the slider range. The index finger may be driving the ball like a fastball.`,
          distanceOutside(eff, t.efficiencyPercent),
          SCALE.efficiencyPoints
        );
      },
      // The index is named only to relax it. On a slider it parks on leather.
      change: "Let the index pad rest on the smooth leather beside the middle finger, and let the middle finger alone work the pinky-side seam.",
      zones: ["index-pad"],
      expect: "Spin efficiency drops and gyro degree rises.",
      source: `${RAPSODO_SLIDER_SOURCE} (efficiency ceiling); ${PRP_SOURCE}; handInstructions.md (middle pad on the pinky-side seam, index pad resting on the adjacent smooth leather).`
    },
    // Two changeup rules, not the four the design table lists.
    //
    // "No fade" is cut. It needs to know whether the changeup is breaking
    // arm-side, and targetFor("changeup") carries no horizontalBreakInches
    // range to measure that against. detect() is not given handedness, and the
    // changeup target is identical for both hands because it has nothing to
    // mirror, so the arguments carry no way to tell arm-side from glove-side.
    // The only ways to get it are to invent a break target or to assume a sign,
    // and a sign assumption passes every right-handed test while inverting the
    // advice for every left-hander. Restore this row when a sourced changeup
    // break range exists; it will then mirror like the two-seam one does.
    //
    // "Loop squeezed rigid" is cut. Its trigger is grip pressure, which ball
    // flight and a static hand scan cannot observe. Same class as the cut
    // slider "fingers too far apart" row.
    {
      id: "changeup-separation",
      pitchIds: CHANGEUP,
      reading: { metric: "velocityMph", measurement: "velocityMph", label: "Changeup velocity", unit: " mph", target: "velocitySeparationMph", baseline: "velocityMph" },
      detect(m, t, baseline) {
        if (!baseline) return null;
        const velocity = m.velocityMph;
        const fastball = baseline.velocityMph;
        if (velocity === null || fastball === null) return null;
        const separation = Math.round((fastball - velocity) * 10) / 10;
        return deviation(
          `Changeup velocity reads ${velocity} mph, ${separation} off the fastball's ${fastball}. It is too close to read as a different pitch.`,
          distanceOutside(separation, t.velocitySeparationMph),
          SCALE.separationMph
        );
      },
      change: "Let the ball settle comfortably into the hand while maintaining middle- and ring-finger contact.",
      zones: ["palm"],
      expect: "Velocity drops.",
      source: `${CHANGEUP_BASELINE_SOURCE}. Separation floor from targets.ts, where it is recorded as a coaching convention rather than a measured target; ${PRP_SOURCE}; handInstructions.md (let the ball settle comfortably into the hand while maintaining middle- and ring-finger contact).`
    },
    {
      id: "changeup-spin",
      pitchIds: CHANGEUP,
      reading: { metric: "spinPerMph", measurement: "totalSpinRpm", label: "Spin per mph", baseline: "spinPerMph" },
      // No target argument is read: a changeup has no absolute spin target.
      detect(m, _t, baseline) {
        if (!baseline) return null;
        const spm = m.spinPerMph;
        const fastball = baseline.spinPerMph;
        if (spm === null || fastball === null) return null;
        return deviation(
          `Spin per mph reads ${spm}, above the fastball's ${fastball}. The changeup is still spinning like a fastball.`,
          distanceOutside(spm, { max: fastball }),
          SCALE.spinPerMph
        );
      },
      change: "Wrap the index finger's inner middle/distal surface around the thumb-side centre of the ball, close to the equator, opposite the pinky. Keep the tip softly curled rather than pointing away.",
      zones: ["index-pad"],
      expect: "Spin drops.",
      source: `${CHANGEUP_BASELINE_SOURCE}, so the comparison point is the baseline's own spin per mph and no threshold is written here; ${PRP_SOURCE}; handInstructions.md (inner middle/distal surface around the thumb-side centre, opposite the pinky; tip softly curled).`
    }
  ];
  function hasReading(value) {
    return typeof value === "number" && Number.isFinite(value);
  }
  function hasRange(range) {
    return !!range && (hasReading(range.min) || hasReading(range.max));
  }
  function ruleReadingAvailable(rule, m, t, baseline) {
    const reading = rule.reading;
    const value = m[reading.metric];
    if (!hasReading(value)) return false;
    if (reading.target && !hasRange(t[reading.target])) return false;
    if (reading.requiresMinimum && (!reading.target || !hasReading(t[reading.target]?.min))) return false;
    if (reading.baseline && (!baseline || !hasReading(baseline[reading.baseline]))) return false;
    if (reading.guard) {
      if (!hasReading(m.spinDirectionClock) || !hasRange(t.axisClock) || axisDistance(m.spinDirectionClock, t.axisClock) > 0) return false;
      if (reading.guard === "axis-and-efficiency" && (!hasReading(m.spinEfficiencyPercent) || !hasRange(t.efficiencyPercent) || distanceOutside(m.spinEfficiencyPercent, t.efficiencyPercent) > 0)) return false;
    }
    return true;
  }
  function checkedRuleReading(rule, m, t, baseline) {
    if (!ruleReadingAvailable(rule, m, t, baseline)) return null;
    if (rule.detect(m, t, baseline) !== null) return null;
    const reading = rule.reading;
    const value = m[reading.metric];
    const formatted = reading.metric === "spinDirectionClock" ? clockText(value) : value;
    const comparison = reading.baseline ? ` against the fastball's ${baseline[reading.baseline]}${reading.unit ?? ""}` : "";
    return {
      reason: `${reading.label} reads ${formatted}${reading.unit ?? ""}${comparison}. This check found no deviation.`,
      triggeringMeasurement: reading.measurement
    };
  }

  // shared/focus/targets.ts
  var PITCH_TARGETS = {
    "four-seam": {
      pitchId: "four-seam",
      axisClock: { min: 12, max: 12.5 },
      efficiencyPercent: { min: 95, max: 100 },
      verticalBreakInches: { min: 15, max: 20 },
      horizontalBreakInches: { min: -3, max: 3 },
      spinPerMph: { min: 22 },
      source: "Rapsodo, 'Understanding the Three Fastball Movement Profiles' and the fastball spin-rate/efficiency profile article (backspin profile). Spin per mph from PitchLogic: average near 24, barely changes with velocity."
    },
    "two-seam": {
      pitchId: "two-seam",
      axisClock: { min: 1, max: 2 },
      // Wide on purpose. The source says different efficiencies suit different
      // spin directions, arm slots and grips.
      efficiencyPercent: { min: 75, max: 100 },
      horizontalBreakInches: { min: 10, max: 20 },
      spinPerMph: { min: 22 },
      source: "Rapsodo fastball spin-rate/efficiency article: 75 to 100 percent efficiency, wide because different efficiencies suit different spin directions, arm slots and grips."
    },
    slider: {
      pitchId: "slider",
      // No minimum: a gyro slider runs under 10 percent and that is correct.
      // The value this replaces was 65 percent, which the same article puts at
      // a sweeping curveball, so the old rule was about 30 points wrong.
      efficiencyPercent: { max: 35 },
      source: "Rapsodo curveball/slider/changeup article: gyro sliders under 10 percent, topspin and sidespin sliders near 35 percent with 65 to 75 gyro degrees."
    },
    changeup: {
      pitchId: "changeup",
      // No absolute ranges on purpose. A changeup is judged only against the
      // same pitcher's own fastball, which gripRules.ts handles with a
      // baseline. The one number here is a gap from that fastball, not a
      // reading the pitch should hit.
      velocitySeparationMph: { min: 8 },
      source: "Rapsodo curveball/slider/changeup article: its own changeup examples run 71.6 to 100 percent efficiency, so no single efficiency target is defensible. The 8 mph velocity separation is a coaching convention, not a measured target: changeups are conventionally thrown 8 to 10 mph off the same pitcher's fastball, and 8 is the bottom of that convention as stated in the Task 6 plan row. Treat it as the least defensible number in this table."
    }
  };
  function mirrorRange(range, fn) {
    const mirrored = {};
    if (range.max !== void 0) mirrored.min = fn(range.max);
    if (range.min !== void 0) mirrored.max = fn(range.min);
    return mirrored;
  }
  function mirrorClock(clock) {
    const mirrored = 24 - clock;
    return mirrored >= 13 ? mirrored - 12 : mirrored;
  }
  function targetFor(pitchId, handedness) {
    const target = PITCH_TARGETS[pitchId];
    if (!target) return null;
    if (handedness === "right") return target;
    const mirrored = { ...target };
    if (target.axisClock) {
      mirrored.axisClock = mirrorRange(target.axisClock, mirrorClock);
    }
    if (target.horizontalBreakInches) {
      mirrored.horizontalBreakInches = mirrorRange(
        target.horizontalBreakInches,
        (inches) => -inches
      );
    }
    return mirrored;
  }

  // shared/focus/gripFeedback.ts
  var RELEASE_HEIGHT_DRIFT_FEET = 0.5;
  var MIN_THROWS_FOR_DRIFT = 3;
  var PITCH_IDS_NEEDING_BASELINE = ["changeup"];
  function roundTo(value, decimals) {
    const factor = 10 ** decimals;
    return Math.round((value + Number.EPSILON) * factor) / factor;
  }
  function measuredText(m) {
    if (m.throwCount === 0) return "No throws recorded for this pitch yet.";
    const parts = [];
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
  function candidatesFor(pitchId, metrics, handedness, baseline) {
    const target = targetFor(pitchId, handedness);
    if (!target) return [];
    const found = [];
    for (const rule of GRIP_RULES) {
      if (!rule.pitchIds.includes(pitchId)) continue;
      const deviation2 = rule.detect(metrics, target, baseline);
      if (!deviation2) continue;
      if (!Number.isFinite(deviation2.magnitude) || deviation2.magnitude <= 0) {
        continue;
      }
      found.push({
        rule,
        summary: deviation2.summary,
        magnitude: deviation2.magnitude
      });
    }
    return found;
  }
  function unfittableZones(candidates, zones) {
    const reachById = new Map(zones.map((zone) => [zone.zoneId, zone.reach]));
    const problems = [];
    for (const candidate of candidates) {
      for (const zoneId of candidate.rule.zones) {
        const reach = reachById.get(zoneId);
        if (reach !== "unreachable" && reach !== "strained") continue;
        if (!problems.includes(zoneId)) problems.push(zoneId);
      }
    }
    return problems;
  }
  function titleFor(zoneId, zones) {
    return zones.find((zone) => zone.zoneId === zoneId)?.title ?? zoneId;
  }
  function releaseHeightSpreadFeet(throws) {
    if (throws.length < MIN_THROWS_FOR_DRIFT) return null;
    const heights = throws.map((t) => t.measurements.releaseHeightFeet).filter((v) => typeof v === "number" && Number.isFinite(v));
    if (heights.length < MIN_THROWS_FOR_DRIFT) return null;
    return roundTo(Math.max(...heights) - Math.min(...heights), 2);
  }
  function result(partial) {
    return {
      change: null,
      expect: null,
      zones: [],
      ruleId: null,
      source: null,
      ruleVersion: GRIP_RULE_VERSION,
      ...partial
    };
  }
  function gripFeedback(input) {
    const { pitchId, throws, zones, baseline, handedness = "right" } = input;
    const metrics = deriveMetrics(throws);
    const measured = measuredText(metrics);
    const baselineMetrics = baseline && baseline.length ? deriveMetrics(baseline) : null;
    if (metrics.throwCount === 0) {
      return result({
        kind: "no-data",
        measured,
        headline: "Record a few throws of this pitch to get a change to try."
      });
    }
    const candidates = candidatesFor(
      pitchId,
      metrics,
      handedness,
      baselineMetrics
    );
    const unfittable = unfittableZones(candidates, zones);
    if (unfittable.length) {
      const names = unfittable.map((zoneId) => titleFor(zoneId, zones));
      return result({
        kind: "fit",
        measured,
        headline: `This grip does not fit your hand yet: ${names.join(" and ")} cannot make the contact this pitch asks for. Work on the fit before changing technique.`,
        zones: unfittable
      });
    }
    if (PITCH_IDS_NEEDING_BASELINE.includes(pitchId) && !baselineMetrics) {
      return result({
        kind: "baseline",
        measured,
        headline: "This pitch is read against your own fastball, so throw some fastballs in the same session before it can be judged."
      });
    }
    const spread = releaseHeightSpreadFeet(throws);
    if (spread !== null && spread > RELEASE_HEIGHT_DRIFT_FEET) {
      return result({
        kind: "drift",
        measured,
        headline: `Your release height moved ${spread} feet across these throws. That is an arm-slot problem rather than a grip problem, so settle the release point first.`
      });
    }
    let best = null;
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
        source: best.rule.source
      });
    }
    const hasRules = GRIP_RULES.some((rule) => rule.pitchIds.includes(pitchId));
    return result({
      kind: "on-target",
      measured,
      headline: hasRules ? "Every reading for this pitch is inside its target range. Keep throwing it." : "No grip rules are written for this pitch yet, so there is nothing to flag."
    });
  }
  var UNSCORED_CONFIDENCE = 0.5;
  var SEVERITY_ORDER = { green: 0, yellow: 1, red: 2 };
  function gripFocusZones(input, feedback) {
    if (feedback.kind !== "change" && feedback.kind !== "on-target") return [];
    const target = targetFor(input.pitchId, input.handedness ?? "right");
    if (!target) return [];
    const metrics = deriveMetrics(input.throws);
    const baseline = input.baseline?.length ? deriveMetrics(input.baseline) : null;
    const candidates = candidatesFor(input.pitchId, metrics, input.handedness ?? "right", baseline);
    const byRule = new Map(candidates.map((candidate) => [candidate.rule.id, candidate]));
    const found = /* @__PURE__ */ new Map();
    for (const rule of GRIP_RULES) {
      if (!rule.pitchIds.includes(input.pitchId)) continue;
      if (!ruleReadingAvailable(rule, metrics, target, baseline)) continue;
      const candidate = byRule.get(rule.id);
      const clean = candidate ? null : checkedRuleReading(rule, metrics, target, baseline);
      if (!candidate && !clean) continue;
      const severity = candidate ? rule.id === feedback.ruleId ? "red" : "yellow" : "green";
      const measurement = rule.reading.measurement === "spinEfficiencyPercent" && !input.throws.some((t) => Number.isFinite(t.measurements.spinEfficiencyPercent) && t.measurements.spinEfficiencyPercent !== null) ? "gyroDegree" : rule.reading.measurement;
      for (const zoneId of rule.zones) {
        const previous = found.get(zoneId);
        if (previous && SEVERITY_ORDER[previous.severity] >= SEVERITY_ORDER[severity]) continue;
        found.set(zoneId, {
          zoneId,
          severity,
          reason: candidate?.summary ?? clean.reason,
          triggeringMeasurement: measurement,
          confidence: UNSCORED_CONFIDENCE
        });
      }
    }
    return [...found.values()];
  }

  // shared/focus/assess.ts
  var VELOCITY_SPREAD_MPH = 3;
  var TOTAL_SPIN_SPREAD_RPM = 200;
  var MIN_THROWS_FOR_CONSISTENCY = 3;
  function roundNumber(value, decimals = 2) {
    const factor = 10 ** decimals;
    return Math.round((value + Number.EPSILON) * factor) / factor;
  }
  function computeConsistency(throws) {
    if (throws.length < MIN_THROWS_FOR_CONSISTENCY) return null;
    const velocities = throws.map((t) => t.measurements.velocityMph).filter((v) => typeof v === "number" && Number.isFinite(v));
    const spins = throws.map((t) => t.measurements.totalSpinRpm).filter((v) => typeof v === "number" && Number.isFinite(v));
    const velocitySpreadMph = velocities.length >= 2 ? roundNumber(Math.max(...velocities) - Math.min(...velocities), 2) : 0;
    const totalSpinSpreadRpm = spins.length >= 2 ? roundNumber(Math.max(...spins) - Math.min(...spins), 2) : 0;
    return {
      throwCount: throws.length,
      velocitySpreadMph,
      totalSpinSpreadRpm,
      inconsistent: velocitySpreadMph > VELOCITY_SPREAD_MPH || totalSpinSpreadRpm > TOTAL_SPIN_SPREAD_RPM
    };
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
  function detailFrom(feedback) {
    return [feedback.measured, feedback.change, feedback.expect].filter((part) => part !== null && part.trim() !== "").join(" ");
  }
  function assess(input) {
    const { pitchId, throws, zones, baseline, handedness } = input;
    const feedback = gripFeedback({
      pitchId,
      throws,
      zones,
      baseline,
      handedness
    });
    const nextAction = {
      zoneId: feedback.zones[0] ?? null,
      summary: feedback.headline,
      detail: detailFrom(feedback),
      rewritten: false
    };
    const classification = feedback.kind === "change" ? "grip-focus" : "not-grip";
    return {
      schemaVersion: "1.0.0",
      assessmentId: deriveAssessmentId(pitchId, throws, input.assessmentId),
      gripPlanId: deriveGripPlanId(pitchId, throws, input.gripPlanId),
      throwIds: throws.map((t) => t.throwId),
      ruleVersion: feedback.ruleVersion,
      classification,
      zones: gripFocusZones(input, feedback),
      nextAction,
      confidence: feedback.kind === "no-data" ? 0 : UNSCORED_CONFIDENCE,
      unreachableZones: unreachableZones(zones),
      consistency: computeConsistency(throws),
      // True while the rule set has not been reviewed by a pitching coach.
      prototypeAdvice: true,
      extensions: { gripFeedback: feedback }
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
    return JSON.stringify(assess(JSON.parse(json)));
  }
  return __toCommonJS(nativeFocus_exports);
})();
