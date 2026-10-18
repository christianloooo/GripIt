# Smooth scanner capture

The user approved preserving hand identity from the palm capture and separating
it from side-view measurement quality after the thumb step stalled at 25%.

## Scope

Keep native selfie TrueDepth, four views, eight accepted observations per view,
metric geometry checks, and HandProfile 1.0.0. Do not fabricate hidden joints or
weaken depth/stability requirements. Preserve local device signing settings.

## Decisions

- Establish the selected physical hand from three confident palm observations.
- Retain that identity only during spatially continuous one-hand tracking.
  Low-confidence side labels do not reject a continuous track. Gaps over 750 ms,
  abrupt movement/scale jumps, multiple hands, or invalid input force palm
  reacquisition without discarding already completed scan views.
- Confidence stored in the profile remains the initial palm identity score,
  explicitly labeled as such, not a probability of measurement accuracy.
- Capture oblique thumb/pinky views with visible fingers, rather than requiring
  an edge-on silhouette where predicted joints overlap on the same depth surface.
- Show specific movement, overlapping-finger, depth-noise, identity-reacquisition,
  and pose instructions. Keep accepted-frame progress visible.

## Verification

Regression tests cover low-confidence side continuation, loss/reacquisition,
wrong-hand initial capture, invalid samples, partial-turn pose matching, and
stability rejection reasons. A synthetic full four-view sequence must finish
through the same identity/depth/stability gates. Run core XCTest and iPhone SDK
type-check. Actual phone capture and measurement accuracy still require testing.
