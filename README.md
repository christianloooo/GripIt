# GripIt

A browser-based baseball grip studio: choose a pitch, personalize a procedural rigged hand, and rotate, zoom, or pan around a regulation-scale baseball.

## Run locally

Requires Node.js 22.12+ (Node.js 24 LTS recommended).

```sh
npm install
npm run dev
```

Open the local URL printed by Vite. Camera access requires localhost or HTTPS.

```sh
npm test
npm run build
npm run preview
```

## The prototype

- React, TypeScript, React Three Fiber, Drei, and Three.js.
- A procedural hand with skinned finger meshes, a bone hierarchy, adjustable segment lengths, and a modeled palm. No external hand asset or paid model is required.
- A 73 mm diameter baseball with procedural red seam stitching. Every scene dimension uses millimeters.
- Four illustrative pitch templates: four-seam, two-seam, slider, and changeup. The selected template changes fingertip target regions and seam orientation.
- Numerical finger positioning with joint limits and a sphere-penetration penalty. The viewer reports unresolved fits rather than claiming every target was reached. Finger labels follow the solved fingertips.
- Right and left hands, labels, separated hand/ball view, camera reset, full screen, and JSON configuration export.
- Manual palm and finger dimensions, or an in-browser MediaPipe scan from a camera or uploaded video. The scanner samples open-hand frames, rejects implausible measurements, and takes median segment lengths from at least five frames with consistent handedness.

## Hand scan

Show **one open hand**, fingers spread, palm toward the camera, in bright light. Measure palm width across the index-to-pinky knuckles (excluding the thumb), and enter that width in millimeters. Use a roughly 4–8 second MP4/WebM clip or the four-second camera scan. Videos with folded fingers are unsuitable for measuring proportions.

MediaPipe estimates 21 world landmarks. Distances between landmarks 5 and 17 establish scale using the measured palm width; consecutive finger-joint distances define the bone lengths. Use the throwing-hand toggle if inferred handedness is reversed by your camera/video.

Video frames stay in the browser. The MediaPipe WASM runtime and model download from jsDelivr and Google Storage on first scan, so scanning requires internet access. The default viewer and manual dimensions work without these model downloads. Google Fonts is optional and falls back to system sans-serif fonts.

## Scope and limitations

This implements the initial rendering/personalization workflow, without a backend, CSV feedback, or pitch-performance optimization. The hand is stylized; landmarks do not capture finger thickness or exact skin geometry. It is a procedural rig rather than an imported artist-authored GLB. Seam curves and pitch contact targets are illustrative and are not anatomically or biomechanically validated. Target placement is not calibrated to the stitched seam curve.

The solver uses a planar three-joint chain per finger, with a fixed base orientation. It penalizes intersections with the ball but does not guarantee collision-free geometry or model finger-to-finger collision, soft tissue, pressure, or full thumb opposition. Some hand dimensions produce unresolved target fits. This is a visualization prototype, not a coaching or injury-prevention tool.

Exported JSON includes measurements, handedness, ball position/radius, base orientations, joint angles in radians, target errors, and minimum finger-segment clearances. Left-handed rendering mirrors the full model across X. Data stays in memory until exported; reloading resets the sample hand.

## Code map

- `src/grip.ts`: hand dimensions, pitch templates, kinematics, collision diagnostics, and landmark calibration.
- `src/Scene.tsx`: procedural skeleton/skin, baseball seams, labels, lights, and orbit controls.
- `src/scan.ts`: MediaPipe setup, video frame sampling, filtering, and median measurement aggregation.
- `src/ScanDialog.tsx`: camera/upload lifecycle, calibration, progress, errors, and scan review.
- `src/App.tsx`: studio controls and configuration export.

MediaPipe implementation reference: [Hand Landmarker for Web](https://ai.google.dev/edge/mediapipe/solutions/vision/hand_landmarker/web_js).
