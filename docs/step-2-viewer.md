# Native grip viewer, pressure shading, and diagnostic heat map

The active app is SwiftUI with SceneKit. `ScannerView` passes the measured
`HandProfile` to `GripViewerView` after a scan or JSON import. The bundled sample
is explicitly labeled. The legacy React viewer is not the native app's renderer.

The audit found an existing native skinning/pose solver and seam fitting, but no
native `GripPlan`, severity map, zone surfaces, or picking contract. `CLAUDE.md`,
`PRODUCT.md`, and `handInstructions.md` were absent. The two supplied Step 2
briefs define the new contracts (the [placement contract](step-2-grip-model.md) is preserved); `docs/pitch-grip-guide.md` preserves the earlier
grip guide. The original scanner, camera permissions, and measurement schema
remain in place.

## Four plans, one rendering path

`PitchGrip` serializes as `four-seam`, `two-seam`, `slider`, and `changeup`.
`zoneTemplates` centralizes instructions, pressure, role, placement, seam
relationship, and opposition. The seam optimizer consumes those relationships.

- Four-seam: index/middle across stitching, with middle intended firmer.
- Two-seam: index/middle along stitching, both medium intended pressure.
- Slider: index on adjacent leather, middle along stitching, thumb support biased
  toward opposition to the middle. Palm has an explicit no-effort entry.
- Changeup: middle/ring are upper drivers; thumb supports the lower centre; index wraps beside it; pinky
  curls at the far side; palm becomes support. Wrist uses medium stabilization.

Geometry uses individual measured bone lengths and palm dimensions. Width is
MCP span, not a uniform whole-hand scale. Missing thickness uses an explicit
model estimate; missing essential lengths are rejected with a readable error
instead of fabricated measurements. Invalid/deeply overlapping skin is rejected.

`GripPlan(pose:)` reports surface contact/clearance error in millimeters and reach
per zone. The thumb must make skin contact in the central underside quadrant; a closed
index–thumb circle is optional and cannot displace that support. Slider index/middle
and changeup middle/ring must establish contact on their middle sections as well
as their distal pads. Engineering buckets
are <=3 mm comfortable, >3 through 8 mm strained, and >8 mm unreachable. These
are not clinical limits. Wrist has no geometric target; its explanation says so.
The demo effort chart in `handInstructions.md` defines all seven highlight regions.

## Supplying Step 4 severity

The native counterpart of the requested shared component is `GripSceneView`:

```swift
let plan = GripPlan(pose: pose)
GripSceneView(pose: pose, showContacts: false, camera: .threeQuarter, reset: 0,
              gripPlan: plan, onZoneSelect: { zone in print(zone.rawValue) })

let severity = GripSeverityMap(["thumb-pad": 0.62, "wrist": 0.85])
GripSceneView(pose: pose, showContacts: false, camera: .threeQuarter, reset: 0,
              gripPlan: plan, zoneSeverity: severity,
              onZoneSelect: { zone in print(zone.rawValue) })
```

The complete studio screen also accepts `zoneSeverity` and `onZoneSelect`:

```swift
GripViewerView(profile: profile, zoneSeverity: severity,
               onZoneSelect: { zone in print(zone.rawValue) })
```

`GripSeverityMap` encodes/decodes a plain JSON object, e.g.
`{"thumb-pad":0.62,"wrist":0.85}`. The stable IDs are `index-pad`, `middle-pad`,
`ring-side`, `pinky`, `thumb-pad`, `palm`, `wrist`. Unknown keys and nonfinite
numeric inputs are discarded; finite inputs clamp to [0,1]. Bands are
[0,0.2) green, [0.2,0.5) yellow, [0.5,1] red. Missing keys remain unassessed and
retain the base skin color. A present empty map is diagnostic mode with no
assessed zones; nil is normal studio mode.

Step 2 defaults to **Show effort**: a continuous white-to-pine-green scale.
White means no effort; deeper pine means more pressure or tension. Soft gradients wrap
loaded finger sections for visibility, including middle-phalanx contact for wrapped grips.
The same map includes ring-finger sides, changeup curls/palm support, and the full wrist
circumference. Wrist color represents stabilization. Turn it off for natural skin.

Step 4 keeps its numeric diagnostic bands and missing-value behavior. An incoming
severity map takes precedence over pressure shading. Intended pressure never
determines a severity color. There is no throw assessment engine in this feature.

## Surfaces and interaction

`GripZoneSurface` derives localized, smoothly tapered surface weights from the
skinned asset's bone weights, longitudinal finger position, and pad orientation.
Colors follow the actual posed vertices, with the existing lighting and normals.
Wrist and palm masks are separate. The changeup keeps the `ring-side` ID while
moving its contact to the pad. Slider palm remains selectable with explicit no effort.
The finger mesh is continuous with no separate fingernail overlays. The baseball keeps its own material.

Tapping a visible hand triangle uses its real barycentric coordinates to return
the stable zone ID. The baseball occludes taps naturally. The accessible zone
buttons also select contacts hidden behind the ball. Selection uses a white
surface contour and a text panel showing instruction, intended pressure, role,
reach/error, placement, seam relation, opposition, and diagnostic severity.

Orbiting does not rebuild the scene. Severity and selection updates retain the
vertex/normal buffers, baseball, and camera. A new fitted pose, including a new
profile of the same pitch, replaces the scene. Pinch zoom is bounded to a camera
distance of 150–650 mm; view presets reset framing. Teardown releases the scene
and removes installed gesture targets. A solve/asset failure preserves the screen
with a readable error instead of showing a substitute hand.

## Running and reviewing

Open `ios/GripIt.xcodeproj`, select **GripIt**, and Run. Complete/import a scan,
then choose **Explore my grips**. Or load the labeled sample, explore grips,
with **Show effort** enabled by default. Use the zone buttons and rotate
through Palm / Thumb / Back to inspect occluded contacts.

For reproducible Debug simulator previews, add these scheme launch arguments:

```text
--grip-preview --pitch=changeup --camera=thumbSide
```

Other pitch IDs are `four-seam`, `two-seam`, `slider`; `--left` mirrors the hand.
Use the **Show effort** toggle for normal skin. These shortcuts are Debug-only.

After launching on a booted simulator, capture a screenshot with:

```sh
xcrun simctl io booted screenshot /tmp/gripit-review.png
open /tmp/gripit-review.png
```

## Limits to review

The surface is a personalized generic hand, not a reconstruction of skin, joint
axes, tendons, or pressure. Collision and reach tolerances are engineering
approximations. Thumb opposition retains an anatomical lateral offset rather
than exact antipodal placement. Global horseshoe direction and all grips still
need a coach's review, even where local pad/seam tests pass. Occluded colored
pads become visible by orbiting; the zone buttons remain available throughout.
The supplied ball is a textured mesh; stitching appearance comes from that asset,
not an added raised-stitch mesh. Real-phone scans and coach validation remain
separate from simulator rendering checks.

## Current verification

See [hand proportions and ball integration](natural-hand-and-ball.md) for the
latest geometry, supplied-ball asset pipeline, render review, and test results.
The native and web viewers now share the project's supplied Ball.glb, rather
than the earlier worn baseball asset.

## Complete effort records

All seven zones are present for every demo pitch, including white/no-effort regions.
Each zone serializes `highlight: {region, intensity, kind}` alongside its existing
pressure/role/placement fields. The highlight record controls intensity; legacy
payloads without it derive the record from their existing fields. Regions include fingerPad, fingerSide, curledFinger,
palm, and wrist; kinds include pressure, support, and stabilization. Four-seam,
two-seam, and slider wrists are firm; changeup wrist is medium.

The renderer reads the supplied plan and updates shading when instructions change,
without rebuilding the mesh or resetting the camera. Coverage tests isolate each
nonzero instruction and require visible geometry for its highlight. Wrist tests
check every vertex around the cuff, including its dorsal surface. Actual finger
compression remains a separate contact-only operation.
