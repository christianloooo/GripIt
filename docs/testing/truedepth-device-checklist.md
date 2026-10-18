# TrueDepth device checklist

Use this checklist for the hackathon device gate. Run it on the same iPhone 17 and app build throughout. This is prototype validation, not a clinical accuracy claim.

## Equipment

- iPhone 17 with the signed GripIt build.
- Phone clamp or tripod.
- Tape measure and distance marks at 25, 40, and 60 cm.
- Digital caliper or rigid metric ruler.
- Washable skin marker or small removable dots.
- Plain background and steady indoor lighting.
- Results sheet for ground truth and exported JSON values.

## Preflight

- [ ] Record the iPhone model, iOS version, app commit, and MediaPipe package resolution.
- [ ] Confirm the app is locked to portrait.
- [ ] Confirm camera permission text says frames and depth are not saved.
- [ ] Confirm denial produces a clear recovery path to Settings.
- [ ] Confirm an unsupported device shows an actionable TrueDepth message.
- [ ] Confirm the app does not request microphone or photo-library access.
- [ ] Confirm the preview is mirrored like a selfie, while landmarks remain attached to the correct physical joints.
- [ ] Confirm no photo, video, or depth file appears in Photos or Files after a scan.

## Guided scan

For each full scan:

- [ ] Select the physical hand before capture.
- [ ] Complete views in this exact order: palm, thumb side, back, pinky side.
- [ ] Keep all 21 landmarks visible.
- [ ] Confirm progress advances only for the highlighted view.
- [ ] Confirm low-confidence, missing-depth, wrong-hand, and wrong-view frames do not advance progress.
- [ ] Confirm each view reaches 8 accepted frames.
- [ ] Confirm the completed scan exports a `HandProfile`.

The export must contain:

- [ ] `schemaVersion` equal to `1.0.0`.
- [ ] Correct physical `handedness`.
- [ ] `units` equal to `millimeters`.
- [ ] `coordinateSystem` equal to `gripit-hand-v1`.
- [ ] Capture method `true-depth-mediapipe`.
- [ ] Calibration method `camera-intrinsics`.
- [ ] Required and captured views in the order palm, thumb-side, back, pinky-side.
- [ ] Coverage fraction `1.0`.
- [ ] All 21 named landmarks.
- [ ] Palm width and length.
- [ ] Three segments for each finger and thumb.

Palm thickness and finger diameter may be `null` in this prototype.

## Ground truth

Mark joint centers. Measure straight point-to-point distances. Do not follow the skin curve.

Record these values once for the selected hand:

- Palm width: index MCP center to pinky MCP center.
- Palm length: wrist landmark center to the midpoint of index MCP and pinky MCP.
- Index, middle, ring, and pinky: MCP to PIP, PIP to DIP, DIP to tip.
- Thumb: CMC to MCP, MCP to IP, IP to tip.

Also record each finger total as the sum of its three segments.

## Repeatable distance matrix

Measure from the front camera plane to the center of the palm. Keep the distance within 5 mm. Restart the scanner between runs. Do not discard the weaker repeat.

| Distance | Run 1 | Run 2 |
|---|---|---|
| 25 cm | Full four-view scan | Full four-view scan |
| 40 cm | Full four-view scan | Full four-view scan |
| 60 cm | Full four-view scan | Full four-view scan |

For each run, record scan time, retries, exported values, visible overlay problems, and rejection reasons.

Use these calculations:

- Accuracy error: `abs(scan - truth) / truth * 100`.
- Repeat difference: `abs(run1 - run2) / mean(run1, run2) * 100`.
- Cross-distance drift: `(largest distance mean - smallest distance mean) / overall mean * 100`.

## Prototype pass gates

- [ ] Six valid exports are produced without a crash.
- [ ] Every scan completes within two attempts.
- [ ] Handedness is correct in all exports.
- [ ] Mean palm width and palm length error is at most the larger of 8 mm or 10%.
- [ ] Mean total finger-length error is at most the larger of 8 mm or 10%.
- [ ] Individual segment error is at most the larger of 5 mm or 15%.
- [ ] Same-distance repeat difference for palm dimensions and total finger lengths is at most 5%.
- [ ] Same-distance repeat difference for one segment is at most the larger of 3 mm or 10%.
- [ ] Cross-distance drift for palm dimensions and total finger lengths is at most 8%.
- [ ] No view shows a consistent mirrored or rotated landmark offset.

## Not in this build

The app has no rigid-object or baseball QA measurement screen. Do not claim that those checks were run. A future debug tool can let a tester tap two aligned depth pixels and compare their projected separation with a caliper-measured object at 25, 40, and 60 cm.

## Done

- [ ] Attach all six JSON exports and the completed results sheet.
- [ ] Record every failure and retry. Do not report only successful attempts.
- [ ] Note whether package resolution, signing, camera permission, and physical-device validation passed.
- [ ] List any failed metric or visual alignment issue as a prototype limitation.
