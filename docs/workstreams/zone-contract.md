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
  pressure: "medium",   // none | light | medium | firm
  role: "drive",        // drive | support | clear
}
```

`pressure` and `role` are judged, not just displayed. A `drive` zone expected to
be `firm` earns different advice from a `clear` zone expected to be `none`. A
zone with no instruction text is one step 4 has nothing to say about, and it
stays untinted.

Four-seam, derived from `handInstructions.md`:

| zone | instruction | pressure | role |
| --- | --- | --- | --- |
| `index-pad` | Pad across the stitching | medium | drive |
| `middle-pad` | Beside the index, pad across the stitching | firm | drive |
| `thumb-pad` | Fleshy pad underneath, on smooth leather | light | support |
| `ring-side` | Side of the finger against the ball | light | support |
| `pinky` | Relaxed beside the ring, off the ball | none | clear |
| `palm` | Small gap of air, do not bury the ball | none | clear |
| `wrist` | Stay behind the ball | firm | drive |

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
