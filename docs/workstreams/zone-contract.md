# Zone contract

The seven zones where the three workstreams meet. Step 2 says what each zone
should do. Step 4 says how it went. The viewer merges them by `zoneId`.

Canonical types live in `src/contracts/zones.ts`. This file explains them.

## The zone IDs

```
index-pad    middle-pad    ring-side
pinky        thumb-pad     palm       wrist
```

These exact strings are the contract. Everything else about a zone, including
where it sits on the model and how it is shaped or highlighted, belongs to
step 2.

## What step 2 provides, per zone

```ts
{
  zoneId: "index-pad",
  title: "Index finger",
  instruction: "Pad across the seam, not along it",
  pressure: "medium",       // none | light | medium | firm
  role: "drive",            // drive | support | clear
  reach: "comfortable",     // comfortable | strained | unreachable
}
```

`pressure` and `role` are judged, not just displayed. A `drive` zone expected to
be `firm` earns different advice from a `clear` zone expected to be `none`. A
zone with no instruction text is one step 4 has nothing to say about, and it
stays untinted.

### Where the pitch ends and the hand begins

`role` and `pressure` come from the pitch. They are coaching intent and do not
scale with hand size: an index finger drives a four-seam whether the hand is
large or small.

`reach` comes from fitting that pitch to this hand. A small hand often cannot
close the index-to-thumb loop a circle change asks for. A large hand buries the
ball and loses the palm gap. That is the whole premise of fitting a grip to a
player, and it is the one place hand measurements change a zone.

Step 4 reads `reach` before giving advice. It never tells a player to press
harder on a contact they cannot make. An `unreachable` zone produces a fit
problem and an alternative, not a technique correction.

### Roles are per pitch, not per finger

A `GripPlan` carries its own zone set. The same finger changes job between
pitches, so this cannot be baked into the model.

Role and pressure for all four pitches, derived from `handInstructions.md`
except where marked. A dash means the pitch does not constrain that zone, so it
is omitted from `instructionZones` and stays untinted.

| zone | four-seam | two-seam | slider | changeup |
| --- | --- | --- | --- | --- |
| `index-pad` | drive, medium | drive, medium | **support, light** | **support, light** |
| `middle-pad` | drive, firm † | drive, medium | **drive, firm** | drive, medium |
| `ring-side` | support, light | support, light | support, light | **drive, medium** |
| `pinky` | clear, none | clear, none | clear, none | **support, light** |
| `thumb-pad` | support, light | support, light | support, light | support, light |
| `palm` | clear, none | clear, none | **–** | **support, light** |
| `wrist` | drive, firm ‡ | drive, firm ‡ | drive, firm ‡ | ‡ unspecified |

Bold marks a change from the four-seam baseline.

### Per-pitch instruction text

**four-seam** — horseshoe sideways across the fingers, rounded end toward the
thumb.

| zone | instruction |
| --- | --- |
| `index-pad` | Pad across the raised stitching, seam crossing underneath |
| `middle-pad` | Beside the index, pad also crossing the stitching |
| `ring-side` | Side of the finger curled against the ball for light support |
| `pinky` | Relaxed beside the ring finger, clear of the ball |
| `thumb-pad` | Fleshy pad underneath, on smooth leather |
| `palm` | Do not bury the ball. Leave a small gap |
| `wrist` | Stay behind the ball ‡ |

**two-seam** — the narrow seam pair running from wrist toward fingertips. Seams
run *along* the fingers rather than across them.

| zone | instruction |
| --- | --- |
| `index-pad` | Pad along the thumb-side seam, following its direction |
| `middle-pad` | Pad along the other seam, toward the pinky side |
| `ring-side` | Curled lightly against the pinky-side surface |
| `pinky` | Relaxed beside the ring finger, off the ball |
| `thumb-pad` | Fleshy pad underneath, opposite the two upper fingers |
| `palm` | Similar depth to the four-seam. Do not bury the ball |
| `wrist` | Stay behind the ball ‡ |

**slider** — the two-seam narrow area, working the seam on the pinky side.

| zone | instruction |
| --- | --- |
| `index-pad` | Rests on smooth leather beside the middle finger, stabilising |
| `middle-pad` | Pad along the pinky-side seam with definite purchase |
| `ring-side` | Curled against the surface below the middle finger |
| `pinky` | Relaxed beside the ring finger, clear of the ball |
| `thumb-pad` | Underneath and opposite, slightly off-centre, no hard pinch |
| `palm` | No compulsory gap. Choose a comfortable depth |
| `wrist` | Release decides whether this behaves like a slider ‡ |

The palm row is deliberately unconstrained. `handInstructions.md` states there
is no compulsory palm gap for this grip, so step 2 omits the zone and step 4
says nothing about it.

**changeup** — circle-change version. The ball sits deeper in the hand.

| zone | instruction |
| --- | --- |
| `index-pad` | Curled around the thumb-side surface, forming a loop with the thumb |
| `middle-pad` | Pad along the thumb-side seam |
| `ring-side` | Pad along the pinky-side seam. A principal contact here |
| `pinky` | Wrapped lightly around the far side to stabilise |
| `thumb-pad` | Wrapped around the lower thumb-side surface, closing the loop |
| `palm` | Let the ball settle comfortably into the hand |
| `wrist` | Not specified ‡ |

Note the two reversals. The index and middle pair that drives both fastballs is
replaced by middle and ring. The palm goes from clearance to contact, because a
changeup is held deeper. Both are judgeable differences, which is why they live
in the plan rather than the model.

### Sourcing

- Unmarked rows come from `handInstructions.md`.
- † The firmer middle finger on the four-seam comes from `PRODUCT.md`, not from
  `handInstructions.md`.
- ‡ `handInstructions.md` never describes the wrist. These rows come from the
  worked example in `PRODUCT.md`, which colours the wrist on a four-seam. The
  changeup wrist has no source at all and is left unspecified rather than
  invented.

Every pressure value is a first pass. The workstream brief already requires
coach review before any of this is presented as validated advice.

## What step 4 provides, per zone

```ts
{
  zoneId: "index-pad",
  severity: "yellow",                        // green | yellow | red
  reason: "Spin efficiency 72% is below the 90% four-seam target",
  triggeringMeasurement: "spinEfficiencyPercent",
  confidence: 0.6,
}
```

Zones the rules did not reach are absent rather than green, so "no opinion" and
"checked and fine" stay distinguishable.

## The viewer

One component, two modes. The severity map is optional.

```tsx
<GripViewer gripPlan={plan} onZoneSelect={setZone} />
<GripViewer gripPlan={plan} zoneSeverity={severity} onZoneSelect={setZone} />
```

Absent means grip studio. Present means heatmap. There is no second renderer.

## Boundaries

- Step 2 never reads throw data and never decides a colour.
- Step 3 never reads zones. It produces `ThrowRecord` values and stops.
- Step 4 never reads model geometry. It consumes instruction zones and throws.

## Changing this list

Changing the zone IDs changes three workstreams at once. Raise it early, agree
it across all three, and change `src/contracts/zones.ts` in one commit.
