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

If the phone prompts for Developer Mode, enable it in Settings > Privacy & Security > Developer Mode, restart, and reconnect. Accept the Trust prompts on both the iPhone and Mac. Each teammate can connect their phone and repeat Run with a Personal Team. The installed app can then launch from the Home Screen after disconnecting.

You can download this branch as a source ZIP from GitHub using Code > Download ZIP. The ZIP contains an Xcode project, not a signed installer. Personal Team signing is performed locally for each device.

The project intentionally has no committed development team. Its default bundle identifiers are:

- App: `com.jyshum.gripit.scanner`
- Tests: `com.jyshum.gripit.scanner.tests`

The simulator has no TrueDepth camera. Use it only for non-camera UI checks. Final validation must run on the physical device.

## Package resolution troubleshooting

If Xcode reports **Missing package product `GripItScannerCore`** or **`MediaPipeTasksVision`**, let package resolution finish before building. MediaPipe now uses the small local `ios/MediaPipeTasks` package, which downloads Google's official binary frameworks directly without cloning the large source repository. If an already-open Xcode window still says **Fetching mediapipe**, close and reopen the project to discard its old remote-package task.

Choose **File > Packages > Resolve Package Versions**, or run from the repository root:

```sh
xcodebuild -resolvePackageDependencies -skipPackageUpdates \
  -project ios/GripIt.xcodeproj -scheme GripIt
```

Keep both `ios/GripItScannerCore` and `ios/MediaPipeTasks` beside `GripIt.xcodeproj`. Avoid resetting package caches while a download is running: that discards progress. The local MediaPipe manifest pins official 1.1.1 archive URLs and checksums. Debug builds use only the selected device's architecture so the app and its local Swift package agree on the simulator architecture.

## Step 2: native grip studio

After a scan completes, tap **Explore my grips**. You can also use **Load sample profile** or **Import hand profile JSON** from the first screen. Import accepts the Step 1 `HandProfile` v1 format, so saved TrueDepth measurements can be reused without another capture.

Choose **4-seam**, **2-seam**, **Slider**, or **Changeup**. Drag to orbit, pinch to zoom, and use the Palm / Thumb / Back viewpoints to inspect the model. Contact markers are optional. [The supplied pitch guide](../docs/pitch-grip-guide.md) defines the finger roles and orientation instructions.

- The native SceneKit renderer uses the connected, MIT-licensed WebXR hand mesh, welded and subdivided twice for a smoother surface. It does not render disconnected capsule fingers.
- Palm width is interpreted as the MCP-to-MCP span used by Step 1, without the old website's 1.18 multiplier. Palm length, all 15 finger segment lengths, and valid measured MCP/CMC positions drive the pose. The asset's interior XR fingertip markers are calibrated to the visible mesh tips before scaling, preventing an extra modeled fingertip beyond the scanned length. Left hands mirror the canonical right-hand scene exactly once.
- A personalized bind shape and dual-quaternion skinning retain volume during bending. Thumb base direction is bounded away from the wrist; independent bend-plane opposition lets the index and thumb form the circle-change loop.
- The project-supplied Ball.glb clean variant is normalized to a 73 mm sphere and uses its original PBR textures. Its actual texture supplies the stitch samples. Ball rotation searches for crossed seams in a four-seamer, along-finger seams in a two-seamer, slider middle-on-seam/index-on-leather, and middle/ring seam contacts for the circle change.
- Skin overlap, edge stretching, visible pad-to-ball gaps, pad-target gaps, seam alignment, and circle-loop gaps between rendered fingertip surfaces are checked. Severe overlaps or distorted meshes are rejected. Less severe unresolved fits show an orange review message.

This is an authored hand fitted to measurements, not a photogrammetric or biomechanically validated skin reconstruction. Unmeasured thickness, nails, and soft tissue remain modeled. Local pad/seam alignment is checked numerically; the full horseshoe orientation and overall anatomy still require visual review on real scanned profiles. Capsule collision penalties and vertex checks do not guarantee a completely collision-free skin surface. Pressure is described by the guide, not inferred or simulated.

Xcode bundles the generated model resources directly; there is no npm step for ordinary Swift changes. To regenerate the native assets after editing the source GLBs or seam samples, run `npm ci` and `node scripts/prepare-native-grip.mjs`. Model conversion preserves the source license notices in the app resources.

For Debug-only simulator previews, add `--grip-preview --pitch=changeup --camera=thumbSide` to the scheme launch arguments. `--left` previews the mirrored hand. Add `--heatmap` for labeled sample diagnostics. These entry points do not replace the scanner in Release builds.

The viewer now includes seven selectable zones and a shared diagnostic heat map. See [the native viewer contract and review steps](../docs/step-2-viewer.md) for severity input, reach tolerances, selection behavior, and limitations.

## Scan flow

1. Choose the physical hand being scanned.
2. Prop the phone upright with the screen facing you. Hold the open hand 30–40 cm in front of the selfie camera. Your face does not need to be in frame.
3. Complete the views in order: palm, thumb side, back, pinky side.
4. Keep the whole hand visible until each view fills.
5. Review or export the resulting `HandProfile` JSON.

The small skeleton shows valid depth samples for the current view, including individual joints from a frame that is incomplete elsewhere. Overall progress advances only after 21 measured joints pass view and metric stability checks. Brief depth holes may use a real sample from the same steady view within the previous 350 milliseconds. Historical points expire and reset on motion or tracking loss; hidden points are never predicted. The accepted-frame counter shows actual progress through the current view. A filled skeleton alone does not mean the scan is finished.

The initial palm establishes hand identity using three confident observations.
During spatially continuous tracking, uncertain left/right labels at side angles
do not block capture. A tracking gap over 750 milliseconds, multiple hands, a
large position/scale jump, or a reliable opposite-hand frontal label requires
palm reacquisition. Completed views remain saved. This continuity heuristic is
not biometric identification.

For the side steps, make a partial turn, roughly 30–75 degrees, while keeping
every finger visible. Do not turn fully edge-on. All original metric stability
and bone-length checks remain active. The app distinguishes overlapping fingers,
motion, and fluctuating depth instead of calling every rejection “hold still.”

View orientation is resolved from the TrueDepth measurements, in the hand's own
basis: the radial axis from the pinky MCP to the index MCP, and the distal axis
from the wrist to the middle MCP. Measured depth is what fixes the sign of
“toward the camera”. MediaPipe's world landmarks are a single-image estimate
whose depth scale and sign Google documents as unreliable, and a side view
depends on exactly that quantity, so they are not used for orientation. The four
palm anchors therefore need valid depth before a view can be judged. It reports how much of the palm, the thumb side, and the fingertips point
at the camera. Those three cosines are invariant to image-plane roll, so tilting
the hand in frame, or an analysis buffer that is not upright, cannot change which
view the scanner believes it sees. Reading a side view off the palm normal's x
component in image axes did depend on that roll, which left palm and back
reachable while the side views were not. Fingertips aimed down the lens are
rejected for every view because they foreshorten every finger segment.

A diagnostic panel is shown during scanning and can be toggled with the
stethoscope button. It names the gate currently blocking capture along with the
values that gate decided on: identity lock, label confidence, the three facing
cosines, requested versus observed view, consecutive pose frames, valid and
bridged depth counts, stability status with motion and bone-change in
millimetres, accepted frames, and the frame size and analysis rotation. The same
line is written to the unified log under subsystem `com.gripit.scanner`,
category `gates`, whenever the blocking gate changes.

Thickness is currently unavailable and remains `null`. Exported confidence is the initial palm identity score retained during continuous tracking, not measurement accuracy. This meaning is also recorded in the profile extensions. Validate measurements against a ruler before using the profile elsewhere.

RGB and depth outputs explicitly use native rotation 0. Apple's camera rotation coordinator determines the required analysis and preview angles rather than assuming every sensor needs a fixed 90-degree turn. RGB pixels are explicitly rotated upright before MediaPipe inference with `.up` orientation. Output points are then mapped once back to the original unmirrored sensor space for depth lookup. The overlay uses the preview's actual rotation, mirroring, and aspect-fill crop. Calibration lens-distortion correction is applied before metric projection.

The analysis coordinates stay unmirrored. Only the selfie preview is mirrored. The scan requires synchronized RGB and depth frames. It does not fall back to RGB-only scale estimation.

## Packages and model

- `GripItScannerCore` is a local package at `ios/GripItScannerCore`.
- `MediaPipeTasksVision` uses official `v1.1.1` binary URLs and checksums from commit `50505c8312c7eacb1bd411cecdc4cc9fd08d53cb`, packaged locally under `ios/MediaPipeTasks`.
- `public/mediapipe/hand_landmarker.task` is referenced directly as an app resource. There is no second checked-in copy.

Local packaging preserves the required unsafe linker flags without cloning the upstream repository. Open the project in Xcode and confirm package resolution before the device test.

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

### Inspect the hand before fitting a grip

In Grip studio, tap **Hand model** to review the measured hand independently of
baseball targets. The view includes front/back/side controls, joint flexion,
mesh inspection, and a SceneKit export. See [the hand model review guide](../docs/hand-model-review.md)
for the reusable rigged GLB, source generation, and Debug launch arguments.

See [the current hand proportions and ball integration](../docs/natural-hand-and-ball.md) for the slimmer palm, corrected reference spacing, asset regeneration, and verification.
