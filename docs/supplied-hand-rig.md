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

The existing bounded joint solver supplies a coarse initial grip. Photo-guided
knuckle curl then seeds the principal contacts; a further bounded refinement
evaluates sparse samples of the real deformed skin, reducing ball
penetration and pad gaps; the circle-change refinement also measures the actual
index–thumb pad gap. This changes joint angles and ball position. It never
projects, flattens, or sculpts hand vertices onto the ball during fitting. A
separate bounded contact-compliance pass, described below, illustrates skin
pressure after the rig has fitted. A final full-mesh check still rejects severe
overlap or stretch. Capsule clearance and synthetic bone-tip target penalties
are excluded from this final skin fit: retaining them fought contact with the
authored pad surface and favored a fingertip pinch. A small angle regularizer
keeps the fit close to the guided pose.

## Photo references and visible pressure

The supplied four-seam, two-seam, slider, and changeup photos guide the support
finger silhouettes. Fastball and slider ring/pinky targets fold back toward the
palm; they no longer use an open relaxed pinky pose. A minimum tucked curl is
maintained during contact refinement so the optimizer cannot satisfy clearance
by extending those fingers beside the ball. Middle/index stay the primary
fastball contacts; middle/ring stay the primary circle-change contacts. The
slider follows the guide's middle-on-seam, index-on-adjacent-leather variant.

`GripContactDeformation` adds localized compliance to palmar contact skin only.
It follows the existing light/medium/firm coaching pressure levels, flattening
the pad against the ball's curved surface and spreading flesh laterally. No
vertex moves more than 1.2 mm. The pass runs only when the rig already has a
contact within 1.5 mm; it cannot repair a floating or invalid grip. Nails,
unloaded fingers, wrist, measured bones, and neutral hand review are unchanged.
Subtle localized blanching accompanies the geometry and remains present when
diagnostic severity overlays are toggled.

This is an illustrative contact response, not a soft-body simulation or force
estimated from photographs/TrueDepth. The model-info screen labels pressure as
illustrative. Tests compare firm versus medium widening on the same fitted
hand, verify larger contact area, retain the deformation bound, and check that
unloaded skin stays unchanged. Seams are fitted after compression, using the
resulting skin contacts.

Fingerprint pads are selected on the palmar side of the distal skin, excluding
nails and lateral caps. The thumb’s rounded palmar end remains part of its pad. Refinement fits a small patch of those vertices rather
than accepting one nearby vertex. Contact markers, contact diagnostics, and
zone reach use skin distances; obsolete bone-tip target errors stay internal
to the initial solver. The circle-change loop is evaluated against the thumb,
not as a required index pad contact with the ball.

Long fingers cannot use thumb opposition. Their bending-plane angle is bounded
to ±0.12 radians, spread to ±0.4 radians, and distal flexion is coupled to the
middle joint (0.35–0.85 times its bend, with a 0.12-radian allowance). Candidate
poses are evaluated on independent copies so rejected trials cannot alter a
coupled joint. These are conservative animation constraints, not a clinical
model of an individual player's range of motion.

`GripSeamTemplate` pins each upper contact to a named stretch of the bundled
baseball's actual stitching. The assigned seam pair and actual pad-contact pair
define corresponding frames; aligning those frames follows changes in grip
depth without imposing an unrelated world-space ball orientation. Slider uses
the middle contact normal and seam tangent, with the reference resolving its
tangent sign. The ball adjusts locally to the actual skin contacts: across for four-seam,
along separate narrow seams for two-seam/changeup, and middle on seam/index on
adjacent leather for slider. It cannot jump to an unrelated equally scored
region of the ball. The coordinates depend on the bundled clean Ball.glb;
review the template if that asset or its texture coordinates change. Visual
naturalness does not establish a correct release or pitch outcome.

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
