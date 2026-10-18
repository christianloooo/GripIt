# Interactive Step 2 grip studio

Branch: `feature/grip-node-studio`, based on Jared Shum's
`integration/native-grip-flow` at `a0a3c73`.

Step 2 shows the fitted hand and baseball as its main interface. Seven numbered
markers identify index, middle, ring, pinky, thumb, palm, and wrist. Tap a marker
or the hand to select a region. One floating card shows its instruction, effort,
and pressure/support/stabilization role, with a leader back to the selected
marker. Close the card to inspect the whole model. Drag to orbit, pinch to zoom,
and use Explore for camera presets or an accessible region list.

The same `GripPlan` drives the effort colors and instruction card. The complete
effort chart is in `handInstructions.md`. White means no effort and deeper pine
means more effort. Full wrist stabilization, finger sides/curls, and palm support
are included. Separate nail overlays are removed.

`GripSceneView.Coordinator` projects candidate points on the actual posed skin
through the current camera. It applies the hand's parent transform, including
left-hand mirroring, before projection. A weak display-link driver tracks orbit
and inertia at 30 fps. Callouts spread overlapping targets and clamp them inside
the canvas; their touch targets remain 44 points while the visible discs are
smaller. Empty overlay space passes gestures through to SceneKit. Teardown stops
the display link and removes the overlay.

`GripGraphOverlay` owns the marker and single-card presentation.
`GripArcadeStyle` applies matte lighting and a dark silhouette to the hand.
The baseball retains the supplied Ball.glb clean model's original UVs and PBR
maps, including the original printed details. Separate continuous thread meshes
follow 242 source-albedo stroke fragments. Every thread has a 0.32 mm radius and
stands 0.57 mm above the 36.5 mm leather radius; logos are not extruded.
Regenerate the bundled threads with `scripts/prepare-raised-stitches.py`
(Python, NumPy, and Pillow are build-time preparation tools only).

Jared's `GripStudioSession` and `TrainingFlowModel` remain the flow owners. The
Record throws action passes the same `StudioFit(pose:plan:)` into throw entry.
Returning to a pitch reuses the cached fit. The Step 4 viewer keeps its existing
presentation and diagnostic severity semantics.

## Preview

Open this checkout's `ios/GripIt.xcodeproj`, select GripIt, and run. The normal
flow restores the latest real scan into scanner results, or offers a new scan
when none exists. Completed/imported non-sample profiles are saved locally;
samples never overwrite them. Earlier temporary scan exports are migrated on
first launch. Opening Step 2 creates a fresh profile-scoped fitting session.
For the offline sample prototype, use Debug
launch arguments:

```text
--grip-preview --sample-hand-preview --pitch=four-seam --zone=middle-pad
```

Other pitch IDs: `two-seam`, `slider`, `changeup`. Omit `--zone` to start with all
markers and no open card. `--camera=thumbSide` selects a viewpoint and `--left`
previews a mirrored hand. The sample grip preview does not start the camera or
make coaching API requests. Record throws continues to Jared's integrated flow.

## Verification

Native tests cover node selection, exact instruction/effort content, one visible
card, camera-dependent marker projection, model reuse, 44-point targets, close
handling, and display-link teardown. The original textured and arcade seam-only
balls are checked against the same seven seam landmarks. Core tests audit every
nonzero effort instruction in isolation and verify the serialized highlight record
and training contract compatibility.

`--grip-preview` uses the saved real scan first; without one it returns to the
scanner unless `--sample-hand-preview` is explicitly supplied. Actual captured
segment lengths and palm dimensions deform the rig for every pitch. Missing
finger diameters remain modeled from authored anatomy; this change does not
claim to measure finger widths that the scanner does not collect.

The changeup fits the index and pinky around opposing side centres, with the
thumb beneath the ball. Ring/pinky support poses use lower preferred curls
and no forced deep PIP flexion. The instruction card is lower, marker clearance
is larger, and the annotation camera is backed off to preserve framing.

Verification before the opposite-side revision: 14 core geometry/personalization tests
passed, followed by a targeted all-four-pitch contact/seam regression after the
final fit changes. Three native tests passed for saved-scan migration/sample
isolation, node/card behavior with raised geometry, and seven seam UV landmarks.
Signed device and simulator builds succeeded. A previous real phone scan was
restored into the simulator and used for the native preview.

Wrapped middle contacts follow an extended section of their assigned seam;
they are not forced into the small fingertip anchor patch. Fingertip anchors
still determine the ball frame and prevent arbitrary seam flips.

## Opposite-side changeup cradle

The index and pinky now contact opposite side centres near the ball equator.
Targets use the actual middle/distal inner skin, with opposing normals, while
middle/ring remain the principal upper seam contacts and the thumb supports the
underside. Closed index–thumb tip contact is not a
required stability test; the opposing cradle is the requested visual criterion.
Only the changeup receives the new seeds, knuckle limits, side-contact objectives,
and adaptive collision refinement. Fastball hand poses are unchanged.

The fitter checks the entire uncompressed hand after sparse fitting. If it finds
an overlap deeper than 2.7 mm, it adds the deepest skin vertices as witnesses and
refines the fit, for up to two additional passes. This catches small palm/knuckle
collisions that a regular sampling grid can miss.

Opposite-side revision verification: optimized core tests passed for all four
reference-pitch contacts/seams, 85%/115% hand sizes, and uniform outward-facing
thread geometry. Native tests passed for graph interaction, seven original seam
landmarks, and the supplied PBR maps/UVs. The final saved phone scan places index
and pinky contact centres near opposite equatorial points; thumb pad RMS gap is
0.10 mm and maximum full-skin overlap is 2.08 mm. The signed phone and simulator
builds use `SWIFT_OPTIMIZATION_LEVEL=-O` to avoid slow debug fitting.

Thread coverage matches 579/586 legacy red-reference samples within 1 mm. The
remaining seven samples map to the red printed MLB logo, deliberately not raised.


## Demo fitting performance

Ordinary Xcode Debug runs now compile the app and numerical core with `-O`.
The core package explicitly opts into optimized Debug compilation because the
app's project setting alone does not propagate to local Swift packages. Release
already uses optimization. No solver iterations, mesh vertices, collision checks,
contact objectives, personalization, materials, or raised stitches were removed.
Optimized Debug builds can make stepping through local variables less precise.

On the same Mac, the existing four-reference-grip anatomy/contact/seam test took
71.760 seconds before this change and 0.824 seconds afterward (about 87x faster;
test execution only, excluding compilation). All 15 selected pose,
personalization, and stitch geometry tests passed. The ordinary signed iPhone
build succeeded with no command-line optimization override. These are host test
timings, not an on-phone end-to-end rendering measurement.

The existing per-profile session cache still reuses completed pitch fits. A new
profile gets its own session, so this does not reuse somebody else's hand.
