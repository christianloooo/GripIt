# Supplied Blender hand integration

The native Step 2 viewer now uses the uploaded `Rigged Hands.blend`, selecting
the open `Hand.R` mesh and `Hand_Right` skeleton. The source scene also contains
curled and rotated hand copies. The original surface, nail detail, and painted
skin weights provide the anatomy; the app does not generate replacement palm
or finger shapes.

## Assets and regeneration

- `public/models/supplied-hand.glb`: portable, skinned hand, 35,312 vertices,
  27 named bones including five fingertip reference markers. GLB units: meters.
- `ios/GripItScannerCore/Sources/GripItScannerCore/Resources/grip-hand.json`:
  the matching native surface with all painted influences, joint coordinates
  in millimeters, authored finger radii, and source provenance.
- `public/models/SUPPLIED-HAND-NOTICE.md`: provenance of the uploaded file.
  The archive did not supply a creator/license notice. It is not relabeled as
  the old WebXR asset's MIT license.

To regenerate, open the supplied blend using Blender with embedded scripts
disabled, then run `scripts/import-hand-rig.py`. It selects only Hand.R, adopts
its matching visible bone pose as the new bind pose, trims the long forearm to
a closed short wrist, and reduces topology for mobile. The source mesh copies
have baked poses and painted groups but no live armature modifiers: using their
edit-bone coordinates with the visible meshes offsets skin from the skeleton.
The imported bind uses matching posed bone heads and preserves the visible
surface instead of trying to reverse-deform it. The old
`scripts/prepare-native-grip.mjs` is a legacy WebXR generator and must not
overwrite the active supplied rig.

Native rendering uses the dense weights. The portable GLB retains its armature
and normalized weights for review and reuse in other tools. The original
uploaded zip and Blender file are preserved unchanged.

## Conservative personalization

Palm span establishes an overall scale. Palm length may change by at most 10%
relative to that scale. Missing palm thickness keeps the source model's depth;
an available thickness may alter depth by at most 15%. Finger segment lengths
are guided by the scan but bounded to 80–120% of the scaled authored lengths.
Thickness adjustments are limited to 85–115% of the authored radii. MCP/CMC
surface measurements blend gently into the authored joint bases, moving each
axis by at most 3 mm. The MCP arch and thumb pad therefore retain their shape.

The raw HandProfile remains unchanged. The fitted pose contains the lengths
actually used. When a measurement is limited or a root is blended, the viewer
explicitly says that proportions were adjusted to preserve natural anatomy.
This is a conservative personalized generic model, not an exact skin scan.

The previous 14 mm default palm thickness and generic finger-cylinder radii
were inappropriate for this source model. The native deformer now uses its
authored radii, preserves the painted weighting, and retains volume with dual
quaternion posing.

## Ball fitting

The existing bounded joint solver supplies an initial grip. A further bounded
refinement evaluates sparse samples of the real deformed skin, reducing ball
penetration and pad gaps; the circle-change refinement also measures the actual
index–thumb pad gap. This changes joint angles and ball position. It never
projects, flattens, or sculpts hand vertices onto the ball. A final full-mesh
check still rejects severe overlap or stretch.

Legacy bone-end target errors remain visible as approximate-fit diagnostics.
They are not equivalent to distances between the authored pad skin and ball.
Seam alignment and coaching-fit diagnostics remain available; visual naturalness
does not establish a correct release or pitch outcome.

## Review

The same native Hand model screen supports neutral and bent inspection without
a baseball. The grip screen uses the same source surface and personalization.
Source-dependent tests now compare palm volume with the authored source instead
of requiring a 10–16 mm thin palm. Tests retain full-skin contact/overlap checks,
segment-length preservation, source-weight normalization, fixed palm anchors,
left mirroring, seam relationships, and limits on measurement-driven changes.

Local Blender renders inspect the actual exported native vertices for open,
bent, four-seam, two-seam, slider, and circle-change poses. These use a labeled
sample hand profile; a fresh user scan should still be reviewed on the phone.
