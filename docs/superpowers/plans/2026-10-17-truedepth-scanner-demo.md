# TrueDepth Scanner Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the iOS WebView entry point with a native scanner that measures one hand from synchronized front-camera RGB and TrueDepth frames and exports a versioned `HandProfile`.

**Architecture:** The app target owns AVFoundation, MediaPipeTasksVision, frame synchronization, preview rendering, and SwiftUI. A local `GripItScannerCore` package owns provider-neutral metric geometry, four-view progression, landmark coverage, aggregation, and JSON encoding. The app uses synchronous MediaPipe video-mode inference on a serial processing queue so every landmark result stays paired with the exact synchronized depth frame.

**Tech Stack:** Swift 6 package, SwiftUI, AVFoundation, Core Video, MediaPipeTasksVision 1.1.1, XCTest, iOS 17+

## Global Constraints

- Install directly from Xcode onto an iPhone 17. Do not add App Store or TestFlight configuration.
- Do not start or use the existing WebView scanner.
- Do not add the rendered hand, baseball model, pitch selection, grip instructions, throw entry, or accounts.
- Keep analysis buffers unmirrored. Mirror only the visible selfie preview.
- Require exactly 21 named landmarks for an accepted `ScanObservation`.
- Reject depth outside `0.12...1.2` meters.
- Do not save or upload RGB frames, depth maps, or MediaPipe results.
- Keep `HandProfile` schema version `1.0.0` and coordinate system `gripit-hand-v1`.
- Required view order is palm, thumb side, back, then pinky side.
- Simulator mode must load the bundled sample profile without camera access.

---

## File Map

- `ios/GripItScannerCore/`: local copy of the provider-neutral scanner package.
- `ios/GripItScannerCore/Sources/GripItScannerCore/Capture/LandmarkCoverageTracker.swift`: per-joint sample counts for the skeletal fill map.
- `ios/GripIt/GripItApp.swift`: native scanner entry point.
- `ios/GripIt/Scanner/ScannerViewModel.swift`: scanner state machine and session ownership.
- `ios/GripIt/Scanner/ScannerView.swift`: minimal scanning and results UI.
- `ios/GripIt/Scanner/CameraPreview.swift`: mirrored `AVCaptureVideoPreviewLayer` wrapper.
- `ios/GripIt/Scanner/TrueDepthCaptureService.swift`: camera discovery, synchronized RGB/depth capture, and diagnostics.
- `ios/GripIt/Scanner/DepthLandmarkMapper.swift`: coordinate mapping, depth neighborhood sampling, and intrinsic scaling.
- `ios/GripIt/Scanner/HandLandmarkerService.swift`: pinned MediaPipe adapter.
- `ios/GripIt/Scanner/HandLandmarkAdapter.swift`: landmark naming, handedness normalization, view classification, and observation construction.
- `ios/GripIt/Scanner/SkeletonCoverageView.swift`: compact 21-joint coverage visualization.
- `ios/GripIt/Resources/hand_landmarker.task`: bundled MediaPipe hand model.
- `ios/GripItTests/DepthLandmarkMapperTests.swift`: pure coordinate and depth tests.
- `ios/GripItTests/HandLandmarkAdapterTests.swift`: handedness and view-classification tests.
- `ios/GripIt.xcodeproj/project.pbxproj`: source, resources, local package, and MediaPipe package references.
- `ios/README.md`: direct-device setup and validation steps.

### Task 1: Bring in the scanner core and add landmark coverage

**Files:**
- Create: `ios/GripItScannerCore/**`
- Create: `ios/GripItScannerCore/Sources/GripItScannerCore/Capture/LandmarkCoverageTracker.swift`
- Create: `ios/GripItScannerCore/Tests/GripItScannerCoreTests/LandmarkCoverageTrackerTests.swift`
- Modify: `ios/GripItScannerCore/Sources/GripItScannerCore/Capture/ScanObservation.swift`
- Modify: `ios/GripItScannerCore/Sources/GripItScannerCore/Capture/CoverageTracker.swift`

**Interfaces:**
- Produces: `LandmarkCoverageTracker.record(validLandmarks:view:)`, `LandmarkCoverageSnapshot`, and the view order `[.palm, .thumbSide, .back, .pinkySide]`.

- [ ] **Step 1: Copy the verified scanner package from `feature/step-1-truedepth-scanner`**

Copy the complete `ios/GripItScannerCore` directory. Exclude `.build`.

- [ ] **Step 2: Write failing per-landmark coverage tests**

```swift
func testCoverageCountsValidLandmarksWithoutCompletingMissingOnes() throws {
    var tracker = LandmarkCoverageTracker(minimumSamplesPerLandmark: 2)
    tracker.record(validLandmarks: [.wrist, .indexMCP], view: .palm)
    tracker.record(validLandmarks: [.wrist], view: .palm)
    XCTAssertEqual(tracker.snapshot.counts[.wrist], 2)
    XCTAssertEqual(tracker.snapshot.counts[.indexMCP], 1)
    XCTAssertEqual(tracker.snapshot.fraction(for: .wrist), 1)
    XCTAssertEqual(tracker.snapshot.fraction(for: .indexMCP), 0.5)
}
```

- [ ] **Step 3: Run the focused test and verify failure**

Run: `cd ios/GripItScannerCore && swift test --filter LandmarkCoverageTrackerTests`

Expected: compilation fails because `LandmarkCoverageTracker` does not exist.

- [ ] **Step 4: Implement the tracker**

```swift
public struct LandmarkCoverageSnapshot: Equatable, Sendable {
    public let minimumSamplesPerLandmark: Int
    public let counts: [HandLandmarkName: Int]

    public func fraction(for landmark: HandLandmarkName) -> Double {
        min(1, Double(counts[landmark, default: 0]) / Double(minimumSamplesPerLandmark))
    }
}

public struct LandmarkCoverageTracker: Sendable {
    public let minimumSamplesPerLandmark: Int
    private var counts: [HandLandmarkName: Int] = [:]

    public init(minimumSamplesPerLandmark: Int = 3) {
        self.minimumSamplesPerLandmark = max(1, minimumSamplesPerLandmark)
    }

    public mutating func record(validLandmarks: Set<HandLandmarkName>, view: ScanView) {
        for name in validLandmarks { counts[name, default: 0] += 1 }
    }

    public var snapshot: LandmarkCoverageSnapshot {
        LandmarkCoverageSnapshot(
            minimumSamplesPerLandmark: minimumSamplesPerLandmark,
            counts: counts
        )
    }
}
```

- [ ] **Step 5: Change and test the natural rotation order**

Set `ScanView.requiredOrder` to `[.palm, .thumbSide, .back, .pinkySide]`. Update coverage tests to assert this exact order and matching instructions.

- [ ] **Step 6: Run scanner-core checks**

Run: `cd ios/GripItScannerCore && swift test`

Expected: all scanner-core tests pass under full Xcode. If only Command Line Tools are active, run `swift run --disable-sandbox GripItScannerCoreChecks` and record the XCTest limitation.

- [ ] **Step 7: Commit**

```bash
git add ios/GripItScannerCore
git commit -m "feat: add scanner core and landmark coverage"
```

### Task 2: Build pure depth and landmark adapters

**Files:**
- Create: `ios/GripIt/Scanner/DepthLandmarkMapper.swift`
- Create: `ios/GripIt/Scanner/HandLandmarkAdapter.swift`
- Create: `ios/GripItTests/DepthLandmarkMapperTests.swift`
- Create: `ios/GripItTests/HandLandmarkAdapterTests.swift`

**Interfaces:**
- Produces: `DepthLandmarkMapper.sampleMedianDepth`, `DepthLandmarkMapper.scaledIntrinsics`, `HandLandmarkAdapter.names`, `physicalHandedness`, and `classifyView`.

- [ ] **Step 1: Write failing depth sampling tests**

```swift
func testMedianDepthIgnoresHolesAndOutOfRangeValues() {
    let values: [Float] = [.nan, 0, 0.39, 0.40, 0.41, 2.0]
    XCTAssertEqual(
        DepthLandmarkMapper.medianValidDepth(values, allowed: 0.12 ... 1.2),
        0.40,
        accuracy: 0.0001
    )
}
```

- [ ] **Step 2: Write failing handedness and view tests**

```swift
func testPhysicalHandednessRejectsUnexpectedHand() throws {
    XCTAssertThrowsError(
        try HandLandmarkAdapter.physicalHandedness(
            mediaPipeLabel: "Left",
            expected: .right,
            convention: .subjectHand
        )
    )
}

func testViewClassifierUsesPalmNormalAndKnuckleDirection() {
    XCTAssertEqual(HandLandmarkAdapter.classifyView(palmNormalZ: 0.8, lateralX: 0.1), .palm)
    XCTAssertEqual(HandLandmarkAdapter.classifyView(palmNormalZ: -0.8, lateralX: 0.1), .back)
    XCTAssertEqual(HandLandmarkAdapter.classifyView(palmNormalZ: 0.1, lateralX: 0.8), .thumbSide)
    XCTAssertEqual(HandLandmarkAdapter.classifyView(palmNormalZ: 0.1, lateralX: -0.8), .pinkySide)
}
```

- [ ] **Step 3: Run tests and verify they fail**

Run: `xcodebuild test -project ios/GripIt.xcodeproj -scheme GripIt -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: compilation fails because the adapter types do not exist.

- [ ] **Step 4: Implement depth mapping as pure functions**

Implement a median filter over a 3-by-3 neighborhood. Ignore nonfinite values, zero, and values outside `0.12...1.2`. Scale `fx`, `fy`, `cx`, and `cy` independently from calibration reference dimensions to depth-map dimensions. Return `nil` when no valid depth exists.

- [ ] **Step 5: Implement landmark naming and handedness normalization**

Map indices `0...20` to `HandLandmarkName.allCases` in MediaPipe order. Define `LabelConvention.subjectHand` and `LabelConvention.mirroredViewer`. Reject an observed physical hand that differs from the selected throwing hand.

- [ ] **Step 6: Implement deterministic view classification**

Use wrist, index MCP, middle MCP, and pinky MCP to derive a palm normal. Classify front and back when `abs(normal.z) >= 0.55`; otherwise classify the lateral direction from the projected index-to-pinky vector. Return the expected current view only when the classification agrees.

- [ ] **Step 7: Run adapter tests**

Run: `xcodebuild test -project ios/GripIt.xcodeproj -scheme GripIt -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: all adapter tests pass.

- [ ] **Step 8: Commit**

```bash
git add ios/GripIt/Scanner ios/GripItTests
git commit -m "feat: add depth and hand landmark adapters"
```

### Task 3: Add synchronized TrueDepth capture and MediaPipe

**Files:**
- Create: `ios/GripIt/Scanner/TrueDepthCaptureService.swift`
- Create: `ios/GripIt/Scanner/HandLandmarkerService.swift`
- Create: `ios/GripIt/Resources/hand_landmarker.task`
- Modify: `ios/GripIt.xcodeproj/project.pbxproj`
- Modify: `ios/GripIt/Info.plist`

**Interfaces:**
- Produces: `TrueDepthCaptureService.start()`, `stop()`, `session`, and `onFrame`; `HandLandmarkerService.detect(pixelBuffer:timestamp:)`.

- [ ] **Step 1: Add pinned package dependencies**

Add local package `GripItScannerCore` at `ios/GripItScannerCore`. Add `https://github.com/google-ai-edge/mediapipe` pinned to exact version `1.1.1`. Link `GripItScannerCore` and `MediaPipeTasksVision` to the GripIt target.

- [ ] **Step 2: Bundle the existing model once**

Copy `public/mediapipe/hand_landmarker.task` to `ios/GripIt/Resources/hand_landmarker.task`. Verify its SHA-256 is `fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1` and add it to the resources build phase.

- [ ] **Step 3: Implement camera capability discovery**

Discover `.builtInTrueDepthCamera` at `.front`. Select a video format with a supported depth format, prefer `kCVPixelFormatType_DepthFloat32`, and configure matching `AVCaptureVideoDataOutput` and `AVCaptureDepthDataOutput` objects on one session.

- [ ] **Step 4: Synchronize frame delivery**

Create `AVCaptureDataOutputSynchronizer(dataOutputs:)`. On a dedicated serial queue, reject dropped video or depth data and convert depth to Float32 before delivering:

```swift
struct SynchronizedCaptureFrame {
    let pixelBuffer: CVPixelBuffer
    let depthData: AVDepthData
    let timestamp: CMTime
}
```

- [ ] **Step 5: Implement MediaPipe video-mode inference**

Load `hand_landmarker.task` from the app bundle. Configure `HandLandmarkerOptions` with `.video`, `numHands = 1`, and confidence thresholds `0.7`. Create `MPImage(pixelBuffer:orientation:)` from the unmirrored buffer. Call `detect(videoFrame:timestampInMilliseconds:)` on the capture processing queue.

- [ ] **Step 6: Add privacy copy**

Set `NSCameraUsageDescription` to: `GripIt uses the front TrueDepth camera to measure your hand on this device. Images and depth maps are not saved or uploaded.`

- [ ] **Step 7: Verify project resolution**

Run: `xcodebuild -resolvePackageDependencies -project ios/GripIt.xcodeproj -scheme GripIt`

Expected: MediaPipeTasksVision 1.1.1 and the local scanner package resolve.

- [ ] **Step 8: Commit**

```bash
git add ios/GripIt.xcodeproj ios/GripIt/Info.plist ios/GripIt/Resources ios/GripIt/Scanner
git commit -m "feat: add synchronized TrueDepth hand capture"
```

### Task 4: Implement scanner state and skeletal coverage UI

**Files:**
- Create: `ios/GripIt/Scanner/ScannerViewModel.swift`
- Create: `ios/GripIt/Scanner/ScannerView.swift`
- Create: `ios/GripIt/Scanner/CameraPreview.swift`
- Create: `ios/GripIt/Scanner/SkeletonCoverageView.swift`
- Modify: `ios/GripIt/GripItApp.swift`
- Modify: `ios/GripIt.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: synchronized frames, `HandLandmarkerService`, `ScannerSession`, and `LandmarkCoverageTracker`.
- Produces: a native scanner-only app entry point and exported `HandProfile` data.

- [ ] **Step 1: Define explicit UI states**

```swift
enum ScannerScreenState: Equatable {
    case chooseHand
    case requestingPermission
    case unsupported(String)
    case scanning
    case complete(HandProfile)
    case failed(String)
}
```

- [ ] **Step 2: Implement the view model state machine**

Own one `ScannerSession`, one `LandmarkCoverageTracker`, and one capture service. For every frame, update preview landmarks and diagnostic counts. Only call `session.accept` when all 21 landmarks have valid metric depth, handedness matches, and the classified view equals `session.coverage.snapshot.currentView`.

- [ ] **Step 3: Implement instruction copy**

Use short states: `Show your palm`, `Turn toward your thumb`, `Show the back of your hand`, `Turn toward your pinky`, `Move closer`, `Move farther away`, `Keep your whole hand visible`, and `Hold still`.

- [ ] **Step 4: Implement the mirrored preview**

Wrap `AVCaptureVideoPreviewLayer` in `UIViewRepresentable`. Set `.resizeAspectFill` and mirror only the preview connection. Draw landmarks in the same mirrored view coordinate space without modifying analysis coordinates.

- [ ] **Step 5: Implement skeletal coverage**

Draw 21 circles and MediaPipe hand connections in a fixed normalized coordinate template. Use gray below 0.25, amber from 0.25 to below 1.0, and green at 1.0. Fill a segment using the lower endpoint fraction.

- [ ] **Step 6: Implement results and export**

Show palm width, palm length, finger segment lengths, accepted view counts, coverage summary, and scan confidence. Write encoded `HandProfile` data to a temporary JSON file and present `UIActivityViewController` for Save to Files or AirDrop.

- [ ] **Step 7: Implement Simulator sample mode**

When `targetEnvironment(simulator)` is true, show `Load sample scan`. Decode `SampleHandProfiles.averageRight()` and move directly to results without starting AVFoundation.

- [ ] **Step 8: Replace the app entry point**

Set `GripItApp.body` to `ScannerView()`. Do not initialize `StudioModel`, `LocalAssetServer`, or `StudioWebView`.

- [ ] **Step 9: Run the simulator build and tests**

Run: `xcodebuild test -project ios/GripIt.xcodeproj -scheme GripIt -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: build succeeds, unit tests pass, and sample mode reaches results.

- [ ] **Step 10: Commit**

```bash
git add ios/GripIt ios/GripItTests ios/GripIt.xcodeproj
git commit -m "feat: add native guided hand scanner UI"
```

### Task 5: Direct iPhone installation and physical validation handoff

**Files:**
- Modify: `ios/README.md`
- Create: `docs/testing/truedepth-device-checklist.md`

**Interfaces:**
- Produces: reproducible Xcode installation and device test instructions for an iPhone 17.

- [ ] **Step 1: Replace WebView setup instructions**

Document that `npm run ios:prepare` is no longer required for the scanner demo. Instruct the tester to install full Xcode, open `ios/GripIt.xcodeproj`, select their Apple ID team, connect and trust the iPhone, select it as the run destination, and press Run.

- [ ] **Step 2: Add the physical checklist**

Record camera format, RGB resolution, depth resolution, depth pixel format, measurement distance, valid landmarks, accepted frames, ground-truth palm width, baseball diameter estimate, exported values, and repeated-scan variation.

- [ ] **Step 3: Run all locally available verification**

Run:

```bash
npm test
npm run build
cd ios/GripItScannerCore && swift run --disable-sandbox GripItScannerCoreChecks
git diff --check
```

Expected: 33 web tests pass, the production web build passes, scanner checks pass, and Git reports no whitespace errors.

- [ ] **Step 4: Run device validation in Xcode**

Expected on the iPhone 17: permission prompt appears once, the TrueDepth camera starts, all four views can complete, the results screen appears, and JSON exports through the share sheet. Record any unavailable depth format or coordinate mismatch instead of hiding it.

- [ ] **Step 5: Commit**

```bash
git add ios/README.md docs/testing/truedepth-device-checklist.md
git commit -m "docs: add direct iPhone scanner test guide"
```
