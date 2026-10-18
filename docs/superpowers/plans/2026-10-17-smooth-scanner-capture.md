# Smooth scanner capture implementation plan

> Execute inline with test-first checkpoints using executing-plans.

**Goal:** Remove the handedness-confidence deadlock at the thumb-side step.

**Architecture:** A testable core identity tracker retains the initial palm
identity only across continuous spatial tracking. Requested-view pose matching
accepts measurable oblique side poses. The native processor keeps all existing
metric gates and reports the specific gate currently blocking capture.

**Tech stack:** Swift, SwiftUI, AVFoundation, MediaPipe, XCTest.

## Constraints

- Native front TrueDepth only, HandProfile 1.0.0 unchanged.
- Four ordered views, eight accepted observations per view.
- No invented depth, metric checks unchanged, local signing preserved.

## Task 1: Identity and pose regressions

- [ ] Add `HandIdentityTrackerTests.swift` covering confident palm lock,
  ambiguous side labels, wrong hand, abrupt jumps, multiple hands, and gaps.
- [ ] Add oblique-view tests in `CameraAlignmentTests.swift`.
- [ ] Run core tests and confirm the missing policy APIs fail.
- [ ] Implement `HandIdentityTracker.swift` and requested-view matching in
  `ScannerAdapterGeometry.swift`.
- [ ] Run core tests and require no failures.

## Task 2: Native gate integration and accurate instructions

- [ ] Expose a rejection status from `MeasurementStabilityGate.swift` with tests
  for moving, overlapping, noisy, settling, and accepted geometry.
- [ ] Integrate identity before assigning observation confidence in
  `ScannerViewModel.swift`. Reuse only the validated palm identity score.
- [ ] Update side instructions and show tracking-lock state in `ScannerView`.
- [ ] Add a full four-view policy/depth/stability/session regression.
- [ ] Run all core tests, native SDK type-check, and dependency wiring check.
- [ ] Review, commit, and push code without staging local signing changes.
