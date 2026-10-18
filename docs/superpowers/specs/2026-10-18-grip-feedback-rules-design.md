# Grip feedback rules, design

Replaces `sample-rules-1` and the AI paragraph writer with a deterministic
engine that names one grip change per throw set.

## Why

Today's feedback is five `spinEfficiencyPercent` if-statements transcribed from
one narrative paragraph in `PRODUCT.md`, wrapped in a language-model call that
writes prose about them. Three things are wrong with it.

The rules contradict their own cited sources. The four-seam "target" of 90% sits
inside the band Rapsodo calls insufficient for ride. The slider ceiling of 65% is
about thirty points off: Rapsodo puts gyro sliders under 10% and sidespin
sliders near 35%, and calls 65-75% a sweeping curveball.

Spin direction is collected on every throw and no rule reads it, although every
source conditions its target on spin axis and arm slot.

The model's output guard only permits numbers found under `observations` and
`handAndGrip.hand`, so it rejects "2,180 rpm" for the comma, rejects the rule's
own target, and accepts a paragraph containing no numbers at all. The guard
selects for vagueness, which is the behaviour Jared reported.

## What the product owes the pitcher

One sentence naming one thing to do differently with their hand, and the number
that should move because of it. Nothing else counts.

## Principle

The app is a measurement log and an experiment runner, not a diagnostician.
Every sentence on screen is one of three kinds, and they never blur:

- **Measured.** Arithmetic on entered numbers. No model, no inference.
- **Instruction.** The pitch's standing grip description, fixed, never recoloured
  by a throw.
- **Change.** One knob, one direction, plus the number expected to move.

No AI anywhere in this path.

## The knobs

`handInstructions.md` already defines the ideal hold per pitch, and each phrase
in it is an adjustable axis. Four of the six already exist in `GripPlacement`.

| Phrase in handInstructions | Knob | In the contract |
| --- | --- | --- |
| "comfortable, small separation between the fingers" | index-middle gap | no |
| "pad across the raised stitching, seam crossing underneath" | seam relationship | `placement.seam` |
| "resting on the adjacent smooth leather" | distance off seam | `placement.seamOffsetMm`, never read |
| "opposite the space between the two upper fingers" | thumb offset | `placement.opposes` |
| "without deliberately burying it in your palm" | depth in hand | no |
| "enough pressure to prevent slipping" | pressure | `placement.pressure` |

A rule's output is one knob and one direction, phrased in the pitcher's own
instruction wording.

## Derived measurements

Computed in code, never by a model.

| Name | Formula | Note |
| --- | --- | --- |
| Active spin | `totalSpinRpm x spinEfficiencyPercent / 100` | Rapsodo defines efficiency as true spin over total spin, so this is their own arithmetic. `rapsodo1.webp` shows 1077 x 0.95 = 1023 and displays 1023. |
| Spin per mph | `totalSpinRpm / velocityMph` | About 24 is average and roughly level-independent, so it is honestly comparable for a high schooler. Reads as seam purchase. |
| Efficiency from gyro | `cos(gyroDegree) x 100` | `rapsodo1.webp` shows -18.2 degrees and 95.0%; cos(18.2) = 0.9500. Fills whichever field is absent. Sign does not matter. |
| Axis hours off target | circular distance on the clock | Never a linear subtraction; 12:30 and 11:30 are one hour apart. |

## Which fingers drive which pitch

This is why one shared rule table cannot work, and why the current one is wrong.

| Pitch | Drivers | Stabilisers |
| --- | --- | --- |
| Four-seam | index + middle, pads across the seams | thumb under the gap, ring side-on |
| Two-seam | index + middle, pads along their own separate seams | thumb under both |
| Slider | middle only, on the pinky-side seam | index parked on smooth leather beside it |
| Changeup | middle + ring | index curled into a thumb loop, off the top |

A slider tip naming the index finger is wrong by construction.

## Targets

Sourced, with the citation kept per row in the table data.

| Pitch | Axis | Efficiency | Break | Spin/mph |
| --- | --- | --- | --- | --- |
| Four-seam | 12:00-12:30 | 95-100% | +15 to +20" V, ~0" H | ~24 |
| Two-seam | 1:00-2:00 RHP | 75-100% | +10 to +20" H arm-side | ~24 |
| Slider | - | under 35%, gyro version under 10% | - | - |
| Changeup | - | no absolute target | - | below the fastball |

Changeup is judged only against the same pitcher's fastball in the same
session, so it needs a baseline and says so when it has none.

## The rules

Seventeen rows. Each is `(pitch, symptom) -> (knob, direction, zone, expected
movement)`.

### Four-seam

| Symptom | Fix | Zone | Expect |
| --- | --- | --- | --- |
| Axis past 12:30 toward 1-2:00 | Thumb pad under the space between index and middle, on smooth leather | thumb-pad | axis to 12:00, eff up |
| Eff below 95, axis fine | Rotate the ball so the stitching crosses underneath both pads | index+middle | eff up |
| Spin/mph below 22 | Move both pads onto the raised stitching | index+middle | total spin up |
| Cut, HB toward glove side | Reduce the gap to a comfortable small separation | index+middle | cut down, VB up |
| VB low, eff fine | Hold between pads and thumb, do not bury it in the palm | palm | VB up |

### Two-seam

| Symptom | Fix | Zone | Expect |
| --- | --- | --- | --- |
| HB under 10", not running | Index pad along the thumb-side seam, middle along the pinky-side seam, rotate until both engage | index+middle | HB up |
| Axis near 12:00, behaving like a four-seam | Turn the two seams to run wrist to fingertips | index+middle | axis to 1:00-2:00 |
| Eff below 75 | Thumb back under the two upper fingers | thumb-pad | eff up |
| Spin/mph below 22 | Both pads onto their seams | index+middle | spin up |

### Slider

| Symptom | Fix | Zone | Expect |
| --- | --- | --- | --- |
| Eff above 45% | Index onto the adjacent smooth leather; let the middle finger work the pinky-side seam alone | index-pad | eff down, gyro up |
| Eff high and fingers apart | Group both fingers toward the one pinky-side seam, they may touch | index+middle | eff down |
| Little sweep, HB low | Thumb slightly off-centre underneath, no hard pinch | thumb-pad | HB up |
| Spin/mph low | Middle finger needs definite purchase on the stitching | middle-pad | spin up |

### Changeup

| Symptom | Fix | Zone | Expect |
| --- | --- | --- | --- |
| Separation under 8 mph | Let the ball settle into the hand | palm | velocity down |
| Spin near the fastball | Curl the index around the thumb-side, off the top | index-pad | spin down |
| No fade | Ring pad along the pinky-side seam, a principal contact here | ring-side | HB up |
| Loop squeezed rigid | Keep the index-thumb loop comfortable, not a clamp | index+thumb | velocity down |

## Precedence

At most one change is ever shown.

1. **Fit gate first.** If the named zone is `unreachable`, or `strained` beyond
   tolerance, suppress the tip and say the grip does not fit this hand. Never
   tell someone to move a finger they cannot reach. `shortfallMm` is already
   computed per zone and currently discarded.
2. **Missing baseline.** Changeup without a fastball in session asks for one.
3. **Release drift.** Existing behaviour: a drifting release point is an arm
   problem, not a grip problem.
4. **Largest normalised deviation wins.** Each symptom reports how far off target
   it is as a fraction of its band width, and the biggest one is shown.

Ties break by table order, so the output is deterministic.

## Output

`assess()` returns finished text. No rewrite step.

```ts
interface GripChange {
  symptom: string;        // "Your axis is about 2 hours arm-side"
  change: string;         // the instruction, in handInstructions wording
  zones: ZoneId[];        // highlighted on the model
  expect: string;         // "axis should move toward 12:30"
  ruleId: string;
  source: string;         // citation for the target
}
```

`zones` drives the existing `selectedZone` highlight in `GripSceneView`, so the
hand shows the finger with no renderer work. A re-solved pose is a later upgrade,
not a dependency.

## Demo fixtures

`rapsodo2.webp`, real numbers: 77.3 mph, 1642 rpm, axis 1:56, 93.8% efficiency,
13.8" V and 18.6" H. Active spin 1540, spin/mph 21.2.

| Grip | Fires | Tip |
| --- | --- | --- |
| Four-seam | axis ~2h arm-side | move the thumb under the gap |
| Two-seam | spin/mph 21.2 | get both pads onto the stitching |

Existing `sampleThrowSession()`, 82.4 mph, 2180 rpm, 12:30, 84%: axis good,
spin/mph 26.5 good, efficiency low, so it fires the seam-orientation rule and
produces a third distinct tip naming a third set of fingers.

`rapsodo1.webp` is softball, 40 foot distance, drop/rise/screw pitch tabs. It is
kept as an extraction test fixture for when the Perceptron key lands, and is not
a demo input.

## Testing

- Each rule fires on a fixture that trips it and stays silent on one that does not.
- The three demo paths produce their three expected tips, asserted on text.
- Circular axis arithmetic: 12:30 against 11:30 is one hour, not eleven.
- Gyro-only input produces the same verdict as the equivalent efficiency-only input.
- An unreachable or strained named zone suppresses the tip.
- Identical input produces identical output, byte for byte.

## Out of scope

Softball. The solver uses a 36.5 mm ball radius, so every contact and reach
figure is computed against a 73 mm baseball.

Any claim about which finger caused a reading. Per-finger force needs an
instrumented ball; Kinoshita measured it with a transducer inside one, and
Driveline diagnosed a dragging middle finger with high-speed video. Ball flight
plus a static hand scan cannot observe it. Rules name a change to try, never a
cause.

Calibrated confidence. These targets are transcribed from manufacturer education
and coaching sources, not validated against outcomes. The set is versioned
`demo-rules-1` and carries a per-row source so that stays visible.
