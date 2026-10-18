# TrueDepth Scanner Demo Design

## Goal

Build a minimal native iOS application that proves GripIt's hand-scanning approach on an iPhone 17. The demo captures synchronized front-camera RGB and TrueDepth data, detects 21 hand landmarks, guides the user through four hand views, and exports measured hand geometry.

The demo is installed directly from Xcode onto the test iPhone. It is not prepared for the App Store, TestFlight, or public distribution.

## Scope

The application includes only:

- Throwing-hand selection.
- Camera permission and TrueDepth capability checks.
- A native live camera preview.
- MediaPipe hand landmarks over the preview.
- Four-view scanning guidance.
- Per-joint and per-segment coverage visualization.
- Metric hand measurements and quality diagnostics.
- `HandProfile` JSON export.
- A simulator sample mode.

The application does not include the existing WebView, the web camera scanner, a rendered hand, a baseball model, pitch selection, grip instructions, throw entry, or account features.

## Architecture

The `ios-app` branch remains the base. Development occurs on `feature/truedepth-scanner-demo`.

The app target owns SwiftUI, AVFoundation, Core Video, preview rendering, camera permissions, MediaPipeTasksVision, coordinate transforms, and device diagnostics. `GripItScannerCore` remains a local Swift package and owns metric projection, accepted observations, coverage rules, measurement aggregation, handedness canonicalization, and `HandProfile` encoding.

The WebView code may remain in the repository for history, but it is not started or used by this demo.

## Capture Pipeline

1. Discover the front `builtInTrueDepthCamera`.
2. Configure video and depth outputs on one `AVCaptureSession`.
3. Synchronize frames with `AVCaptureDataOutputSynchronizer`.
4. Send the unmirrored RGB buffer to MediaPipe Hand Landmarker in live-stream mode.
5. Keep the visible selfie preview mirrored without changing analysis coordinates.
6. Map all 21 landmark pixels into the aligned depth map.
7. Sample a small median depth neighborhood for every landmark.
8. Reject incomplete, low-confidence, nonfinite, or out-of-range frames.
9. Project valid pixels into metric XYZ coordinates with camera intrinsics.
10. Pass a complete `ScanObservation` to `ScannerSession`.

Frame buffers and depth maps remain in memory only while processing. They are not saved or uploaded.

## Scanning Experience

The first screen asks whether the throwing hand is left or right. The scan then starts in portrait orientation.

The camera preview occupies most of the screen. It contains:

- A landmark skeleton aligned over the real hand.
- A short current instruction.
- A directional rotation arrow.
- Overall scan progress.
- A compact skeletal coverage map in the lower corner.
- A small diagnostics row showing valid depth landmarks and distance.

The required sequence is palm, thumb side, back, then pinky side. Progress updates only from accepted frames. The instruction explains whether to move closer, move farther away, center the full hand, flatten the hand, rotate left, rotate right, or hold still.

The skeletal coverage map starts gray. A joint becomes partially filled while valid samples accumulate and green after it meets the required count across the necessary views. A connecting segment fills only when both endpoints have sufficient valid depth. This coverage is diagnostic and does not weaken the existing four-view completion requirements.

## Results

After all required coverage completes, the app shows:

- Palm width and length in millimeters.
- Each finger's segment lengths in millimeters.
- Available thickness measurements.
- Accepted frame counts per view.
- Per-landmark coverage and scan consistency.
- Camera and depth diagnostics needed for physical validation.
- Buttons to export JSON, scan again, or load the bundled sample profile.

The exported value is the versioned `HandProfile` used by future GripIt workstreams.

## Failure Handling

The app presents explicit states for:

- Camera permission denied.
- TrueDepth camera unavailable.
- No synchronized depth format.
- MediaPipe model initialization failure.
- No hand or more than one hand found.
- Wrong physical hand detected.
- Missing depth at required landmarks.
- Hand outside the supported distance range.
- Incomplete scan or unstable measurements.

Rejected frames do not change progress. The user can restart without relaunching the app.

## Testing

Automated tests cover the core contract, projection, measurement aggregation, coverage, handedness normalization, and adapter coordinate transforms. The existing web test suite must remain passing even though the WebView is unused by this demo.

Physical iPhone 17 validation checks:

- TrueDepth RGB and depth frames synchronize.
- Preview landmarks follow the hand in portrait orientation.
- All 21 landmark locations map to valid depth pixels when visible.
- A measured ruler and 73 mm baseball remain within an agreed prototype tolerance at 25, 40, and 60 cm.
- Repeated scans of the same hand produce stable segment measurements.
- Right and left handedness labels match the user's selected physical hand.
- No captured images or depth maps remain after a scan ends.

## Local Installation

The repository includes setup instructions for a development build:

1. Install full Xcode.
2. Open the GripIt Xcode project.
3. Select the user's Apple development team and a unique bundle identifier if required.
4. Connect and trust the iPhone 17.
5. Select the phone as the run destination.
6. Build and run directly from Xcode.

No App Store or TestFlight configuration is required for the hackathon demo.

## Acceptance Criteria

- The app launches directly into the native scanner.
- The old WebView scanner is never loaded.
- The iPhone 17 reports a usable front TrueDepth camera and synchronized depth format.
- The user can complete all four guided views.
- The skeletal coverage map reflects accepted landmark depth samples.
- The app produces a valid `HandProfile` with metric measurements.
- The result can be exported as JSON.
- The project can be installed directly on the test iPhone from Xcode.
