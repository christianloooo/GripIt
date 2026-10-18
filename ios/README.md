# GripIt TrueDepth scanner

This native SwiftUI demo uses the front TrueDepth camera for metric hand measurements. MediaPipe identifies 21 hand landmarks. `GripItScannerCore` handles projection, guided coverage, aggregation, and `HandProfile` JSON.

Camera and depth frames are processed in memory. The app does not save photos, video, or depth maps.

## Requirements

- A Mac with Xcode.
- iOS 17 or later.
- A physical iPhone with a front TrueDepth camera. Device validation targets iPhone 17.
- An Apple ID added to Xcode. A free Personal Team is enough for direct device installation.

The iOS app does not require `npm`, `npm run ios:prepare`, a local web server, or generated web assets.

## Run on iPhone 17

1. Connect and unlock the iPhone.
2. Open `ios/GripIt.xcodeproj` in Xcode.
3. Wait for Swift Package Manager to resolve `GripItScannerCore` and `MediaPipeTasksVision`.
4. Select the **GripIt** target, then **Signing & Capabilities**.
5. Select your Personal Team. Change the bundle identifier only if your team reports a conflict.
6. Select the connected iPhone 17 as the run destination.
7. Press **Run**.
8. Allow camera access when prompted.

The project intentionally has no committed development team. Its default bundle identifiers are:

- App: `com.jyshum.gripit.scanner`
- Tests: `com.jyshum.gripit.scanner.tests`

The simulator has no TrueDepth camera. Use it only for non-camera UI checks. Final validation must run on the physical device.

## Scan flow

1. Choose the physical hand being scanned.
2. Hold the open hand near the requested distance.
3. Complete the views in order: palm, thumb side, back, pinky side.
4. Keep the whole hand visible until each view fills.
5. Review or export the resulting `HandProfile` JSON.

The analysis coordinates stay unmirrored. Only the selfie preview is mirrored. The scan requires synchronized RGB and depth frames. It does not fall back to RGB-only scale estimation.

## Packages and model

- `GripItScannerCore` is a local package at `ios/GripItScannerCore`.
- `MediaPipeTasksVision` is pinned to official `v1.1.1` commit `50505c8312c7eacb1bd411cecdc4cc9fd08d53cb`.
- `public/mediapipe/hand_landmarker.task` is referenced directly as an app resource. There is no second checked-in copy.

The revision pin is required because the package uses unsafe linker flags. Open the project in Xcode and confirm package resolution before the device test.

## Checks

These syntax checks do not require full Xcode:

```sh
plutil -lint ios/GripIt.xcodeproj/project.pbxproj
plutil -lint ios/GripIt/Info.plist
```

With full Xcode and package access, run the app tests:

```sh
xcodebuild test \
  -project ios/GripIt.xcodeproj \
  -scheme GripIt \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath ios/build \
  CODE_SIGNING_ALLOWED=NO
```

Simulator tests cover adapter math and non-camera behavior. They do not validate TrueDepth capture, MediaPipe handedness, preview alignment, or measurement accuracy. Use [the device checklist](../docs/testing/truedepth-device-checklist.md) for those checks.
