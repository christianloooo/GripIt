# Hand model anatomy review

The supplied reference is an anatomy and silhouette reference, not a mesh file.
This update refines the project's licensed WebXR hand into a reusable rigged
asset and renders the real mesh in a neutral pose before adding baseball targets.

## Review it in the app

Open `ios/GripIt.xcodeproj` and run **GripIt**. From Grip studio, tap **Hand model**.
The screen uses the current scanned/imported hand profile. Debug reference previews
use an explicitly labeled sample. Rotate through Palm, Back, Thumb, and Reset;
use **Finger bend** to inspect joint deformation without the baseball. **Inspect
mesh topology** displays the triangles. **Export 3D hand (.scn)** saves the actual
posed SceneKit geometry, including its attached nail patches.

Debug scheme arguments for reproducible review:

```text
--hand-model-preview --camera=palm
--hand-model-preview --camera=back
--hand-model-preview --camera=threeQuarter --flexion=0.6
```

Add `--wireframe` to inspect the triangle mesh.

## Reusable files

- `public/models/gripit-anatomical-hand.glb`: a portable, rigged bind-pose hand,
  18,514 vertices and 25 bones. Units are meters. The original wrist/finger bone
  names are preserved. Includes refined joint shapes and palmar creases.
- `ios/GripItScannerCore/Sources/GripItScannerCore/Resources/grip-hand.json`:
  matching native bind surface, joint coordinates in millimeters, and dense skin
  weights. Native fitting keeps all influences. GLB normalizes its four largest
  weights per vertex for compatibility; maximum discarded weight is recorded in
  its scene metadata (7.26% in this export).
- The `.scn` export is a posed static review model, not an animated skeleton.
  Native measured posing continues to use the JSON rig and solver.

Generate both bind assets with `node scripts/prepare-native-grip.mjs`.
The existing MIT hand license is preserved in `public/models/HAND-LICENSE.md` and
in the native resource bundle. This is a refined derivative, not a recovered copy
of the reference image's original mesh.

## Structural changes

Smoothing the original skin weights spread proximal finger influence below the
knuckles. Those weights now transition back to anchored palm/metacarpal bones,
so bending a finger does not pull a broad sheet of palm tissue upward. Joint
bulges, shallow palmar flexion grooves, and palm creases modify the actual bind
vertices while preserving connected topology and the calibrated fingertip caps.

The previous nail ellipsoids were positioned from an estimated radius and
oriented relative to the ball. They could appear as detached discs. Nail patches
now reuse the actual dorsal skin triangles and sit only 0.04 mm above them to
avoid depth flicker. Their location follows the same skin deformation as the
finger. This also makes the nail orientation independent of ball placement.

The clear pinky's old target lay only about 33 mm from its base, forcing a
full-length finger into an unintended loop. Fastball/slider pinky targets now
come from a gentle relaxed bend beside the ring finger. Changeup support remains
a separate pitch-specific target.

The neutral preview and the grip viewer share the same mesh, personalization,
SceneKit materials, and camera controls. Essential missing measurements are
still rejected. The model does not fabricate a missing scan.

## Verification and limits

Core tests verify measured segment lengths in neutral and bent review poses,
anchored wrist/palm motion across pitches, and a clear pinky that does not form an
unintended circle. App tests verify the neutral scene/export and that nail patch
vertices remain attached to the actual posed skin through flexion. The rigged GLB
was reloaded with GLTFLoader: all 25 bones and normalized weights were present.

The model is a personalized generic hand, not a reconstruction of the user's
skin or joint anatomy. Reference-hand renders verify the mesh and deformation;
they do not reproduce the exact failing phone scan, whose exported profile was
not supplied. Large changes in landmark placement can still require separate
retargeting work. The synthetic joint/crease detail is illustrative. The original
reference's quad layout is not reproduced; the runtime asset is triangulated.

Current verification: 64 core tests and 15 app tests passed. The additional export
check passed after confirming that the MIT notice survives the `.scn` round trip
in a non-rendered license node. Both GLB and native exports retain the notice.
Local review renders and the exported SceneKit hand are in
`ios/build/reviews/natural-fit/`. A Debug-only `--save-hand-render` launch argument
writes a four-view render of the actual meshes to the app's temporary directory.

The measured bind fit also eases palm-depth scaling into finger-thickness scaling
at the MCP instead of applying the full finger radius scale to the broad palmar
pad. This reduces the raised ridge seen in the first anatomy review render.
The final four-view sheet renders actual SceneKit meshes, including a bent pose.
The unsigned iPhone Release build passed after these changes.

The current refinement also corrects reference MCP spacing, calibrates palm depth
from the actual bind surface, and eases the thumb-base depth into the palm.
Pitch fitting now uses a raised ball position, adjusted upper-pad targets, and
additional bounded solve starts for thumb opposition and coupled contacts.
See [hand proportions and ball integration](natural-hand-and-ball.md) for the
current asset pipeline and verification. These engineering checks still do not
replace review of a real scan or coaching validation.
