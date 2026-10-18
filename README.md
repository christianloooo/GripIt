# GripIt

A browser-based grip studio with automatic hand measurement from a baseball reference, a rigged 3D hand, and a regulation-scale textured baseball.

## iOS app

This branch includes a SwiftUI iPhone/iPad app with the studio and Rapsodo throw entry bundled in WebKit, camera authorization, and native JSON sharing. Run `npm run ios:prepare`, then open `ios/GripIt.xcodeproj` on a Mac. Select your signing team and device in Xcode. See [iOS setup and architecture](ios/README.md).

## Run

Requires Node.js 22.12+ or Node.js 24.

```sh
npm install
npm run dev
```

Open the URL printed by Vite. Camera access requires localhost or HTTPS. Restart the server after changing scan worker code; `predev` and `prebuild` prepare its classic-worker bundle and the local MediaPipe WASM files.

```sh
npm test
npm run build
npm run preview
```

## Rapsodo throw entry

After viewing a grip, select **Next: record throws** beneath the 3D viewer. The selected pitch and throwing hand carry into a responsive input table. Enter velocity (mph), total spin (rpm), spin direction (hh:mm), spin efficiency (%) or signed gyro degree, and release height (ft). Rapsodo score is optional; no device-specific score scale is assumed. Broad numeric limits catch likely typos, not performance targets.

**Save & review session** accepts one or more valid throws and shows average velocity/spin plus session history. Re-saving updates the same session instead of duplicating it. Drafts remain separate by pitch, throwing hand, and optional hand-profile ID when navigating back to the grip view. Sessions and drafts are temporary: export JSON before refreshing or closing the app.

**Load sample session** replaces unsaved entries with three clearly labeled fake throws. Editing them retains `source: "sample"`; choose **Start real session** to enter real readings. **Export session JSON** downloads an array of v1 `ThrowRecord` values for Step 4. When embedded in a compatible iOS host, exports use its existing `gripit` share bridge instead of a browser download.

Integration: `SessionTable` accepts `pitchId`, `pitchName`, optional `handProfileId`, optional `handedness`, `onBack`, and an optional `onSaved(records)` callback. Records match `docs/contracts/v1/fixtures/throw-record-four-seam.json`. Clock time uses decimal hours (`12:30` becomes `12.5`), optional values use `null`, and an available profile ID is stored under `extensions["gripit.throwEntry"].handProfileId`. No coaching or assessment fields are added. The current scanner does not yet expose a shared `HandProfile`, so its private measurement object is not used as one.

Core files: `src/SessionTable.tsx`, `src/throwEntry.ts`, `src/exportThrows.ts`, `src/throwEntry.css`. Run `npm test` for validation, fixture compatibility, component interaction, exports, and grip-to-entry navigation checks; run `npm run build` for the production bundle.

## Scan: no measurements to type

1. Put a **regulation baseball** beside one open hand against a dark, uncluttered background. Do not hold the ball inside the scanning hand.
2. Keep the entire ball and all fingertips visible, with space between the ball and hand. Face the palm toward the camera, fingers straight and comfortably spread.
3. Keep the palm and ball center at approximately the **same camera distance**. Use a straight-on view, step back enough to reduce perspective differences, and hold still.
4. Start the camera scan or upload a short video. A green circle should outline the baseball; landmarks outline the hand. Rescan if the reference circle is wrong.
5. Review the detected throwing hand and apply the scan. Dimensions are displayed automatically; there are no numeric scan inputs.

The reference diameter is **73 mm**. A gradient/circle detector locates the ball, checks its outline/brightness and separation from the hand, and derives millimeters per pixel. It rejects missing, cropped, poorly contrasted, or overlapping references. This is geometric detection, not a trained semantic baseball classifier: another bright circular object can be mistaken for a ball. Use one baseball and check the overlay.

MediaPipe supplies joint landmarks. Aspect-corrected image coordinates and estimated depth determine segment distances. Palm width includes an estimated skin margin around the measured knuckle span. Knuckle X/Y positions personalize finger attachment points. Root depth and finger thickness remain modeled. Accepted frames must contain one open hand and a usable ball, and per-segment measurements must remain stable across frames.

All video processing happens locally in a Web Worker. The model, runtime, hand, and baseball assets are bundled locally. Optional Google Fonts may download fonts; the interface falls back to system fonts offline. Measurements stay in memory unless exported.

## Measurement equations

```text
mm_per_pixel = 73 / detected_ball_diameter_pixels
L = sqrt((x2-x1)^2 + (y2-y1)^2 + (z2-z1)^2) * calibrated_scale
L_index = d(5,6) + d(6,7) + d(7,8)
```

Normalized landmark Y is multiplied by image height/width; normalized Z shares X units. This preserves the aspect ratio before applying the distance formula. Medians aggregate segment lengths and knuckle positions across consistent-handedness frames.

A single camera does not establish the absolute depth difference between the ball and palm. Perspective, the real ball's diameter, lighting, and landmark error affect scale. These are approximate measurements, not a precision skin scan or a guarantee of millimeter accuracy.

## Rendering and position accuracy

The default hand is the authored, rigged `generic-hand/right.glb` from the MIT-licensed Immersive Web WebXR Input Profiles assets. It is cloned, transformed to a canonical right-hand coordinate frame, proportioned, and retargeted to the solver's FK anchors. The bind skin is reshaped to measured segment lengths using the original skin weights before posing. Minimum segment rotations retain the authored thumb roll. Tests verify that all 20 finger joint/tip anchors agree with solver positions, and actual skin checks reject excessive stretching and collapse. The canonical hand has palm +Z, fingers +Y, and thumb +X; left-handed rendering mirrors X once.

This establishes **renderer/solver agreement**, not anatomical or biomechanical correctness. A generic mesh is not the user's exact skin. Soft-tissue deformation, contact pressure, tendon coupling, release motion, and full thumb opposition are not reconstructed. Some fits remain unresolved; the viewer shows the largest target gap and flags those configurations.

Scans are checked against all four pitch models before replacing the current hand. Rejected scans leave the previous selection intact. Unexpected hand rendering failures display a rejection message instead of silently substituting a procedural model. The older procedural surface remains in the repository for its geometry regression tests.

## Failure logging

Open **Failure log** in the header to review, download, or clear the last 50 failures stored in this browser. Scan entries include frame rejection counts when available. Model entries include measurements and available deformation metrics. Video and images are not logged or uploaded. Failures from before this feature existed cannot be recovered.

[FAILURE_LOG.md](FAILURE_LOG.md) records the warped-thumb investigation, changes, verification, and remaining limits. Deformation checks reject severe stretching/collapse; they do not establish anatomical accuracy or full skin collision clearance. Thumb fits with a target gap over 12 mm or capsule penetration beyond 2 mm are rejected.

## The supplied baseball asset

The viewer uses **[Worn Baseball Ball by Alex Bes](https://sketchfab.com/3d-models/worn-baseball-ball-fdf3de6ae225421ea78961b897b9608a)**, licensed **CC BY 4.0**. The matching source was retrieved from a public redistribution whose embedded USD metadata identifies the same author, title, source URL, and license.

It was converted to GLB, recentered, radially normalized to a **73 mm sphere**, and packaged with its albedo, normal, roughness, and occlusion maps. Visible red stitch pixels were sampled through the original mesh UVs into contact-reference coordinates. The optimizer targets those coordinates, rather than the previous unrelated procedural seam curve. Radial normalization removes the source mesh’s slight shape irregularity; textured wear remains. The triangulated surface approximates a sphere, and collision checks use its analytic 36.5 mm radius.

Attribution and changes: `public/models/ATTRIBUTION.md`. Hand license: `public/models/HAND-LICENSE.md`. `scripts/convert-baseball.py` documents conversion (Pillow plus an ASCII USD export from `usdcat`); running the app does not require Python or USD tools.

## Geometric optimizer

```text
p_i = FK(theta_i, L_i)
E_position = sum_i ||p_i - t_i||²
E_joint = sum_j ((theta_j - theta_neutral_j) / theta_range_j)²
E_collision = squared capsule/ball and capsule/capsule penetrations
E = 1 * E_position + 6 * E_joint + 80 * E_collision
```

Bounded multi-start coordinate descent searches finger flexion, knuckle spread, ball translation, and orientation. A coarse orientation search accommodates the imported ball's seam layout. Index and middle targets follow the same transformed asset used in the viewer. The remaining finger targets support the lower/side surface. Finger-segment lengths are preserved by FK. JSON exports contain dimensions, ball transform, angles, target errors, clearance, calibration metadata, and objective values. Left hands use canonical right-hand coordinates with `mirrorX: true`.

This is a local geometric fit, not proven pitch-performance optimization. Sphere/capsule collision terms do not guarantee a collision-free skin mesh, and palm collision is not modeled. Pitch templates are illustrative. CSV feedback and performance experiments remain outside this revision.

## Main files

- `src/ballReference.ts`: automatic circle detection and ball-calibrated hand measurements.
- `src/scan.ts`, `src/scan.worker.ts`, `src/scanQuality.ts`: capture sampling, worker inference, quality checks, aggregation.
- `src/ScanDialog.tsx`: camera/upload scan, reference overlay, result review.
- `src/grip.ts`: FK, imported seam targets, bounded optimizer, fit diagnostics.
- `src/riggedHand.ts`: authored hand retargeting to FK anchors.
- `src/Scene.tsx`: hand, supplied baseball, camera, lights, and contact labels.
- `src/handSurface.ts`: adaptive procedural fallback.

MediaPipe reference: [Hand Landmarker for Web](https://ai.google.dev/edge/mediapipe/solutions/vision/hand_landmarker/web_js).
