# Carter's brief: throw inputs and Rapsodo photo import

You own getting data **in**. Jared owns deciding what the app **says** about it.
The split is clean, so we should barely touch the same files.

| Owner | Files |
| --- | --- |
| **You** | `shared/throwEntry.ts`, `shared/contracts/`, `api/`, `ios/GripIt/Training/ThrowEntryView.swift`, `ios/GripItScannerCore/.../Training/ThrowRecord.swift` |
| **Jared** | `shared/focus/*.ts` |

Do not edit `shared/focus/`. Jared is rewriting the whole rule engine there.

---

## Package 3 — the contract. Do this FIRST, merge to main immediately.

Both of us build against this, so it has to land before either branch diverges.
It is small. Get it in, merge, then start package 4.

### 3a. Add horizontal and vertical break

Rapsodo shows both on the same screen we already copy velocity and spin from.
In `rapsodo2.webp` they read `13.8" V` and `18.6" H`, just under the break chart.
Four of the new coaching rules are dead without them.

In `shared/throwEntry.ts`, `ThrowRecord["measurements"]` gains:

```ts
/** Inches, from the Rapsodo break chart. Positive = arm-side for a RHP. */
horizontalBreakInches: number | null;
/** Inches, induced vertical break. Positive = ride. */
verticalBreakInches: number | null;
```

Both nullable, because manual entry can skip them.

Mirror in:

- `ThrowDraft` (two new string fields) and `validateThrow` (range check, say -30..30)
- `api/_validation.ts`, the `throwRecord` zod schema
- `ios/GripItScannerCore/Sources/GripItScannerCore/Training/ThrowRecord.swift`
- `ios/GripIt/Training/ThrowEntryView.swift`, two more `field(...)` rows

### 3b. Kill the efficiency-vs-gyro XOR

Today the form forces a choice between spin efficiency and gyro degree, and
`api/_validation.ts` enforces it:

```ts
.refine((m) => (m.gyroDegree === null) !== (m.spinEfficiencyPercent === null))
```

**The real device shows both at once.** `rapsodo1.webp` reads `95.0` efficiency
and `-18.2°` gyro on the same screen. They are two views of one quantity:
cos(18.2°) = 0.9500, exactly the efficiency shown.

So:

- Delete that `.refine`. Allow both, either, or neither.
- Replace the `spinMode` picker in the form with two independent optional fields.
- Add a helper so one fills the other when only one is present:
  `efficiency = cos(gyro°) × 100`, `gyro° = acos(efficiency / 100)`.
  Gyro sign does not affect efficiency.

This also fixes a live bug: every rule reads `spinEfficiencyPercent`, so a user
who picks **Gyro** today silently gets no coaching at all.

Ship 3a and 3b together, merge to `main`, tell Jared.

---

## Package 4 — Perceptron photo import

Point the phone at the Rapsodo iPad, get a `ThrowRecord`. This is the demo
opener and it removes the worst friction in the app: nobody hand-types seven
numbers per throw for thirty throws in a bullpen.

### The API

`perceptron-mk1.5`, OpenAI-compatible, so the existing SDK pattern works:

```python
base_url = "https://api.perceptron.inc/v1"
model    = "perceptron-mk1.5"
```

Key is at `platform.perceptron.inc`. Check what the hackathon track gave us for
credits. Put it in the same ignored `.env` the Anthropic key lives in, as
`PERCEPTRON_API_KEY`. Never in the app bundle.

Relevant capabilities:

- **JSON Schema constrained output.** Define the measurements schema, get it
  back structured. No parsing, no regex.
- **Unreadable text returns null.** Maps straight onto our nullable fields. A
  metric that is not on screen comes back null instead of invented. This is the
  single most important property, do not defeat it with a "guess if unsure" prompt.
- **Few-shot reference images.** "References set the classes, not the answer."
- **Grounding** via `<point_box>` on a 0–1000 grid.
- Accepts PNG, JPEG and **WebP**. Temperature defaults to 0, so extraction is
  deterministic.
- $0.15 / 1M input tokens. 300 requests/min. 20 MiB per request body.

### Use both screenshots as references

`rapsodo1.webp` and `rapsodo2.webp` in the repo root are **two different
layouts**: one softball RAMP-UP, one baseball, different metric sets in
different positions. Pass both as few-shot references so layout variation is
handled without fine-tuning.

Fields to extract, all nullable:

```
velocityMph, totalSpinRpm, spinDirectionClock ("01:56"),
spinEfficiencyPercent, gyroDegree, trueSpinRpm,
horizontalBreakInches, verticalBreakInches, releaseHeightFeet, pitchType
```

Note `rapsodo1.webp` also shows **TRUE SPIN 1023** directly, and 1077 × 0.95 =
1023.15. If true spin is on screen, take it rather than recomputing.

### Make the boxes visible

Ask for `<point_box>` grounding and draw the boxes over the screenshot in the
confirm step. "Here is what I read, tap to correct" is both better UX and a far
better demo than numbers silently appearing in a form.

### Always show a confirm step

Never write straight into a session. Extract, show the user the values with
their boxes, let them edit, then save. An OCR mistake that silently becomes a
coaching input is worse than typing.

### Route it through `api/`, not the phone

The existing server already holds keys and is already wired. Add
`api/extract.ts` next to `api/coach.ts` and reuse `jsonEndpoint` from
`api/_http.ts` for validation and the body limit. Do not put a Perceptron key in
the app.

---

## Package 2 (UI half) — removing the AI feedback

Jared is deleting the AI from the coaching path. The engine will return finished
text, so the app stops calling a model to write a sentence.

On your side, in `ios/GripIt/Training/FocusAssessmentView.swift`:

- Remove the `AI COACHING` panel's loading, retry and `connectionMessage` states
- Remove the "Your throw data is ready. Retry coaching…" fallback — it currently
  shows **nothing useful** whenever the model output is rejected
- Keep the "Ask about your result" question box. That one stays AI.

Wait until Jared's engine lands before ripping this out, or the screen goes blank.

---

## Branches

```
main
 └─ your contract change (package 3) ──> merge to main straight away
      ├─ carter/input-and-import
      └─ jared/feedback-rules
```

Short-lived branches. Merge to `main` as soon as something is green.

Repo is `christianloooo/GripIt`, it is **public**, and `main` now holds the
complete integrated app.

---

## Verifying

```sh
npm test                 # web + shared suites
npm run ios:focus        # rebuild the native JS engine after ANY shared/ change
```

`npm run ios:focus` matters: `shared/` is bundled into
`ios/GripItScannerCore/Sources/GripItScannerCore/Resources/focus-engine.js` and
the native app runs that bundle through JavaScriptCore. Change `shared/` without
rebuilding it and the phone silently keeps the old rules.

Swift package tests:

```sh
cd ios/GripItScannerCore
swift test --scratch-path /tmp/gripit-build
```

The `--scratch-path` is not optional. The repo sits under iCloud-synced Desktop,
which stamps `com.apple.FinderInfo` on build products, and codesign refuses to
sign them. Building outside the synced folder avoids it.

---

## Two things not to break

- `ios/GripIt.xcodeproj/project.pbxproj` and `ios/GripIt/Info.plist` carry
  **uncommitted local signing** on Jared's machine: team id, bundle id, display
  name, and `GRIPIT_API_BASE_URL`. Never stage them. Use
  `git add <specific files>`, never `git add -A`.
- Keep Anthropic as the provider for the question box. No migration.
