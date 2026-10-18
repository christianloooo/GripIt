# Step 2: Grip model and viewer

Owner: Chris. This file is self-contained. You do not need to pull another
branch to build against it.

## What you own, with no input from anyone

The hand model, proportional fitting from `HandProfile`, joint solving, ball
pose, seam math, materials, lighting, camera, and how a zone is shaped or
highlighted. Nobody downstream reads your geometry.

`grip.ts` already gives you `BALL_RADIUS = 36.5`, `BALL_CENTER`, and
`seamPoint(t)` over the 11,416-point seam curve in `baseballSeams.json`. The
current finger placement uses magic numbers such as
`-0.5 + pitch.spread - 0.23`. Replacing those is the job.

## What the rest of us need back

Three things, and nothing else couples us.

### 1. Seven zones, these exact strings

```
index-pad    middle-pad    ring-side
pinky        thumb-pad     palm       wrist
```

After a throw, step 4 tints these green, yellow or red and explains why. Every
coachable spot has to be addressable, which is why the list is fixed.

Ids are stable keys, not descriptions. On a changeup `ring-side` makes a pad
contact. The id does not change.

### 2. A `GripPlan` carrying one entry per zone, per pitch

```ts
{
  zoneId: "index-pad",
  title: "Index finger",
  instruction: "Pad across the raised stitching, seam crossing underneath",
  pressure: "medium",      // none | light | medium | firm        from the pitch
  role: "drive",           // drive | support | clear             from the pitch
  reach: "comfortable",    // comfortable | strained | unreachable   from your solver
  placement: {
    surface: "pad",        // pad | tip | side | curl | none
    region: "top",         // top | underside | thumb-side | pinky-side | off-ball
    seam: "across",        // across | along | beside | off | none
    seamOffsetMm: 0,       // null means you choose a comfortable distance
    opposes: [],           // zones this sits opposite across the ball
  },
}
```

`seam` carries most of the meaning. `across` means the stitching runs
perpendicular to the finger and passes under the pad. `along` means parallel to
it. That single field is the whole difference between a four-seam and a
two-seam, and the current code cannot express it.

`opposes` with several entries means the contact opposes their midpoint. A
four-seam thumb sits under the gap between the index and middle fingers, not
under either one.

### 3. One viewer that takes an optional severity map

```tsx
<GripViewer gripPlan={plan} onZoneSelect={setZone} />                        // grip studio
<GripViewer gripPlan={plan} zoneSeverity={severity} onZoneSelect={setZone} /> // heatmap
```

Absent means step 2. Present means step 4. One component, no second renderer.

## The field only you can produce

`reach` is what your solver says after fitting a pitch to a real `HandProfile`.
A smaller hand may need a different ball position to maintain contact.
The approved changeup keeps the thumb supporting underneath, with the index curled beside the ball.

That field is the product. It is what separates GripIt from a static grip
diagram. Step 4 reads it before giving advice, so nobody is told to press
harder on a contact they physically cannot make.

If a continuous value suits your solver better, emit millimetres of shortfall
and step 4 will bucket it.

## Placement, all four pitches

Pitch ids are `four-seam`, `two-seam`, `slider`, `changeup`, matching `PITCHES`
in `grip.ts`. A dash in `offset` means the source describes the relationship
without a distance, so you choose one.

### four-seam

Horseshoe lying sideways across the fingers, rounded end toward the thumb,
opening toward the pinky.

| zone | surface | region | seam | offset | opposes | pressure | role |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `index-pad` | pad | top | across | 0 mm | – | medium | drive |
| `middle-pad` | pad | top | across | 0 mm | – | firm | drive |
| `ring-side` | side | pinky-side | off | – | – | light | support |
| `pinky` | none | off-ball | none | – | – | none | clear |
| `thumb-pad` | pad | underside | off | – | `index-pad`, `middle-pad` | light | support |
| `palm` | no placement | | | | | none | clear |
| `wrist` | no placement | | | | | firm | drive |

Index and middle keep a comfortable small separation.

### two-seam

The narrow seam pair, running from wrist toward fingertips.

| zone | surface | region | seam | offset | opposes | pressure | role |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `index-pad` | pad | top | **along** | 0 mm | – | medium | drive |
| `middle-pad` | pad | top | **along** | 0 mm | – | medium | drive |
| `ring-side` | side | pinky-side | off | – | – | light | support |
| `pinky` | none | off-ball | none | – | – | none | clear |
| `thumb-pad` | pad | underside | off | – | `index-pad`, `middle-pad` | light | support |
| `palm` | no placement | | | | | none | clear |
| `wrist` | no placement | | | | | firm | drive |

Identical to the four-seam except the seam relation. Each upper finger follows
its own seam of the pair instead of crossing a single one.

### slider

The two-seam narrow area, working the seam on the pinky side.

| zone | surface | region | seam | offset | opposes | pressure | role |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `index-pad` | pad | top | **beside** | – | – | **light** | **support** |
| `middle-pad` | pad | top | along | 0 mm | – | firm | drive |
| `ring-side` | side | pinky-side | off | – | – | light | support |
| `pinky` | none | off-ball | none | – | – | none | clear |
| `thumb-pad` | pad | underside | off | – | `middle-pad` | light | support |
| `palm` | no placement | | | | | none | clear |
| `wrist` | no placement | | | | | firm | drive |

Only the middle finger finds stitching. The index rests on smooth leather
beside it toward the thumb side, and the two may touch lightly. The thumb is
allowed slightly off centre and should not need a hard pinch.

The palm is present with an explicit no-effort value. The grip uses a comfortable depth.

### changeup

Circle-change version. The ball sits deeper in the hand.

| zone | surface | region | seam | offset | opposes | pressure | role |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `index-pad` | **curl** | **thumb-side** | off | – | `thumb-pad` | light | **support** |
| `middle-pad` | pad | top | along | 0 mm | – | medium | drive |
| `ring-side` | **pad** | **top** | **along** | 0 mm | – | medium | **drive** |
| `pinky` | **curl** | **pinky-side** | off | – | – | light | **support** |
| `thumb-pad` | pad | **underside** | off | – | `middle-pad` + `ring-side` | light | support |
| `palm` | no placement | | | | | **light** | **support** |
| `wrist` | no placement | | | | | medium | support |

Three reversals from the fastballs. Middle and ring replace index and middle as
the drivers. The index never goes over the top; it curls around the side and
rests beside the thumb, which supports underneath. The palm
goes from clearance to contact, because the ball settles into the hand.

## Instruction text

One sentence per zone that a player can act on.

| pitch | zone | instruction |
| --- | --- | --- |
| four-seam | `index-pad` | Pad across the raised stitching, seam crossing underneath |
| four-seam | `middle-pad` | Beside the index, pad also crossing the stitching |
| four-seam | `ring-side` | Side of the finger curled against the ball for light support |
| four-seam | `pinky` | Relaxed beside the ring finger, clear of the ball |
| four-seam | `thumb-pad` | Fleshy pad underneath, on smooth leather |
| four-seam | `palm` | Do not bury the ball. Leave a small gap |
| four-seam | `wrist` | Stay behind the ball |
| two-seam | `index-pad` | Pad along the thumb-side seam, following its direction |
| two-seam | `middle-pad` | Pad along the other seam, toward the pinky side |
| two-seam | `ring-side` | Curled lightly against the pinky-side surface |
| two-seam | `pinky` | Relaxed beside the ring finger, off the ball |
| two-seam | `thumb-pad` | Fleshy pad underneath, opposite the two upper fingers |
| two-seam | `palm` | Similar depth to the four-seam. Do not bury the ball |
| two-seam | `wrist` | Stay behind the ball |
| slider | `index-pad` | Rests on smooth leather beside the middle finger, stabilising |
| slider | `middle-pad` | Pad along the pinky-side seam with definite purchase |
| slider | `ring-side` | Curled against the surface below the middle finger |
| slider | `pinky` | Relaxed beside the ring finger, clear of the ball |
| slider | `thumb-pad` | Underneath and opposite, slightly off centre, no hard pinch |
| slider | `wrist` | Release decides whether this behaves like a slider |
| changeup | `index-pad` | Curled lightly around the thumb-side surface |
| changeup | `middle-pad` | Pad along the thumb-side seam |
| changeup | `ring-side` | Pad along the pinky-side seam. A principal contact here |
| changeup | `pinky` | Wrapped lightly around the far side to stabilise |
| changeup | `thumb-pad` | Supports the lower centre with its fleshy pad |
| changeup | `palm` | Let the ball settle comfortably into the hand |

## Demo effort coverage

The demo effort chart in `handInstructions.md` specifies every region for all
four pitches. White means no effort. Deeper pine means more pressure or tension.
Wrist stabilization covers the full circumference: firm for four-seam, two-seam,
and slider; medium for changeup. Ring-side support, curled fingers, and changeup
palm support also have visible regions. Every pitch includes the palm, including
an explicit no-effort entry for slider.

Each zone records `highlight: {region, intensity, kind}`. `region` maps to the
finger pad, finger side, curled finger, palm, or wrist; `kind` identifies pressure,
support, or stabilization. This record drives the demo shading. Legacy payloads
without it derive the same record from pressure, role, and placement.

## Out of scope

Camera frames, scan worker messages, MediaPipe results, native iOS types,
throw data, and deciding any zone's colour. Step 4 owns assessment.

## If a zone fights the model

Say so now. Changing the list later breaks three workstreams at once.
