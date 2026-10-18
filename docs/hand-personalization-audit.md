# Hand personalization audit — 2026-10-18

Scope: `feature/grip-node-studio`, based on `origin/integration/native-grip-flow`.
This audit does not implement the pending circle-change, relaxed-finger,
annotation-spacing, or raised-seam changes.

## Findings

The normal scan-to-viewer flow generates a personalized mesh, rather than choosing
one of four pre-rendered hands. The four pitch poses share an authored source rig
and pitch-specific fitting objectives. Their proportions come from the profile.
This is a parameterized generic hand, not a reconstructed copy of the entire skin
surface of the scanned hand.

| Input | Scanner produces it? | Model behavior |
| --- | --- | --- |
| Three segment lengths for each finger | Yes | Changes bone lengths and axial skin scaling |
| Palm width | Yes, index-MCP to pinky-MCP distance | Scales the palm and establishes default finger thickness |
| Palm length | Yes, wrist to midpoint of outer MCPs | Changes palm longitudinal scale, with limits |
| Finger diameter | No: always null | Uses source-rig thickness scaled by palm width; a supplied imported diameter does change radial skin scaling |
| Palm thickness | No: always null | Preserves source-rig thickness scaled by palm width |
| Finger-base landmarks | Yes | Blends measured bases into authored anatomy, with a maximum 3 mm offset per axis |
| Handedness | Yes | Canonical fitting; renderer mirrors left hands once |

TrueDepth is used: `TrueDepthCaptureService` selects the front
`builtInTrueDepthCamera` and synchronizes RGB with depth output.
`DepthLandmarkMapper` uses MediaPipe image points to sample the depth map, then
camera calibration/intrinsics to project metric landmarks. It does not use
MediaPipe's guessed world coordinates as millimeter measurements. However, 21
sampled landmark positions alone do not measure finger outlines or diameters.

## Data path and cache

1. `ScannerFrameProcessor` maps synchronized depth and image landmarks into accepted observations.
2. `ScannerSession.makeProfile` calls `HandMeasurementAggregator.measure`, taking
   median segment/palm measurements over the accepted observations.
3. `ScannerView` passes `model.profile` into `GripViewerView`.
4. The viewer constructs a `GripStudioSession(profile:)`. Its pitch-keyed cache
   belongs to that one session/profile; it is not shared globally across scans.
5. `GripPoseSolver.initialFit` derives lengths, radii, palm scales, and roots.
6. The solver fits each pitch, and `deform` applies axial and radial skin scaling.
7. `GripSceneBuilder` builds the hand geometry from `pose.vertices`.
   `GripSceneView.Coordinator` replaces the scene for a new pose ID.

The Debug `--grip-preview` launch path deliberately bypasses the scanner and
passes `SampleHandProfiles.averageRight()`. This was the mode used for the last
installed prototype preview. Reopening that preview cannot demonstrate that a
fresh scan changes the hand. The normal app route starts at the scanner.

## Limits that reduce visible differences

When `preserveAuthoredAnatomy` is enabled:

- Each finger segment is clamped to 80–120% of its authored length after palm-width scaling.
- Each supplied finger diameter is clamped to 85–115% of authored diameter after palm-width scaling.
- Palm longitudinal scale is clamped to 90–110% of the palm-width scale.
- Supplied palm-depth scale is clamped to 85–115% of the palm-width scale.
- Finger-base offsets use 35% of the landmark difference, capped at 3 mm per axis.

Consequently, two requests beyond the same clamp can produce identical effective
dimensions. The original raw measurements remain in the profile; the displayed
hand can differ from them. Existing `adjustedProportions` diagnostics indicate
that a bound was used but do not list each requested versus effective value.

Pressure instructions/intensities are pitch templates, not force measured by the
hand scan. Their shading follows the fitted skin, but changing finger dimensions
does not independently establish a new measured pressure distribution.

## Reproducible verification

`GripPersonalizationAuditTests` checks:

- Requested +8% index segment lengths change the rendered index-pad vertices
  while leaving radius unchanged. Existing bounds reduce the effective total
  increase to about 5.3% for this fixture (81.28 to 85.59 mm).
- Isolated +8% supplied index diameter changes rendered skin while leaving bone lengths unchanged.
- +10% metric observation dimensions propagate through aggregation and fitting
  into different skin vertices in all four pitches, including all five fingers'
  effective bone lengths. Profile IDs are deliberately identical.
- The scanner aggregation leaves finger diameter and palm thickness null.

Run from the repository root:

```sh
swift test --package-path ios/GripItScannerCore --filter GripPersonalizationAuditTests
```

These synthetic checks verify sensitivity and data flow. They do not validate
physical measurement accuracy against a ruler or a real hand surface.

Observed maximum skin displacement with +10% observation dimensions: four-seam
16.45 mm, two-seam 16.45 mm, slider 12.85 mm, changeup 22.42 mm. Isolated index
length change moves pad skin up to 4.11 mm; diameter 17.79 to 19.21 mm moves pad
skin up to 0.68 mm. Maximum displacement includes pose adjustments, so it is not
a direct measurement of finger-length error.

## Recommended follow-up

First compare two exported real scan profiles and their effective fitted
dimensions, using the normal scanner route instead of sample preview. Then add
finger-width measurement using segmented hand boundaries and calibrated depth;
do not label a palm-width-based default as individually measured finger width.
Expose requested/effective dimensions before deciding whether anatomy bounds
should be widened. Full surface reconstruction is a separate scope from fitting
this authored rig.

## Follow-up implementation

The viewer now restores the most recent saved real scan, migrates earlier
temporary scan exports, and saves new completed/imported real profiles locally.
A sample cannot overwrite a saved scan. The debug grip preview uses saved scan
data first and requires an explicit sample-preview flag to fall back to the
bundled sample. The scanner-to-viewer presentation identity includes the encoded
profile so a changed profile gets a fresh fitting session. Finger-width and
palm-thickness acquisition remain outside this change.
