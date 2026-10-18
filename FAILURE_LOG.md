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
