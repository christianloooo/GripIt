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

## The studio

The viewer uses a smooth, continuous implicit hand surface (palm, wrist, thumb pad, tapered finger capsules, and nails), with finger positions driven by measured segment lengths. The canonical model is a **right hand**: palm faces +Z, fingers point +Y, thumb lies on +X. Left hands mirror X once. Preview mirroring does not alter detection coordinates.

The baseball is 73 mm in diameter. Its seam curve is shared between drawing and optimization. Index and middle targets are sampled on that seam, offset outward by fingertip radius so the finger pad can meet the ball surface. Four pitch templates provide starting regions and orientations; they are illustrative, not validated coaching recommendations.

## Optimization equations

Segment measurements use the requested Euclidean distance:

```text
L = sqrt((x2-x1)^2 + (y2-y1)^2 + (z2-z1)^2)
L_index = d(5,6) + d(6,7) + d(7,8)
scale = measured middle length / (d(9,10)+d(10,11)+d(11,12))
# measureLandmarks also supports palm-width-only calibration: width / d(5,17)
```

The browser optimizer minimizes the requested weighted geometric objective:

```text
p_i = FK(theta_i, L_i)
E_position = sum_i ||p_i - t_i||^2
E_joint = sum_j ((theta_j - theta_neutral_j) / theta_range_j)^2
E_collision = squared capsule/ball and capsule/capsule penetrations
E = w1 E_position + w2 E_joint + w3 E_collision
```

`solveGrip` uses bounded, multi-start coordinate descent, alternating finger flexion/knuckle spread with ball position and orientation. Targets follow the transformed seam. Weights are 1 / 6 / 80. Each finger has three flexion angles and a knuckle spread angle. Ball translation is bounded within 10 mm of its initial pose; rotation is bounded around the pitch template. The exported objective contains the unweighted components and weighted total.

This implements the equations in TypeScript to keep the app running with `npm run dev`; Python/SciPy and an API server are not required. It finds a local geometric fit and does not guarantee a global optimum or a collision-free solution. Finger/palm attachments are intentionally blended; inter-finger capsule collision excludes the merged base/base region. Soft tissue, pressure, release dynamics, and palm collision are not modeled. Unresolved target fits are reported below the viewer.

## Guided scan

Show **one open hand**, fingers straight and spread, in bright light. Enter your measured palm width across the knuckles (excluding the thumb) and middle finger length from its base knuckle to the tip, in millimeters. The middle-finger reference calibrates segment scale; palm width sets the palm mesh directly. This avoids letting an unreliable short MediaPipe palm span inflate every finger. The scan shows 21 tracked landmarks and feedback for missing hands, multiple hands, cropped fingertips, folded fingers, edge-on palms, and unstable measurements. Lengths use aspect-corrected normalized image landmarks with their estimated depth (Y is multiplied by video height/width; Z shares X units). The Euclidean distance equation is applied to these 3D coordinates, calibrated against measured middle-finger length. World landmarks check open-hand pose. It requires at least eight stable frames with consistent handedness and takes median segment lengths. Live scans finish early after 25 stable frames; video scans sample up to 60 frames.

Camera previews behave like a mirror, but the detector receives the original frames. For a video recorded with a mirror filter, select the mirror option. Review and correct the throwing hand before applying a scan. Finger and palm dimensions remain editable afterward.

Inference runs in a classic Web Worker so the interface stays responsive. The model is included at `public/mediapipe/hand_landmarker.task`; `npm install`, `npm run dev`, and `npm run build` prepare the matching WASM runtime and bundled worker locally. Camera/video frames stay on the device; scanning makes no model/CDN requests. Optional Google Fonts still downloads fonts and falls back to system fonts offline.

Landmarks estimate proportions, not exact skin geometry. Palm length is inferred from wrist-to-middle-knuckle distance. Finger thickness is a scaled anatomical proxy, not measured from images. Check scan measurements against a ruler. No scan is stored unless exported; reloading resets the sample hand.

## Export and scope

JSON exports include measured dimensions, ball transform, finger angles in radians, target coordinates, target errors, clearance, and objective values. Coordinates are canonical right-hand coordinates; `mirrorX: true` identifies left-handed rendering.

CSV feedback, pitching-performance optimization, and the experimental `G_next = G + delta_G` loop are not implemented in this revision. This revision addresses handedness, hand visualization, scan quality, and the geometric fitting equations.

## Code map

- `src/grip.ts`: hand dimensions, pitch templates, kinematics, collision diagnostics, and landmark calibration.
- `src/Scene.tsx` and `src/handSurface.ts`: continuous hand skin, nails, shared baseball seams, labels, lights, and orbit controls.
- `src/scan.ts`, `src/scan.worker.ts`, and `src/scanQuality.ts`: worker inference, frame sampling, quality filters, and median measurements.
- `src/ScanDialog.tsx`: camera/upload lifecycle, calibration, progress, errors, and scan review.
- `src/App.tsx`: studio controls and configuration export.

MediaPipe implementation reference: [Hand Landmarker for Web](https://ai.google.dev/edge/mediapipe/solutions/vision/hand_landmarker/web_js).
