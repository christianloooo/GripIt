# Grip Feedback Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `sample-rules-1` and the AI paragraph writer with a deterministic engine that names one grip change per throw set, highlights the finger on the 3D hand, and states the number expected to move.

**Architecture:** Four pure modules in `shared/focus/`, each with one job, composed in a single direction with no cycles. Measurement is separated from judgement, targets are separated from responses, and selection is separated from copy. Rules are data rows, not control flow, so correcting a threshold or adding a pitch never touches engine logic.

**Tech Stack:** TypeScript, vitest, bundled to `focus-engine.js` by esbuild and run in JavaScriptCore on the phone. No network, no model, no new dependencies.

---

## Architecture

### Data flow

```
ThrowRecord[]            typed, sample, or photo-extracted. Source is irrelevant.
     |
     v
metrics.ts               pure arithmetic. No thresholds, no judgement.
     |  DerivedMetrics
     v
targets.ts               researched facts per pitch. No responses.
     |  PitchTarget
     v
gripRules.ts             data rows. Each: does this symptom apply, and how far off?
     |  Candidate[]
     v
gripFeedback.ts          gates, then ranks, then returns exactly one result.
     |  GripFeedback
     v
assess.ts                packs it into the existing FocusAssessment wire type.
     |
     v
nativeFocus.ts -> focus-engine.js -> Swift -> FocusAssessmentView + zone highlight
```

Dependencies point one way only. `metrics` knows nothing about targets, `targets`
know nothing about rules, `gripRules` knows nothing about precedence.

### Module responsibilities

| File | Owns | Must not |
| --- | --- | --- |
| `shared/focus/metrics.ts` | Turning throws into numbers: active spin, spin per mph, gyro/efficiency conversion, circular clock distance, medians | Know any threshold or any pitch |
| `shared/focus/targets.ts` | What each pitch should read, with a source string per entry | Know what to do when a target is missed |
| `shared/focus/gripRules.ts` | One row per symptom: which pitches, a predicate, the change copy, the zones, the expectation | Decide which row wins, or do arithmetic |
| `shared/focus/gripFeedback.ts` | Gates and precedence. Returns exactly one result | Contain any rule copy or any target number |

Four files, each small enough to hold in your head, each testable alone.

### Key design decisions

**Rules are data, not branches.** A rule is a value with an id, the pitches it
applies to, a predicate, and its copy. Adding the cutter later means appending
rows and a target entry. The engine does not grow.

**Predicates return a magnitude, not a boolean.** Each returns how far off target
the reading is, normalised as a fraction of the band width, or null when it does
not apply. Normalising is what makes "show the worst one" comparable across
different units, so axis hours and spin-per-mph can be ranked against each other.
Copy stays out of ranking entirely.

**Targets are separate from responses.** A target is a researched fact. A rule is
what we say about missing it. Correcting the slider ceiling, which today is
thirty points wrong, touches one target row and no rules. Both carry a source
string so a wrong number is traceable to where it came from.

**Gates run before ranking, in order.** Fit, then missing baseline, then release
drift, then ranked deviation. The fit gate matters most: `reach` is already on
every zone and ignored today, so the app can currently tell someone to move a
finger they cannot reach.

**Zones are the only coupling to the 3D model.** A result carries `ZoneId[]`. The
viewer already highlights a zone with a white outline, so phase one needs no
renderer work at all. A re-solved pose reads the same field later.

**Input source is invisible to the engine.** Everything starts from
`ThrowRecord[]`. Photo import, sample data and manual entry converge before this
point, which is why Carter's track and this one are independent.

### Interfaces

Signatures only. Bodies are implementation.

```ts
// metrics.ts
export interface DerivedMetrics {
  throwCount: number;
  velocityMph: number | null;
  totalSpinRpm: number | null;
  spinEfficiencyPercent: number | null;   // filled from gyro when absent
  activeSpinRpm: number | null;
  spinPerMph: number | null;
  spinDirectionClock: number | null;
  horizontalBreakInches: number | null;
  verticalBreakInches: number | null;
}

export function efficiencyFromGyro(gyroDegree: number): number;
export function clockHoursApart(a: number, b: number): number;   // circular
export function deriveMetrics(throws: readonly ThrowRecord[]): DerivedMetrics;
```

```ts
// targets.ts
export interface Range { min?: number; max?: number; }
export interface PitchTarget {
  pitchId: string;
  axisClock?: Range;              // decimal clock hours
  efficiencyPercent?: Range;
  horizontalBreakInches?: Range;
  verticalBreakInches?: Range;
  spinPerMph?: Range;
  source: string;
}
export const PITCH_TARGETS: Readonly<Record<string, PitchTarget>>;
```

```ts
// gripRules.ts
export interface Deviation { summary: string; magnitude: number; }  // 0 = on target
export interface GripRule {
  id: string;
  pitchIds: readonly string[];
  detect(m: DerivedMetrics, t: PitchTarget, baseline: DerivedMetrics | null): Deviation | null;
  change: string;                 // handInstructions wording
  zones: readonly ZoneId[];
  expect: string;
  source: string;
}
export const GRIP_RULES: readonly GripRule[];
export const GRIP_RULE_VERSION = "demo-rules-1";
```

```ts
// gripFeedback.ts
export type FeedbackKind = "change" | "fit" | "baseline" | "drift" | "on-target" | "no-data";
export interface GripFeedback {
  kind: FeedbackKind;
  measured: string;               // always present, pure arithmetic
  headline: string;
  change: string | null;
  expect: string | null;
  zones: ZoneId[];
  ruleId: string | null;
  ruleVersion: string;
  source: string | null;
}
export function gripFeedback(input: {
  pitchId: string;
  throws: readonly ThrowRecord[];
  zones: readonly InstructionZone[];
  baseline?: readonly ThrowRecord[];
}): GripFeedback;
```

### Staying unblocked by Carter

`horizontalBreakInches` and `verticalBreakInches` land in Carter's contract task.
`metrics.ts` reads them through a locally declared structural type that marks
both optional, so this track compiles and tests before his change merges and
lights up automatically after. No shared edit, no merge conflict.

### Attaching without touching Swift

`FocusAssessment` is the wire type Swift decodes, so changing its shape means
changing Swift. Phase one avoids that entirely:

- `nextAction.summary` takes the headline, `nextAction.detail` takes the measured
  line plus the change plus the expectation as prose. Both already render.
- `nextAction.zoneId` takes the primary zone. One Swift line in
  `FocusAssessmentView.onAppear` prefers it for the initial highlight.
- `extensions` carries the full structured `GripFeedback` for later, which
  existing decoders ignore.

Phase two promotes it to a first-class field once the shape has settled.

---

## File Structure

**Create**
- `shared/focus/metrics.ts` + `metrics.test.ts`
- `shared/focus/targets.ts` + `targets.test.ts`
- `shared/focus/gripRules.ts` + `gripRules.test.ts`
- `shared/focus/gripFeedback.ts` + `gripFeedback.test.ts`
- `shared/focus/demoFixtures.ts` — the three demo paths as shared fixtures

**Modify**
- `shared/focus/assess.ts` — delegate `nextAction` and `zones` to the new engine
- `shared/focus/rules.ts` — delete `SAMPLE_RULES_LIST`, keep `PITCH_INSTRUCTION_ZONES`
- `ios/GripIt/Training/FocusAssessmentView.swift` — highlight the named zone
- `ios/GripIt/Training/TrainingFlowModel.swift` — pass other pitches' sessions

**Delete**
- `shared/focus/coachPrompt.ts`, `shared/focus/askPrompt.ts` — already dead in
  production, referenced only by tests
- The coaching half of `shared/focus/interpretation.ts`; the question box keeps
  its own path

---

## Tasks

Each task is TDD: write the failing test, watch it fail, implement, watch it
pass, commit. Run `npx vitest run shared/focus/<file>.test.ts` for one file.

### Task 1: Pure measurement

**Files:** create `shared/focus/metrics.ts`, `shared/focus/metrics.test.ts`

- [ ] Test `efficiencyFromGyro`. Anchor on real data: `rapsodo1.webp` shows
      -18.2 degrees and 95.0 percent, so `efficiencyFromGyro(-18.2)` is 95.0 to
      one decimal. Negative and positive gyro give the same efficiency.
- [ ] Test `clockHoursApart` is circular. 12:30 against 11:30 is 1.0, not 11.0.
      1:56 against 12:15 is about 1.68. Never greater than 6.
- [ ] Test `deriveMetrics` on one throw and on three, that it takes medians, that
      active spin is total times efficiency over 100, that spin per mph is total
      over velocity, and that efficiency is filled from gyro when only gyro is
      present. Anchor active spin on `rapsodo1`: 1077 at 95 percent is 1023, the
      true spin the screenshot displays.
- [ ] Test every field is null, not NaN or zero, when its input is absent.
- [ ] Implement, pass, commit.

### Task 2: Targets

**Files:** create `shared/focus/targets.ts`, `shared/focus/targets.test.ts`

- [ ] Test all four pitches are present and every entry has a non-empty `source`.
- [ ] Test the slider ceiling is at most 35 percent, which is the correction to
      today's 65, and that the four-seam efficiency floor is at least 95.
- [ ] Test ranges are well formed: `min` is not above `max`.
- [ ] Implement, pass, commit.

### Task 3: Rule shape and four-seam rows

**Files:** create `shared/focus/gripRules.ts`, `shared/focus/gripRules.test.ts`

- [ ] Test rule ids are unique and every rule names at least one zone, a
      non-empty `change`, a non-empty `expect`, and a `source`.
- [ ] Test every `zones` entry is a real `ZoneId`.
- [ ] Test each four-seam rule fires on metrics that trip it and returns null on
      metrics that do not, one case each way per rule.
- [ ] Test magnitude is zero on target, rises as the reading moves away, and is
      comparable between two rules with different units.
- [ ] Implement the five four-seam rows, pass, commit.

### Task 4: Two-seam rows

**Files:** modify `shared/focus/gripRules.ts`, `gripRules.test.ts`

- [ ] Test each of the four two-seam rules fires and stays silent appropriately.
- [ ] Test the two-seam rules name index and middle, never the wrist.
- [ ] Implement, pass, commit.

### Task 5: Slider rows

**Files:** modify `shared/focus/gripRules.ts`, `gripRules.test.ts`

- [ ] Test the efficiency rule fires above the corrected ceiling and is silent at
      a genuine gyro slider reading.
- [ ] Test no slider rule asks the index finger to drive, since on a slider the
      index parks on leather and the middle finger works the seam.
- [ ] Implement, pass, commit.

### Task 6: Changeup rows and baseline

**Files:** modify `shared/focus/gripRules.ts`, `gripRules.test.ts`

- [ ] Test the separation rule needs a baseline and returns null without one.
- [ ] Test it fires when separation from the baseline fastball is under 8 mph and
      is silent when it is comfortably over.
- [ ] Test the changeup rules name middle, ring, index and palm, never the wrist.
- [ ] Implement, pass, commit.

### Task 7: Gates and precedence

**Files:** create `shared/focus/gripFeedback.ts`, `gripFeedback.test.ts`

- [ ] Test no throws returns `no-data` and names no zone.
- [ ] Test a rule whose named zone is `unreachable` is suppressed and the result
      is `fit`, not a technique instruction. Repeat for `strained`, which today
      is invisible to the engine and still receives advice.
- [ ] Test a changeup with no baseline returns `baseline`.
- [ ] Test release drift returns `drift` and names no finger.
- [ ] Test gate order: a throw that trips both a fit problem and a deviation
      returns `fit`.
- [ ] Test exactly one change is ever returned, and that the largest normalised
      deviation wins when several rules fire.
- [ ] Test ties break by table order, so identical input gives identical output.
- [ ] Test `measured` is populated in every outcome including `no-data`.
- [ ] Implement, pass, commit.

### Task 8: Demo fixtures end to end

**Files:** create `shared/focus/demoFixtures.ts`, modify `gripFeedback.test.ts`

- [ ] Encode `rapsodo2.webp`'s real readings as a fixture: 77.3 mph, 1642 rpm,
      axis 1:56, 93.8 percent, 13.8 inch vertical and 18.6 inch horizontal break.
- [ ] Encode the existing `sampleThrowSession()` readings as the second fixture.
- [ ] Test demo path one: that fixture as a four-seam names the thumb.
- [ ] Test demo path two: the same fixture as a two-seam names index and middle
      and cites seam purchase, a different rule from path one.
- [ ] Test demo path three: the sample session as a four-seam fires the seam
      orientation rule, a third distinct rule.
- [ ] Test the three paths return three different rule ids, which is the property
      that makes the demo worth showing.
- [ ] Commit.

### Task 9: Replace the old engine

**Files:** modify `shared/focus/assess.ts`, `shared/focus/rules.ts`, `shared/focus/assess.test.ts`

- [ ] Test `assess()` populates `nextAction` from the new engine and that
      `ruleVersion` reads `demo-rules-1`.
- [ ] Test `nextAction.zoneId` is the primary zone of the chosen change.
- [ ] Test the full structured result is present under `extensions` so nothing
      downstream has to change yet.
- [ ] Delete `SAMPLE_RULES_LIST` and keep `PITCH_INSTRUCTION_ZONES`, which is
      Step 2 content and unrelated to rules.
- [ ] Update existing `assess.test.ts` cases that assert the old copy.
- [ ] Run the whole web suite, pass, commit.

### Task 10: Remove the AI coaching path

**Files:** modify `shared/focus/interpretation.ts`, `api/coach.ts`; delete `shared/focus/coachPrompt.ts`, `shared/focus/askPrompt.ts`

- [ ] Confirm by search that `COACH_SYSTEM_PROMPT` and `ASK_SYSTEM_PROMPT` are
      referenced only by tests, then delete both files and their tests.
- [ ] Remove the coaching generation from `api/coach.ts`. The endpoint keeps
      returning the hand-fit explanation, which is a different job and still
      earns its call.
- [ ] Test `/api/coach` no longer calls the model for coaching text.
- [ ] Run the whole web suite, pass, commit.

### Task 11: Native engine and the highlight

**Files:** modify `ios/GripIt/Training/FocusAssessmentView.swift`, `ios/GripIt/Training/TrainingFlowModel.swift`

- [ ] Run `npm run ios:focus` to rebuild `focus-engine.js`. Without this the
      phone silently keeps the old rules.
- [ ] Add a Swift test that the native engine returns the expected rule for the
      `rapsodo2` fixture, proving the bundle actually rebuilt.
- [ ] Prefer `nextAction.zoneId` for the initial zone highlight in `onAppear`.
- [ ] Pass other pitches' sessions from `GripStudioSession` so a changeup can see
      a fastball baseline. The data is already in memory and simply not passed.
- [ ] Build for device, confirm it compiles, commit.

Note: `swift test` needs `--scratch-path /tmp/gripit-build`. The repo sits under
iCloud-synced Desktop, which stamps `com.apple.FinderInfo` on build products and
codesign refuses to sign them.

### Task 12: Strip the dead UI

**Files:** modify `ios/GripIt/Training/FocusAssessmentView.swift`

Do this only once Task 11 is green, or the feedback panel renders empty.

- [ ] Remove the coaching loading, retry and `connectionMessage` states.
- [ ] Remove the "Your throw data is ready. Retry coaching" fallback, which today
      shows nothing useful whenever model output is rejected.
- [ ] Keep the question box. That one stays AI.
- [ ] Build for device, commit.

---

## Verification

```sh
npm test                 # web and shared suites
npm run ios:focus        # REQUIRED after any shared/ change
cd ios/GripItScannerCore && swift test --scratch-path /tmp/gripit-build
```

Done means: three demo paths produce three different rules naming three
different finger groups, no model is called for coaching text, a strained or
unreachable contact never receives a technique instruction, and identical input
produces identical output.

## Not in this plan

The re-solved pose showing the suggested grip. It reads the same `zones` field
and is additive, so it is a separate plan once this one is green.

Perceptron extraction. Carter's track, and the engine cannot tell the difference.
