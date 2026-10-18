# Step 1: TrueDepth Scanner

## Branch

`feature/step-1-truedepth-scanner`

## Goal

Build a native iOS scanner prototype that captures one open throwing hand and exports a versioned `HandProfile`. This workstream owns capture quality and measurements. It does not own pitch posing, Rapsodo entry, or coaching feedback.

## Product context

Read:

- `PRODUCT.md`
- `handInstructions.md`
- `docs/superpowers/specs/2026-10-17-gripit-four-workstream-design.md`
- `docs/contracts/v1/README.md`
- `README.md` for the existing web scanner

The current browser scanner uses MediaPipe and a 73 mm baseball to estimate scale. The native prototype uses TrueDepth as the metric source and MediaPipe as the semantic landmark source.

## Required input and output

The scanner consumes synchronized RGB and depth frames from the front TrueDepth camera. It produces the `HandProfile` boundary defined in `docs/contracts/v1/README.md`.

The scanner must not expose AVFoundation, MediaPipe, Core Video, or Metal types across that boundary.

## Recommended implementation

- Reusable core package at `ios/GripItScannerCore`.
- SwiftUI scan flow.
- AVFoundation `builtInTrueDepthCamera`.
- `AVCaptureDataOutputSynchronizer` for RGB and depth.
- MediaPipeTasksVision in live-stream mode.
- Camera intrinsics for metric XYZ reconstruction.
- Coverage states: palm, back, thumb side, pinky side.
- A fixture-driven simulator mode because TrueDepth is unavailable in Simulator.
- JSON export using Swift `Codable`.
- Optional Perceptron scan-QA sidecar through a server proxy.

The Xcode app shell is owned separately. Follow `docs/integration/ios-scanner-host.md` for the boundary. Perceptron guidance is described in `docs/integration/perceptron.md` and never replaces metric depth or landmark measurements.

## Scope

- Device capability check.
- Camera permission and unavailable-state UI.
- Synchronized frame capture.
- One target hand only.
- Named landmark detection.
- Depth sampling and confidence rejection.
- Canonical left/right coordinate conversion.
- Guided view coverage.
- Measurement aggregation.
- `HandProfile` preview and JSON export.
- Unit tests for contracts, coordinates, coverage, and aggregation.

## Out of scope

- Photorealistic reconstruction.
- Pitch selection.
- Grip solving.
- Baseball seam alignment.
- Throw entry.
- Focus assessment.
- Uploading scan video.
- Claiming clinical or millimeter-perfect accuracy.

## Acceptance criteria

- Runs on a physical TrueDepth-capable iPhone.
- Shows an actionable unsupported-device state.
- Simulator mode loads `hand-profile-average-right.json`.
- Guides the user through all four required views.
- Rejects missing, low-confidence, or out-of-range depth samples.
- Produces millimeter measurements in `gripit-hand-v1`.
- Canonicalizes left and right hands consistently.
- Exports JSON compatible with the shared fixture shape.
- Stores no RGB or depth frame after the scan ends.
- Native tests and existing web tests pass.

## Coordination rules

Do not rename or reinterpret shared v1 contract fields without coordinating all four branches. New experimental scanner values belong under a namespaced key in `extensions`.

