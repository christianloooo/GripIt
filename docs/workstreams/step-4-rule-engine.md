# Step 4: The rule engine

Owner: Carter. Self-contained. Branch `feature/step-4-assessment`.

The engine decides every colour, reason and confidence in the app. A language
model sits downstream of you and rewrites one sentence. It never changes a
severity, picks a zone or invents a number, so your output is the whole of the
product's judgement.

## The function

```ts
assess(input: {
  pitchId: string;
  throws: ThrowRecord[];          // from src/throwEntry.ts, your own work
  zones: InstructionZone[];       // from the GripPlan, Chris's work
  ruleSet: RuleSet;               // versioned data, yours
}): FocusAssessment
```

Pure. No network, no clock, no randomness, no mutation of the inputs. The same
arguments must always return the same assessment, because the UI shows the rule
version beside the result and we have to be able to reproduce it.

Types are in `src/contracts/assessment.ts` and `src/contracts/zones.ts`.

## Rules are data, not code

A rule names a measurement, a condition, the zones it implicates with their
severities, and the one next action. Thresholds move when a coach reviews them,
and that must not mean editing control flow.

```ts
{
  id: "four-seam-low-spin-efficiency",
  pitchIds: ["four-seam"],
  measurement: "spinEfficiencyPercent",
  when: { below: 80 },
  zones: [
    { zoneId: "wrist", severity: "red" },
    { zoneId: "middle-pad", severity: "red" },
    { zoneId: "index-pad", severity: "yellow" },
    { zoneId: "thumb-pad", severity: "yellow" },
  ],
  reason: "Spin efficiency {value}% is below the {threshold}% four-seam target",
  nextAction: {
    zoneId: "wrist",
    summary: "Stay behind the ball",
    detail: "Keep the wrist firm and push through the back of the ball instead of around its side.",
  },
  confidence: 0.6,
  classification: "grip-focus",
}
```

Zone severities belong to the rule rather than being derived from `role` or
`pressure`. Deriving them looked tempting and does not survive the worked
example: the index pad is a `drive` zone on a four-seam but the product colours
it yellow while the middle pad goes red.

## The acceptance test

`PRODUCT.md` contains a worked example. Reproduce it exactly:

> Maya throws a four-seam. Her Rapsodo shows 72% spin efficiency. GripIt
> colours her wrist and middle finger red, and index and thumb yellow.

The expected output is committed at
`src/contracts/fixtures/focus-assessment-four-seam.json`. If your engine
produces that from a 72% four-seam throw, the wiring is right.

## Safety rules, in priority order

These are not optional. Each one exists because breaking it produces advice
that is worse than silence.

1. **An unreachable zone never gets technique advice.** If the plan marks a
   zone `reach: "unreachable"`, the hand physically cannot make that contact.
   Copy it into `unreachableZones`, suppress any rule targeting it, and let the
   UI report a fit problem instead. Telling a player to press harder somewhere
   they cannot reach is the worst thing this product can do.

2. **A null measurement does not fire a rule.** `spinEfficiencyPercent` and
   `gyroDegree` are both nullable and a player supplies one or the other.
   A rule whose measurement is null is skipped, and overall confidence drops
   because less evidence was available.

3. **Release-height problems are `not-grip`.** A drifting release point comes
   from the arm and timing. Classify it `not-grip`, set `nextAction.zoneId` to
   null, and colour nothing. Detecting drift needs the spread across three or
   more throws, so a single throw cannot produce this finding.

4. **Exactly one next action.** A player cannot work on five things. When
   several rules fire, the highest-severity rule with the highest confidence
   supplies `nextAction`. Ties break by rule order so the result stays stable.

5. **Absent is not green.** Only include a zone in `zones` when a rule reached
   it. A zone nobody has an opinion about is left out, and the viewer leaves it
   untinted. Never emit green to mean "not checked".

6. **`prototypeAdvice` stays true** until a pitching coach signs off the rule
   set. The UI labels it.

## Which pitches get real rules

Be honest about the evidence rather than filling in a grid.

- **four-seam** — full rules. `PRODUCT.md` supplies the 90% spin-efficiency
  target and the worked example.
- **two-seam** — conservative rules only. A two-seam is thrown with deliberate
  sidespin, so the four-seam efficiency target does not transfer. Use a lower
  bound and lower confidence.
- **slider** — do not reuse the fastball logic. A slider wants *low* spin
  efficiency, so the comparison inverts. Without a coach-supplied threshold,
  return a low-confidence result or `not-grip` rather than guessing.
- **changeup** — the useful signal is velocity separation from the player's
  fastball, which a single changeup throw does not contain. Return `not-grip`
  until sessions carry both pitches.

Returning no finding is a correct outcome. The product promises focus areas,
not a diagnosis for every throw.

## Consistency

With three or more throws, report velocity and total-spin spread in
`ConsistencyReport` and set `inconsistent` when the spread is wide enough that
single-throw advice is unreliable. Keep it separate from grip focus: a player
can have a good grip and poor repeatability, and those are different problems.

With fewer than three throws, `consistency` is null.

## Out of scope

Calling the language model, rendering anything, 3D geometry, camera work,
mutating `ThrowRecord` or `GripPlan`, and final coaching thresholds.

## Done when

- The Maya fixture reproduces exactly.
- Identical inputs and rule version always give an identical assessment.
- Every emitted zone carries a reason and a confidence.
- An unreachable zone never receives technique advice.
- A null measurement lowers confidence instead of firing a rule.
- A single throw never produces a consistency finding.
- Existing tests still pass.
