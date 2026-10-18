# GripIt Four-Workstream Design

## Goal

Build the four product steps in parallel without coupling later work to the implementation details of the TrueDepth scanner.

## Workstreams

1. Step 1 captures a hand and produces a versioned `HandProfile`.
2. Step 2 combines a `HandProfile` with a `PitchDefinition` and produces a `GripPlan` for the arcade-style viewer.
3. Step 3 captures and validates a `ThrowRecord` from Rapsodo values.
4. Step 4 combines a `GripPlan` and one or more `ThrowRecord` values to produce a `FocusAssessment`.

Each workstream consumes contracts and fixtures. No downstream workstream reads camera frames, MediaPipe landmarks, AVFoundation objects, React component state, or another workstream's private implementation.

## Shared contract rules

- Every persisted payload includes `schemaVersion` using semantic versioning.
- Version `1.x` changes are additive. Existing required fields cannot change meaning.
- Physical lengths use millimeters.
- Angles use radians.
- Confidence values use the inclusive range `0...1`.
- Timestamps use ISO 8601 UTC strings.
- Unknown measurements use `null`. They are not guessed silently.
- Each payload includes an `extensions` object for namespaced experimental data.
- Fixture IDs begin with `sample-`. Production IDs must not use that prefix.

## Hand coordinate system

`gripit-hand-v1` is anatomical and canonicalized so downstream math is identical for left and right hands.

- Origin: wrist landmark.
- Positive X: from the pinky side toward the thumb side.
- Positive Y: from the wrist toward the fingertips.
- Positive Z: out through the palm-facing surface.
- Left-hand scanner output is reflected into this canonical coordinate system.
- The physical hand remains available through the separate `handedness` field.

## Step 1: TrueDepth scanner

The native iOS scanner uses AVFoundation to capture synchronized RGB and TrueDepth data. MediaPipe identifies named hand landmarks. The scanner lifts accepted landmarks into metric XYZ coordinates using the depth map and camera calibration. A coverage state machine guides the user through palm, back, thumb-side, and pinky-side views.

TrueDepth is the metric source. MediaPipe is the semantic landmark source. A baseball may be used as a validation reference but is not required for scale on supported TrueDepth devices. Unsupported devices may continue using the existing web scanner and baseball reference.

The scanner fits measurements to a stable profile. It does not generate pitch poses, throw advice, or a final mesh.

## Step 2: Grip model and viewer

The viewer consumes a fixture or real `HandProfile`. It builds a clean stylized hand from proportions rather than displaying raw scan points. A `PitchDefinition` describes ball orientation, finger-pad contact regions, seam relationships, pressure, support fingers, palm depth, and release instructions.

The grip solver produces a `GripPlan` containing the ball transform, hand joint transforms, contact regions, instruction zones, fit confidence, and unresolved constraints. The renderer remains replaceable. Three.js and React Three Fiber are the first target.

## Step 3: Throw entry

Throw entry owns forms, units, range checks, sample-data labeling, and session grouping. It produces `ThrowRecord` values. It does not infer which finger caused a result.

## Step 4: Focus assessment

The assessment engine consumes `GripPlan` and `ThrowRecord` values. It produces colored zones, confidence, a reason, and one suggested adjustment. It supports a `not-grip` result when the available measurements do not justify grip advice.

Rules remain data-driven so coaching thresholds can change without changing the 3D renderer.

## Error handling

- Missing required contract fields are rejected at boundaries.
- Unsupported major versions are rejected with an actionable message.
- Optional measurements remain `null` and reduce confidence.
- Low scan coverage never presents as a completed personalized profile.
- Unreachable grip contacts appear as unresolved constraints.
- Invalid throw values remain in the form and show field-level errors.
- Assessments always include the inputs and rule version that produced them.

## Testing

- Contract fixtures must decode in Swift and TypeScript.
- Scanner math uses recorded or synthetic depth fixtures in unit tests.
- Grip generation runs against small, average, large, and left-hand profiles.
- Throw validation covers boundaries and missing optional values.
- Assessment rules use deterministic fixtures and expose confidence.
- Each workstream runs the existing web tests before integration.

## Branches

- `feature/step-1-truedepth-scanner`
- `feature/step-2-grip-model-viewer`
- `feature/step-3-throw-entry`
- `feature/step-4-focus-assessment`

All four branches start from the same shared foundation commit. Contract changes require coordination across all active branches.
