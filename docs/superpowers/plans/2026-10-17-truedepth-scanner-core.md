# TrueDepth Scanner Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a portable Swift package that turns calibrated hand landmark samples into the versioned `HandProfile` consumed by every later GripIt step.

**Architecture:** `GripItScannerCore` contains no AVFoundation, MediaPipe, SwiftUI, or Perceptron types. The host iOS app adapts synchronized TrueDepth and landmark results into plain Swift values. The package projects depth into metric camera coordinates, tracks required views, aggregates measurements, canonicalizes handedness, and exports contract-compatible JSON.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, Foundation, JSON `Codable`

## Global Constraints

- The package must compile for iOS 17 or later and macOS 13 or later.
- Physical lengths use millimeters.
- Confidence values use the inclusive range `0...1`.
- The hand coordinate system is `gripit-hand-v1`.
- Left-hand output is reflected into the same anatomical coordinate system as right-hand output.
- The package must not expose AVFoundation, MediaPipe, Core Video, Metal, SwiftUI, or Perceptron types.
- Unsupported major contract versions must be rejected.
- Missing measurements remain `nil` and are never silently invented.
- RGB and depth frames are not persisted in `HandProfile`.
- Perceptron may provide optional guidance annotations only. It is not a source of metric measurements.

---

## File Map

- `ios/GripItScannerCore/Package.swift`: package platforms, library target, checker executable, tests, and fixture resources.
- `ios/GripItScannerCore/Sources/GripItScannerCore/Contracts/HandProfile.swift`: v1 contract values and JSON codec.
- `ios/GripItScannerCore/Sources/GripItScannerCore/Geometry/MetricGeometry.swift`: plain 2D and 3D geometry values, depth projection, and handedness canonicalization.
- `ios/GripItScannerCore/Sources/GripItScannerCore/Capture/ScanObservation.swift`: provider-neutral landmarks, views, and accepted frame samples.
- `ios/GripItScannerCore/Sources/GripItScannerCore/Capture/CoverageTracker.swift`: four-view progress and next-view guidance.
- `ios/GripItScannerCore/Sources/GripItScannerCore/Measurement/HandMeasurementAggregator.swift`: robust medians and stable hand dimensions.
- `ios/GripItScannerCore/Sources/GripItScannerCore/ScannerSession.swift`: coordinates accepted samples into one `HandProfile`.
- `ios/GripItScannerCore/Sources/GripItScannerCore/Contracts/SampleHandProfiles.swift`: bundled simulator profile loader.
- `ios/GripItScannerCore/Sources/GripItScannerCore/Resources/hand-profile-average-right.json`: executable copy of the shared contract fixture.
- `ios/GripItScannerCore/Sources/GripItScannerCoreChecks/main.swift`: framework-free local verification executable.
- `ios/GripItScannerCore/Tests/GripItScannerCoreTests/ContractCompatibilityTests.swift`: contract decoding, version rejection, and round-trip tests.
- `ios/GripItScannerCore/Tests/GripItScannerCoreTests/MetricGeometryTests.swift`: depth projection and left-hand reflection tests.
- `ios/GripItScannerCore/Tests/GripItScannerCoreTests/CoverageTrackerTests.swift`: view progression and confidence rejection tests.
- `ios/GripItScannerCore/Tests/GripItScannerCoreTests/HandMeasurementAggregatorTests.swift`: robust aggregation and missing data tests.
- `ios/GripItScannerCore/Tests/GripItScannerCoreTests/ScannerSessionTests.swift`: complete and incomplete session tests.
- `docs/integration/ios-scanner-host.md`: Xcode integration boundary for the partner-owned app.
- `docs/integration/perceptron.md`: optional hackathon-track integration and safety boundary.

### Task 1: Swift package and executable HandProfile contract

**Files:**
- Create: `ios/GripItScannerCore/Package.swift`
- Create: `ios/GripItScannerCore/Sources/GripItScannerCore/Contracts/HandProfile.swift`
- Create: `ios/GripItScannerCore/Sources/GripItScannerCore/Contracts/SampleHandProfiles.swift`
- Create: `ios/GripItScannerCore/Sources/GripItScannerCore/Resources/hand-profile-average-right.json`
- Create: `ios/GripItScannerCore/Tests/GripItScannerCoreTests/ContractCompatibilityTests.swift`

**Interfaces:**
- Consumes: `docs/contracts/v1/fixtures/hand-profile-average-right.json`
- Produces: `HandProfile`, `HandMeasurements`, `CaptureMetadata`, `JSONValue`, and `HandProfileCodec`

- [ ] **Step 1: Create the package manifest and copy the shared fixture into test resources**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GripItScannerCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "GripItScannerCore", targets: ["GripItScannerCore"]),
        .executable(name: "GripItScannerCoreChecks", targets: ["GripItScannerCoreChecks"])
    ],
    targets: [
        .target(
            name: "GripItScannerCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "GripItScannerCoreChecks",
            dependencies: ["GripItScannerCore"]
        ),
        .testTarget(
            name: "GripItScannerCoreTests",
            dependencies: ["GripItScannerCore"]
        )
    ]
)
```

- [ ] **Step 2: Write failing contract tests**

```swift
func testSharedFixtureDecodesAndRoundTrips() throws {
    let profile = try SampleHandProfiles.averageRight()
    XCTAssertEqual(profile.schemaVersion, "1.0.0")
    XCTAssertEqual(profile.measurements.palm.widthMm, 82)
    XCTAssertEqual(try HandProfileCodec.decode(HandProfileCodec.encode(profile)), profile)
}

func testUnsupportedMajorVersionIsRejected() throws {
    let data = Data(#"{"schemaVersion":"2.0.0"}"#.utf8)
    XCTAssertThrowsError(try HandProfileCodec.decode(data))
}
```

- [ ] **Step 3: Run the tests and verify they fail because contract types do not exist**

Run: `cd ios/GripItScannerCore && swift test --filter ContractCompatibilityTests`

Expected: compilation fails with `cannot find 'HandProfileCodec' in scope`.

- [ ] **Step 4: Implement the v1 values and codec**

Implement exact `Codable`, `Equatable`, and `Sendable` structures for the fixture fields. Decode the top-level `schemaVersion` first. Accept only major version `1`. Configure dates as ISO 8601 strings to preserve the wire value. Represent unknown additive extension values with recursive `JSONValue` cases for string, number, boolean, object, array, and null.

- [ ] **Step 5: Run the contract tests**

Run: `cd ios/GripItScannerCore && swift test --filter ContractCompatibilityTests`

Expected: all contract tests pass.

- [ ] **Step 6: Commit**

```bash
git add ios/GripItScannerCore
git commit -m "feat: add Swift hand profile contract"
```

### Task 2: Metric projection and canonical coordinates

**Files:**
- Create: `ios/GripItScannerCore/Sources/GripItScannerCore/Geometry/MetricGeometry.swift`
- Create: `ios/GripItScannerCore/Tests/GripItScannerCoreTests/MetricGeometryTests.swift`

**Interfaces:**
- Consumes: `PixelPoint`, depth in meters, and `CameraIntrinsics`
- Produces: `MetricPoint3D`, `DepthProjector.project(pixel:depthMeters:intrinsics:)`, and `HandCanonicalizer.canonicalize(_:handedness:)`

- [ ] **Step 1: Write failing geometry tests**

```swift
func testProjectsDepthIntoMillimeters() throws {
    let point = try DepthProjector.project(
        pixel: PixelPoint(x: 420, y: 290),
        depthMeters: 0.5,
        intrinsics: CameraIntrinsics(fx: 500, fy: 500, cx: 320, cy: 240)
    )
    XCTAssertEqual(point, MetricPoint3D(xMm: 100, yMm: 50, zMm: 500))
}

func testLeftHandReflectsXOnly() {
    let point = MetricPoint3D(xMm: -12, yMm: 30, zMm: 4)
    XCTAssertEqual(
        HandCanonicalizer.canonicalize(point, handedness: .left),
        MetricPoint3D(xMm: 12, yMm: 30, zMm: 4)
    )
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `cd ios/GripItScannerCore && swift test --filter MetricGeometryTests`

Expected: compilation fails because `DepthProjector` is missing.

- [ ] **Step 3: Implement calibrated pinhole projection and validation**

Use `x = (u - cx) * z / fx`, `y = (v - cy) * z / fy`, and convert meters to millimeters. Reject non-finite values, non-positive focal lengths, and depth outside `0.12...1.2` meters with typed errors.

- [ ] **Step 4: Run the geometry tests**

Run: `cd ios/GripItScannerCore && swift test --filter MetricGeometryTests`

Expected: all geometry tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/GripItScannerCore/Sources/GripItScannerCore/Geometry ios/GripItScannerCore/Tests/GripItScannerCoreTests/MetricGeometryTests.swift
git commit -m "feat: add calibrated depth projection"
```

### Task 3: Provider-neutral observations and guided coverage

**Files:**
- Create: `ios/GripItScannerCore/Sources/GripItScannerCore/Capture/ScanObservation.swift`
- Create: `ios/GripItScannerCore/Sources/GripItScannerCore/Capture/CoverageTracker.swift`
- Create: `ios/GripItScannerCore/Tests/GripItScannerCoreTests/CoverageTrackerTests.swift`

**Interfaces:**
- Consumes: `ScanObservation(view:landmarks:frameConfidence:)`
- Produces: `CoverageTracker.accept(_:)`, `CoverageSnapshot`, and actionable `nextInstruction`

- [ ] **Step 1: Write failing coverage tests**

```swift
func testRequiresFourViewsInOrder() throws {
    var tracker = CoverageTracker(minimumFramesPerView: 2, minimumConfidence: 0.8)
    try tracker.accept(.fixture(view: .palm, confidence: 0.9))
    try tracker.accept(.fixture(view: .palm, confidence: 0.9))
    XCTAssertEqual(tracker.snapshot.currentView, .back)
    XCTAssertEqual(tracker.snapshot.fraction, 0.25)
}

func testRejectsLowConfidenceWithoutAdvancing() {
    var tracker = CoverageTracker(minimumFramesPerView: 2, minimumConfidence: 0.8)
    XCTAssertThrowsError(try tracker.accept(.fixture(view: .palm, confidence: 0.5)))
    XCTAssertEqual(tracker.snapshot.fraction, 0)
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `cd ios/GripItScannerCore && swift test --filter CoverageTrackerTests`

Expected: compilation fails because `CoverageTracker` is missing.

- [ ] **Step 3: Implement observations and deterministic coverage state**

Define the required order as palm, back, thumb side, pinky side. Accept only the current view. Count accepted frames only when frame and landmark confidence pass. Expose captured views, fraction, completion, and a plain-text next instruction.

- [ ] **Step 4: Run the coverage tests**

Run: `cd ios/GripItScannerCore && swift test --filter CoverageTrackerTests`

Expected: all coverage tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/GripItScannerCore/Sources/GripItScannerCore/Capture ios/GripItScannerCore/Tests/GripItScannerCoreTests/CoverageTrackerTests.swift
git commit -m "feat: add guided scan coverage state"
```

### Task 4: Robust dimensions and complete scanner session

**Files:**
- Create: `ios/GripItScannerCore/Sources/GripItScannerCore/Measurement/HandMeasurementAggregator.swift`
- Create: `ios/GripItScannerCore/Sources/GripItScannerCore/ScannerSession.swift`
- Create: `ios/GripItScannerCore/Tests/GripItScannerCoreTests/HandMeasurementAggregatorTests.swift`
- Create: `ios/GripItScannerCore/Tests/GripItScannerCoreTests/ScannerSessionTests.swift`

**Interfaces:**
- Consumes: accepted `ScanObservation` values with named metric landmarks
- Produces: `HandMeasurementAggregator.measure(_:)` and `ScannerSession.makeProfile(profileId:createdAt:)`

- [ ] **Step 1: Write failing aggregation tests**

```swift
func testMedianRejectsOneLargeOutlier() throws {
    let samples = [fixtureHand(scale: 1), fixtureHand(scale: 1.02), fixtureHand(scale: 8)]
    let measurements = try HandMeasurementAggregator().measure(samples)
    XCTAssertLessThan(measurements.palm.widthMm ?? 0, 100)
}

func testMissingRequiredLandmarksRemainAnError() {
    XCTAssertThrowsError(try HandMeasurementAggregator().measure([[:]]))
}
```

- [ ] **Step 2: Write failing session tests**

```swift
func testIncompleteSessionCannotExport() {
    var session = ScannerSession()
    XCTAssertThrowsError(try session.makeProfile(profileId: "profile-1", createdAt: "2026-10-17T00:00:00Z"))
}

func testCompletedSessionExportsV1Profile() throws {
    var session = ScannerSession(minimumFramesPerView: 1)
    for view in ScanView.requiredOrder { try session.accept(.fixture(view: view, confidence: 1)) }
    let profile = try session.makeProfile(profileId: "profile-1", createdAt: "2026-10-17T00:00:00Z")
    XCTAssertEqual(profile.coordinateSystem, "gripit-hand-v1")
    XCTAssertEqual(profile.capture.coverage.fraction, 1)
}
```

- [ ] **Step 3: Run the tests and verify they fail**

Run: `cd ios/GripItScannerCore && swift test --filter 'HandMeasurementAggregatorTests|ScannerSessionTests'`

Expected: compilation fails because the aggregator and session are missing.

- [ ] **Step 4: Implement measurements and session export**

Compute Euclidean segment lengths for thumb, index, middle, ring, and pinky. Compute palm width from index MCP to pinky MCP. Compute palm length from wrist to the midpoint of index and pinky MCP. Use a median across frames. Build capture metadata with method `true-depth-mediapipe`, required and captured views, calibration method `camera-intrinsics`, and the median accepted-frame confidence.

- [ ] **Step 5: Run all native package tests**

Run: `cd ios/GripItScannerCore && swift test`

Expected: all native tests pass.

- [ ] **Step 6: Commit**

```bash
git add ios/GripItScannerCore
git commit -m "feat: aggregate scans into hand profiles"
```

### Task 5: Host integration and optional Perceptron boundary

**Files:**
- Create: `docs/integration/ios-scanner-host.md`
- Create: `docs/integration/perceptron.md`
- Modify: `docs/workstreams/step-1-truedepth-scanner.md`

**Interfaces:**
- Consumes: synchronized AVFoundation frames, MediaPipe results, and optional Perceptron responses from the host app
- Produces: an exact adapter checklist and ownership boundary

- [ ] **Step 1: Document the Xcode host adapter**

Specify that the app target owns camera permission, `AVCaptureDataOutputSynchronizer`, depth-map access, MediaPipe live-stream callbacks, preview rendering, and local-package linking. Map those results into `CameraIntrinsics`, `PixelPoint`, `MetricPoint3D`, `NamedLandmark`, and `ScanObservation`.

- [ ] **Step 2: Document the Perceptron option**

Define two supported uses: scan-frame QA with an instruction such as `rotate toward thumb side`, and post-capture throw-video analysis for ball release and motion events. State that the API call must run through a server-side proxy so the API key is not embedded in iOS. State that model output is advisory and cannot write metric landmark coordinates or change `HandProfile.measurements`.

- [ ] **Step 3: Run native and web regression tests**

Run: `cd ios/GripItScannerCore && swift test`

Expected: all native tests pass.

Run: `npm test`

Expected: all existing web tests pass.

- [ ] **Step 4: Commit**

```bash
git add docs/integration docs/workstreams/step-1-truedepth-scanner.md
git commit -m "docs: define iOS scanner integration boundary"
```

### Task 6: Final verification

**Files:**
- Verify only

**Interfaces:**
- Consumes: all package source, tests, fixtures, and documentation
- Produces: verified branch ready for Xcode integration

- [ ] **Step 1: Confirm the package has no forbidden framework imports**

Run: `rg -n 'import (AVFoundation|MediaPipeTasksVision|CoreVideo|Metal|SwiftUI)' ios/GripItScannerCore/Sources`

Expected: no matches.

- [ ] **Step 2: Confirm no placeholder language remains**

Run: `rg -n 'PLACEHOLDER_MARKER|INCOMPLETE_IMPLEMENTATION' ios/GripItScannerCore docs/integration`

Expected: no matches.

- [ ] **Step 3: Run the complete verification set**

Run: `cd ios/GripItScannerCore && swift test && cd ../../.. && npm test && npm run build`

Expected: all Swift tests pass, all web tests pass, and the Vite production build succeeds.

- [ ] **Step 4: Inspect the final diff and branch status**

Run: `git status --short && git log --oneline --decorate -6`

Expected: clean worktree and focused scanner commits on `feature/step-1-truedepth-scanner`.
