# GripIt failure log

## 2026-10-17 — warped thumb after hand scanning

**Reported:** scanned hands produced warped thumbs and failed-looking models. The user's failing video was not available for replay; regression cases below use synthetic scan proportions, not a claimed reproduction of that exact video.

**Code findings:**

- The previous retargeter resized the palm but translated finger joints to scanned lengths without first reshaping their bind skin. This can stretch the thumb web and finger tips.
- Its rotation frame was reconstructed against world Z. That frame can roll abruptly near vertical directions and loses the authored thumb orientation.
- The optimizer restricted every thumb around the same 1.05-radian yaw, even for scan thumb bases near the wrist. That restricts the direction toward the baseball support point.
- Existing tests checked finite vertices and joint/solver agreement; those checks allow stretched or collapsed skin.

**Changes:**

- Reshape the authored bind skin with the original skin weights and measured segment lengths before binding the personalized skeleton.
- Rotate each segment by the minimum rotation from its authored direction to the solved direction, retaining its authored roll.
- Center thumb yaw search on the direction from its measured base to the ball support target.
- Reject invalid dimensions, inconsistent thumb placement, unstable palm/knuckle positions, and obscured or curled thumbs during capture.
- Preflight all four pitch skins before applying a scan. Reject excessive edge stretching, collapsed triangles, a thumb target gap above 12 mm, or thumb capsule penetration greater than 2 mm. A rejected scan leaves the previous measurements/model selected. Unexpected render failures show an explicit rejection message instead of substituting a procedural hand.
- Add **Failure log** in the app header. It records scan failures with frame rejection counts and model failures with measurements, pitch, and available deformation metrics. It stores the last 50 entries in this browser and supports JSON download and clearing. It stores no video or images. It cannot recover failures from before logging was installed.

**Verification:** automated tests cover three synthetic hand sizes across all four pitches, solver/skin anchor agreement, finite surfaces, corrupted thumb proportions, unstable thumb attachments, finite-but-stretched skin, collapsed skin, unreachable thumb targets, and bounded logging with unavailable browser storage. Mesh views were inspected from three angles. Browser interaction and the user's real scan still need verification; native browser automation was unavailable in this environment.

**Limits:** the deformation thresholds are engineering rejection checks, not anatomical validation. This is a generic skinned hand driven by approximate monocular measurements. Passing checks does not guarantee exact skin anatomy, complete thumb opposition, or collision-free skin/ball contact. Solver collision checks use capsules, not the full skin surface.

## 2026-10-17 — native Step 2 viewer and heat-map regression checks

The native SwiftUI/SceneKit viewer uses the measured TrueDepth profile and a
connected skinned surface. Its checks include measured bone/skin-tip lengths,
thumb direction, excessive skin/ball penetration and stretching, and local seam
alignment. Invalid fits show an error instead of a substitute hand. A `GripPlan`
now records per-zone geometric reach/error; this is distinct from Step 4 severity.

The viewer previously lacked stable selectable zones and diagnostic coloring.
It now shares one scene between studio and heat-map mode, uses exact seven-zone
IDs, omits the slider palm, and leaves missing severity unassessed. A same-pitch
new profile previously could retain stale scene geometry; scene caching now keys
on the fitted pose identity. Severity changes preserve the scene and camera.

During regression work, a trial forcing the thumb to the exact lateral midpoint
opposite the upper contacts produced 9–17 mm target errors and >4 mm skin overlap
on the sample. That trial was rejected. The bounded rig retains a thumb-side
anatomical offset, with a smaller pitch-specific opposition adjustment. Exact
antipodal thumb contact is **not** claimed. Wrist guidance is extrapolated and
has no measured reach target; changeup wrist pressure and role are unspecified.

Tests cover all four plans and their seam/opposition contracts, all applicable
surface-zone IDs and selectable triangles, independent wrist/palm masks, small
and large hands, nonfinite/missing severity, boundary colors, and scene/camera
reuse. Simulator screenshots provide visual review, not validation of a real
scan or pitching outcome. See [native viewer details](docs/step-2-viewer.md).

## 2026-10-17 — hand anatomy review after phone screenshots

**Reported evidence:** phone screenshots show stretched palm/web tissue, nail
plates appearing as detached discs, and an unintended pinky loop. The reference
shows a coherent palm, separate fingers, joint structure, and a natural thumb.
The exact exported scan profile is unavailable, so the reference renders are not
claimed as reproduction or verification of that specific scan.

**Changes:** anchored weights below finger-base joints; refined the connected
bind mesh with joint volume and shallow creases; replaced estimated ellipsoid
nails with dorsal skin-triangle patches; changed the relaxed clear pinky target;
added independent open/bent hand review, real SceneKit export, and a reusable
rigged GLB. See [the model review guide](docs/hand-model-review.md).

**Regression checks:** preserve measured lengths through review flexion; retain
anchored palm/wrist points; reject invalid review inputs; prevent unintended
clear-pinky loops; verify nail vertices stay on the actual skin; reload the
SceneKit export and rigged GLB. Phone scan retargeting still needs a check with
the original failing profile rather than inference from screenshots alone.

## 2026-10-17 — thick palm, excessive spacing, and replacement baseball

**Reported:** the palm remained too thick and fingers unnaturally spaced.
**Found:** the reference fixture treated external palm breadth as MCP-center span;
missing-depth fitting used an unrelated hardcoded bind depth; thumb-base radius
scaling could inflate palmar tissue. Earlier ball assets also differed from the
newly supplied Ball.glb.

**Changed:** corrected the reference span/length, calibrated missing-depth scaling
to the actual surface with a 14 mm estimate, blended thumb-base depth, and eased
neutral digit headings. Adjusted ball placement/contact targets and bounded
multi-start posing. Real measurements and root landmarks remain authoritative.
Imported the provided ball's clean variant, preserved original UVs and PBR maps,
and regenerated actual seam references for native and web rendering.

**Verified:** 64 core, 15 iOS, and 33 web tests pass; web production build,
simulator build, and unsigned iPhone Release build pass. Actual four-view hand
renders inspect depth, spacing, and flexion. Source SHA, PBR maps, and 73 mm ball
normalization are checked. See [implementation details](docs/natural-hand-and-ball.md).
The failing real scan was not supplied as an exported profile.

Final render review caught an extra native UV-V flip that broke the supplied
texture atlas and disagreed with stitch sampling. Removed it, retained the source
normal-map orientation, and added a displayed-UV/source-UV regression assertion.
