# GripIt grip-feedback engine — handoff

**Tasks 1 through 10 are done.** Only Tasks 11 and 12 remain, and both need Xcode and a
physical device, so they run on the owner's Mac.

## Apply the work

Nine commits exist only as the patches beside this file. `origin/jared/feedback-rules`
is still at `9b9f179`.

```sh
cd <your gripit clone>            # NOT your home folder
git fetch origin jared/feedback-rules
git checkout jared/feedback-rules # lands on 9b9f179
git am 0001-*.patch 0002-*.patch 0003-*.patch 0004-*.patch 0005-*.patch \
       0006-*.patch 0007-*.patch 0008-*.patch 0009-*.patch
npm install
npm test                          # expect 207 passed
npx tsc -b                        # expect 0 errors
```

If zsh says `no matches found`, the patches are not where you pointed it. Use full
filenames rather than a glob.

| Patch | Commit | What |
| --- | --- | --- |
| 0001 | `587a0d9` | Task 6: changeup separation + spin rules |
| 0002 | `ce955fd` | Task 7: `gripFeedback.ts`, gates and precedence |
| 0003 | `2c1f1a9` | Guard `four-seam-cut` on the spin axis (not in the plan) |
| 0004 | `6e7c41f` | Task 8: `demoFixtures.ts` + three end-to-end demo paths |
| 0005 | `eacce45` | Render a clock just past 12 as `12:mm`, not `0:mm` |
| 0006 | `e7a7d8e` | Fix stale `assess.test.ts` fixture (typecheck) |
| 0007 | `80bb17c` | Task 9: engine behind `assess()`, rebuilt native bundle |
| 0008 | `c588d77` | Fix stale `interpretation.test.ts` fixture (typecheck) |
| 0009 | `d5d891d` | Task 10: stop calling a model to write the coaching sentence |

## State

```
148 tests  shared/focus/
207 tests  full web suite
  0 errors  npx tsc -b
  npm run build passes
```

`shared/focus/`: `metrics.ts`, `targets.ts`, `gripRules.ts` (12 rules), `gripFeedback.ts`,
`demoFixtures.ts`, `assess.ts`. `coachPrompt.ts` deleted, `askPrompt.ts` trimmed to the
one guard the question box still needs.

**The phone now runs the real engine.** Before `80bb17c`, `shared/nativeFocus.ts` reached
only the old `DEFAULT_RULE_SET`, so `gripRules.ts` was unreachable from the bundle entry
point and every rule written in Tasks 1 to 8 was invisible to the device. Verified after:

```
grep -c demo-rules-1     focus-engine.js  ->  1   (was 0)
grep -c four-seam-axis   focus-engine.js  ->  1   (was 0)
grep -c sample-rules-1   focus-engine.js  ->  0   (was 3)
```

## The three demo paths, as the engine answers them

| Path | Input | ruleId | zones |
| --- | --- | --- | --- |
| One | rapsodo2 as four-seam | `four-seam-axis` | `thumb-pad` |
| Two | rapsodo2 as two-seam | `two-seam-purchase` | `index-pad` + `middle-pad` |
| Three | sample session as four-seam | `four-seam-cut` | `index-pad` + `middle-pad` |

Three distinct rule ids, which is the property that makes the demo worth showing. Paths
one and two match the design exactly. Path three is demoing an accident — see Carter item 2.

---

# Remaining: Tasks 11 and 12, on the Mac

Full detail in `docs/superpowers/plans/2026-10-18-grip-feedback-rules.md`.

**Task 11 — native engine and the highlight.** `npm run ios:focus` is already run and the
rebuilt bundle is committed in `80bb17c`, so the Swift test proving the bundle rebuilt
should pass immediately. Prefer `nextAction.zoneId` for the initial zone highlight in
`FocusAssessmentView.onAppear`. Pass other pitches' sessions from `GripStudioSession` so a
changeup can see a fastball baseline — `AssessInput.baseline` now exists and is wired
through to the engine; the data is already in memory and simply not passed.

**Task 12 — strip the dead UI.** Do this only once Task 11 is green, or the feedback panel
renders empty. Keep the question box; that one stays AI.

`swift test` needs `--scratch-path /tmp/gripit-build`. The repo sits under iCloud-synced
Desktop, which stamps `com.apple.FinderInfo` on build products and codesign refuses to
sign them.

**Transitional state you will see on device before Task 12 lands:**
`FocusAssessmentView.swift:99` gates the coaching panel on `coaching?.rewritten == true`,
and `rewritten` is now permanently `false`. So the phone shows the "Your throw data is
ready. Retry coaching…" fallback until Task 12 deletes it. That is the exact dead UI
Carter's brief says he removes, and he was told to wait for this engine. Expected, not a
regression.

**Ownership overlap to settle before starting:** Task 12 and Carter's "Package 2 (UI half)"
are the same file and the same edit (`ios/GripIt/Training/FocusAssessmentView.swift`).

---

# Open items for Carter

1. **`releaseHeightFeet` is still non-nullable** in `ThrowRecord["measurements"]`, and
   neither demo Rapsodo screenshot shows it, so photo import will fail validation. Known.

2. **`f731f7a` corrupted the four-seam sample fixture.** That commit pasted
   `rapsodo2.webp`'s break values into all three rows of `sampleThrowSession()`:

   ```
   ["82.4", "2180", "12:30", "84",                 "5.8"]   # before
   ["82.4", "2180", "12:30", "84", "18.6", "13.8", "5.8"]   # after
   ```

   A four-seam with a 12:30 axis cannot produce 18.6 inches of horizontal break. The
   fixture is physically self-contradictory. **Consequence:** demo path three fires
   `four-seam-cut` (magnitude 3.9) instead of the `four-seam-efficiency` (2.2) the design
   predicts. The test asserts the real behaviour with a comment saying to flip it once the
   fixture is corrected. Do not change a `SCALE` value to force the design's answer —
   `SCALE` affects ranking only, and tuning it to match a doc is backwards.

3. **`shared/contracts/assessment.ts` was edited by this track**, and his brief lists
   `shared/contracts/` as his. `80bb17c` deleted `RuleSet`, `AssessmentRule`,
   `RuleCondition`, `RuleZone`, `RuleNextAction` and `ThrowMeasurementKey` — all rule-engine
   types that went dead when `SAMPLE_RULES_LIST` was removed. No dangling references remain
   and the `FocusAssessment` wire type Swift decodes is untouched, but he should know.

4. **`carter/input-and-import` does not exist on origin.** His brief says it should sit
   alongside `jared/feedback-rules`. Package 4 (Perceptron photo import) is the demo opener.

---

# Known, deliberate, not bugs to re-litigate

- **`FocusAssessment.zones` is now always `[]`.** `FocusZone` requires a severity and a
  confidence per zone; the rule engine produces neither, since a rule names contacts to
  change rather than colouring them. Filling them would mean inventing a calibration to
  tint the 3D model with. Zone information travels in `nextAction.zoneId` and under
  `extensions`. The phase-one coupling to the model is the white outline driven by
  `nextAction.zoneId`, so nothing on screen is lost; the prototype severity tint returns in
  phase two if wanted.

- **Five of the design's 17 rule rows are cut**, each with the reason in a code comment.
  Slider: "fingers apart" (unobservable), "not enough sweep" (no defensible break target,
  the app does not collect intended subtype), "spin per mph" (no slider target).
  Changeup: "no fade" (needs a break direction the changeup target does not carry, and
  `detect()` never sees handedness, so it would need an invented number or a sign
  assumption), "loop squeezed rigid" (grip pressure is unobservable). Do not reinstate any
  of them to hit a rule count.

- **`CoachResponse.rewritten` stays, narrowed to the literal `false`.** Swift's
  `CoachReply.rewritten` is non-optional, so omitting the key throws during decode and
  discards the whole reply, hand-fit explanation included. Retiring it is Carter's call in
  Package 2 / Task 12. `CoachResponse.reason` was removed; Swift has it optional and
  `FocusAssessmentView.swift:159` already falls through to `fitReason`.

# Small things left on the floor

- `shared/contracts/fixtures/focus-assessment-four-seam.json` is stale: still records
  `ruleVersion: "sample-rules-1"`, four tinted zones and a `wrist` next action. Left
  because `interpretation.test.ts`, `fit.test.ts`, `api/http.test.ts` and
  `api/_validation.test.ts` all read it as a sample `FocusAssessment` rather than as engine
  output. Worth regenerating as a follow-up.
- `gripFeedback.ts`'s drift headline reads "moved 1 feet". `${spread} feet` is
  unconditional. One-line fix.
- `clockText`'s wrap handles negatives down to −11 only. `parseClock` validates 1:00 to
  12:59, so no negative can reach it today.
- `npx prettier --check shared/focus/interpretation.ts` warns, and did before this track
  too. `npm run format` does not cover `shared/` or `api/`, so nothing in CI reads it.

---

# Rules this engine is built on — do not break them

1. **Never invent a threshold.** If a rule needs a target `targets.ts` does not carry, stop
   and report rather than hardcoding. An unsourced number is exactly how the shipped slider
   ceiling ended up ~30 points wrong.
2. **Guard rules that share a cause.** `four-seam-buried` returns null when the axis is off;
   `four-seam-cut` now does the same, because horizontal break on a fastball is downstream
   of the spin axis. Correctness must never depend on which rule ranks higher — ranking is
   `gripFeedback.ts`'s job.
3. **Handedness is a trap.** `targetFor(pitch, "left")` returns a MIRRORED target: axis
   mirrors about 12 o'clock, horizontal break is NEGATED. Never write a literal comparison
   like `break < 10`. Always measure against the range on the target argument. A sign
   assumption passes every right-handed test and silently inverts advice for every lefty.
4. **No rule may name the `wrist` zone.** The app cannot observe release mechanics. Tested.
5. **No slider rule may tell the index finger to drive, press or grip.** On a slider the
   index is passive on leather by design. Tested.
6. **Rule copy comes from `handInstructions.md`**, in the pitcher's own wording.

## Verify after any change

```sh
npx vitest run shared/focus/     # fast loop
npm test                         # full web suite
npm run ios:focus                # REQUIRED after ANY shared/ change
```

`ios:focus` bundles `shared/` into
`ios/GripItScannerCore/Sources/GripItScannerCore/Resources/focus-engine.js`, which the app
runs through JavaScriptCore. Skip it and the phone silently keeps the old rules. As of
`80bb17c` this genuinely matters — before then it was a no-op.

## Commit discipline

- Stage by exact path. Never `git add -A` or `git add .`.
- Short imperative subject, no `feat:` / `fix:` prefix. Body says why.
- Never stage `ios/GripIt.xcodeproj/project.pbxproj` or `ios/GripIt/Info.plist`. They carry
  uncommitted local signing.

## Definition of done for the whole plan

Three demo paths produce three different rules naming three different finger groups, no
model is called for coaching text, a strained or unreachable contact never receives a
technique instruction, and identical input produces identical output. All four hold today
except the "three different finger groups" half of the first, for the reason in Carter
item 2.

---

# NEXT UP: merge `feature/step-2-grip-model-viewer`, then build the severity gradient

Added after Tasks 6-10 landed. I investigated the merge and stopped short of committing
it, for reasons below. Two pieces of work, in this order.

## Piece A — merge the step-2 viewer branch (do this on a Mac)

```
origin/feature/step-2-grip-model-viewer   a54520f
merge-base with our branch                a0a3c73
```

Note the branch MOVED during the session: it was `2f1e31e` and is now `a54520f`. Re-check
`git ls-remote --heads origin` before starting, someone is pushing to it.

Two commits ahead: `8aeda4a` "Build personalized grip explorer and optimize hand fitting"
and `a54520f` "hi".

**It does not touch `shared/`, `api/` or `src/` at all**, so the rule engine is safe and
the TypeScript side cannot conflict. Verified with a scoped diff.

**Conflicts are exactly two files**, both SceneKit:
```
ios/GripIt/GripViewer/GripSceneView.swift
ios/GripIt/GripViewer/GripViewerView.swift
```
Everything else auto-merges. I did NOT resolve them, because this container has no Xcode
and no macOS, so a blind resolution could not be compiled or tested. Resolve them where
you can build.

**Three things to settle before committing the merge:**

1. **`handInstructions.md` changed the changeup grip, and it breaks a shipped rule.**

   Old: "Index finger: Curl it around the thumb-side surface rather than placing it over
   the top."
   New: "Index finger: Wrap its inner middle/distal surface around the thumb-side centre
   of the ball, close to the equator, opposite the pinky. Keep the tip softly curled
   rather than pointing away."

   The `changeup-spin` rule in `shared/focus/gripRules.ts` quotes the OLD sentence verbatim
   as its `change` copy, because every rule's copy is sourced from `handInstructions.md`.
   That sentence no longer exists on their branch. The pinky also becomes a cradle contact.
   Either their wording wins and the rule copy is rewritten to match, or the change is
   reverted. This is a grip decision, not a code decision — ask the team, do not pick one.

   Their version also says "A closed fingertip loop is optional for this demonstrated
   cradle", which further undercuts the already-cut "loop squeezed rigid" row. Keep it cut.

2. **They have an effort-shading system that collides with the error gradient.**

   Their new "Step 2 demo effort chart" in `handInstructions.md` assigns a pine-green
   intensity per region per pitch (index medium, middle firm, wrist firm stabilisation,
   and so on). That is EFFORT, not error. In the renderer the two are already mutually
   exclusive:

   ```swift
   // GripSceneView.swift:514
   if let pressure, pressure.indices.contains(vertex), severity == nil {
   ```

   Pressure shading only paints when severity is absent. So the hand shows effort OR
   errors, never both. Decide which the feedback screen shows, or add a toggle.

   Their chart assigns the **wrist** firm effort on every pitch. That is fine for effort.
   It must NOT become a severity tint — rule 4 above forbids the engine from ever naming
   the wrist, because the app cannot observe release mechanics.

3. **Junk and a never-stage file in their diff.**
   - A file literally named `GripIt` at the repo root, one line, containing git log output
     from commit `d3045f8`. Not present on `main` or on our branch. Drop it in the merge.
   - `ios/GripIt.xcodeproj/project.pbxproj`, 74 lines changed. Carter's brief says never
     stage it; it carries uncommitted local signing (team id, bundle id, display name,
     `GRIPIT_API_BASE_URL`). Check what survives the merge before committing.
   - `ios/GripIt/Info.plist` is also in their diff, but it is only an alphabetical key
     reorder with no content change. Harmless.

   Their branch does NOT touch `ios/GripIt/Training/`, so `FocusAssessmentView.swift` and
   `TrainingFlowModel.swift` are untouched and the Task 11/12 notes above still stand.

## Piece B — the severity gradient (pure TypeScript, can be done anywhere)

`FocusAssessment.zones` is currently always `[]`. See the "Known, deliberate" section above
for why. The renderer is already built and needs no Swift work: `GripSceneView.swift:519`
bands per-vertex off `GripSeverityBand.band(severity?[zone])`, and
`FocusAssessmentView.swift:42` already feeds it `assessment.severityMap`. Only the data is
missing.

The engine already computes a normalised `magnitude` for every rule that fires, comparable
across units. That is a real severity signal, which the old hand-typed table never had.
Proposed mapping, which invents nothing:

| Zone state | Severity |
| --- | --- |
| Named by the winning rule | `red` |
| Named by another rule that fired | `yellow` |
| Named by a rule that ran, had its reading, and returned null | `green` |
| Untouched by any rule, or its reading was missing | absent |

`shared/contracts/zones.ts` already states absent must not mean green, so "checked and
fine" and "no opinion" stay distinguishable. That is exactly what the bottom two rows
preserve.

`confidence` is the one `FocusZone` field with no honest source. Set it to a single
documented constant with a comment saying the engine does not score confidence, the way
`assess.ts` already does for its top-level `confidence`.

Shape: a function in `shared/focus/gripFeedback.ts` returning `FocusZone[]`, `assess.ts`
passing it through instead of `[]`, tests, then `npm run ios:focus` and stage the bundle.

**Do not** derive severity by inventing magnitude cut points (`> 1.0 = red` and so on)
unless the team explicitly asks for it. The winner/fired/clean mapping above needs no
threshold at all, and rule 1 is the rule this whole engine is built on.

## Suggested order

1. Apply patches 0001-0009 (above). Confirm 207 tests, `tsc -b` clean.
2. Piece B, the gradient. Pure TypeScript, testable without a device, lands independently.
3. Resolve the two grip questions with the team (changeup wording, effort vs error shading).
4. Piece A, the Swift merge, on a Mac.
5. Tasks 11 and 12.
