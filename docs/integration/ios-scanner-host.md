# iOS Scanner Host Integration

## Ownership

The partner-owned Xcode app owns camera capture, permission UI, previews, and third-party SDKs. `ios/GripItScannerCore` owns scanner math and the exported `HandProfile`.

Add `ios/GripItScannerCore` as a local Swift package. Link the `GripItScannerCore` library to the iOS app target. Do not copy the package source into the app target.

## Device requirements

- iOS 17 or later.
- A front `builtInTrueDepthCamera` for metric scanning.
- A clear unsupported-device screen when that camera is missing.
- Simulator mode loads `try SampleHandProfiles.averageRight()` from the package.

## Camera adapter

The app target should create:

- `AVCaptureDevice` using `builtInTrueDepthCamera` and front position.
- `AVCaptureVideoDataOutput` for RGB frames.
- `AVCaptureDepthDataOutput` for depth frames.
- `AVCaptureDataOutputSynchronizer` for aligned timestamps.

### Coordinate transform order

Keep analysis coordinates separate from the mirrored preview. Record the exact transform used to prepare the MediaPipe input as `sensorToModel`.

For each synchronized frame:

1. Reject dropped RGB or depth data.
2. Convert the depth map to `kCVPixelFormatType_DepthFloat32` when needed.
3. Read `AVCameraCalibrationData.intrinsicMatrix` and `intrinsicMatrixReferenceDimensions`.
4. Run MediaPipe Hand Landmarker in live-stream mode on the RGB frame.
5. Convert each normalized landmark to a MediaPipe-input pixel coordinate.
6. Apply `sensorToModel.inverted()` to recover the unmirrored RGB sensor coordinate. This reverses model rotation, mirror, resize, and crop in the opposite order from which they were applied.
7. Map the RGB sensor coordinate into the depth-data reference space. Use the synchronized depth calibration and alignment. Do not reuse the preview-layer transform.
8. Scale `fx`, `fy`, `cx`, and `cy` from `intrinsicMatrixReferenceDimensions` to the actual depth-map width and height.
9. Sample a small neighborhood around the mapped depth pixel. Use the median of valid depth values. Reject holes and depths outside `0.12...1.2` meters.
10. Call `DepthProjector.project(pixel:depthMeters:intrinsics:)`.
11. Build one `NamedLandmark` for each MediaPipe landmark.
12. Build `ScanObservation` and pass it to `ScannerSession.accept(_:)`.

The RGB buffer sent to MediaPipe must not be mirrored merely to match the selfie preview. Mirror only the displayed preview. If the MediaPipe adapter applies orientation or crop, preserve that transform and invert it before depth lookup.

### Handedness rule

Ask the user which hand they throw with before scanning. Store that as `expectedHandedness`. Use it as the physical handedness passed into `ScanObservation` only after the MediaPipe result agrees.

Handedness behavior differs between legacy MediaPipe Hands and versions of MediaPipe Tasks. Legacy Hands documents a mirrored-input assumption and requires swapping labels for unmirrored input. The iOS Tasks API does not support mirrored image orientations. Pin the exact `MediaPipeTasksVision` version in the Xcode project and test its label behavior with one known right-hand image and one known left-hand image.

The adapter must implement one explicit normalization function:

```swift
func physicalHandedness(
    mediaPipeLabel: String,
    inputWasMirrored: Bool,
    labelConvention: LabelConvention
) throws -> Handedness
```

For the selected SDK and model, encode whether an unmirrored `Left` means the subject's left hand or must be swapped. Reject the frame when the normalized result does not equal `expectedHandedness`. Never pass a raw MediaPipe label directly into `ScanObservation`.

References: [MediaPipe Hand Landmarker for iOS](https://developers.google.com/edge/mediapipe/solutions/vision/hand_landmarker/ios) and [legacy handedness convention](https://github.com/google-ai-edge/mediapipe/blob/master/docs/solutions/hands.md#multi_handedness).

The adapter maps MediaPipe's 21 landmarks directly to `HandLandmarkName`. No AVFoundation, Core Video, MediaPipe, or Metal value crosses into the package.

## Guided UI

Read `session.coverage.snapshot` after each accepted or rejected frame.

- `currentView` selects the silhouette and highlighted unfilled region.
- `acceptedFramesInCurrentView / minimumFramesPerView` drives fill within that view.
- `fraction` drives continuous overall completion, including partial progress within a view.
- `nextInstruction` supplies the fallback text prompt.
- A rejected frame leaves progress unchanged.

The initial sequence is palm, back, thumb side, then pinky side. The app may animate the target hand. It must not change the required order without changing scanner-core tests.

## Export

After coverage completes, call:

```swift
let profile = try session.makeProfile(
    profileId: UUID().uuidString,
    createdAt: ISO8601DateFormatter().string(from: Date())
)
let data = try HandProfileCodec.encode(profile)
```

The resulting JSON is the only Step 1 value required by Steps 2, 3, and 4. Do not persist RGB frames, depth maps, or MediaPipe result objects after the scan ends.

## Baseball reference

TrueDepth supplies metric depth, so a baseball is not required for scale. It is still useful as an optional QA reference:

- Confirm that the detected baseball diameter is close to 73 mm.
- Warn about a likely depth-alignment or intrinsics error when it is not.
- Use the ball as a visual anchor in the hackathon demo.

Do not reject every TrueDepth scan merely because the baseball is missing. The browser fallback still requires the baseball because monocular RGB does not provide absolute scale.

## Physical-device checks

- Confirm preview and landmark coordinates stay aligned in portrait orientation.
- Feed synthetic normalized points at the four image corners and center through the adapter. Confirm their depth pixels match the expected corners and center after inverse rotation, mirror, crop, and scale.
- Confirm depth values are in meters before projection.
- Scan a ruler or caliper-measured object at 25, 40, and 60 cm.
- Compare a 73 mm baseball estimate at the same distances.
- Scan the same right and left hand twice and compare segment variation.
- Verify known left-hand and right-hand images normalize to the subject's physical hand for the pinned MediaPipe version.
- Verify the app deletes frame buffers and temporary clips when the session ends.
