# Perceptron evaluation for GripIt

Research date: October 18, 2026. Research only; no app or rule changes.

## Live-test update

Subsequent tests succeeded with key 2 and the official Mk1.5 SDK. The tested hand prompts misplaced joints, so a MediaPipe replacement is not supported by these results. Actual report OCR read the bundled baseball sample correctly twice; another report needed a crop to recover small break labels. Twelve inference requests cost an estimated $0.0080967. See [the live-test report](2026-10-18-perceptron-live-test.md). The earlier access-block and Egocentric discussion below are historical research; Jared has confirmed Egocentric is unavailable and only Mk1.5 is in scope.

## Priority and conclusion

Evaluate replacement of MediaPipe first. Real OCR for uploaded Rapsodo reports is second. Account creation and cloud progress storage remain deferred.

Perceptron is a candidate hand-landmark provider, but the official material reviewed does not demonstrate better physical hand measurement accuracy than MediaPipe. Retain TrueDepth and the downstream HandProfile contract. Do not replace the working scanner based only on general vision benchmarks.

The supplied Claude artifact could not be accessed by the browsing tool. Findings below come from current official vendor documentation and the actual app source.

## What GripIt does today

HandLandmarkerService runs MediaPipe's bundled Hand Landmarker on the phone, returning 21 normalized image points, a handedness label, classification confidence and hand count. It does not supply metric dimensions to the app.

TrueDepthCaptureService pairs video with depth and calibration. It currently delivers up to eight frames per second to the scanner. DepthLandmarkMapper rotates the image points back into sensor coordinates, samples measured depth, rejects discontinuities and projects into millimeters. ScannerFrameProcessor derives hand facing from these measured points, locks physical handedness, checks requested views, handles brief measured-depth gaps, and checks stability before accepting a frame.

HandMeasurementAggregator measures palm width between index/pinky knuckles, palm length from wrist to their midpoint, and finger segment distances, then takes medians across observations. These are landmark-based dimensions, not an exact bone or skin reconstruction. Palm thickness and finger diameters remain absent. The existing grip fitter supplies modeled thickness from its reference anatomy where measurements are absent. Full wrist-to-fingertip hand length is not a separately stored scalar.

Steps 2 and 4 consume HandProfile and the cached fitted model. The scanner adapter should continue to produce the same profile schema, units and joint names.

## Relevant documented Perceptron capabilities

The current public Mk1.5 model supports multimodal requests, spatial annotations and structured outputs. Its chat annotations use a normalized 0-1000 image grid, not millimeters. Endpoint contracts differ, so that convention must not be assumed for Egocentric or Detect responses without their schema.

Perceptron's July 9 Egocentric announcement specifically advertises a hand-pose sidecar returning per-frame boxes, full 21-keypoint skeletons and left/right identities. It is described as early access for video annotation, and the pose stream runs on their GPUs separately from the metered API. This is more relevant than asking the generic chat model to guess joint locations. Public material reviewed does not establish its anatomical joint error, live iPhone request latency, internal pose-model implementation, or superiority over MediaPipe on our capture poses.

The Mk1.5 release's hand-localization comparison measures hand boxes against Gemini, not finger-joint localization or hand dimensions against MediaPipe. It cannot establish a measurement accuracy improvement for GripIt.

Official sources:

- https://www.perceptron.inc/blog/introducing-perceptron-egocentric-api
- https://www.perceptron.inc/blog/introducing-perceptron-mk1-5
- https://docs.perceptron.inc/perceptron-mk1.5/concepts/coordinates
- https://docs.perceptron.inc/perceptron-mk1.5/index
- https://developers.google.com/edge/mediapipe/solutions/vision/hand_landmarker/ios
- https://developer.apple.com/documentation/avfoundation/avdepthdata/cameracalibrationdata

## Measurement-first evaluation

1. Confirm access to the Egocentric pose service, its exact endpoint/schema, joint definitions/order, handedness convention, visibility/confidence semantics, timestamp behavior, and whether it supports live frames rather than only completed video jobs. Confirm what model implements its pose stream. A standard chat API key does not establish access to this service.
2. Capture synchronized color/depth/calibration examples from the actual scanner, covering both hands and every requested view. Keep originals and timestamps together. Compare providers on identical frames rather than separate scans.
3. Require named anatomical joints, preserve frame orientation/crops, and map returned points into the existing sensor/depth coordinates. Never combine delayed points with the latest live depth frame. Retain each original depth frame until its matching result is processed.
4. Compare image-joint localization, missing/swapped joints, projected measurement error against explicitly defined physical reference measurements, repeat-scan variation, completion time, and stalls. Distinguish improved usability from improved dimensional accuracy. Agree acceptance tolerances before deciding; no unsourced accuracy target.
5. Keep handedness identity scores distinct from confidence in joint placement or dimensional accuracy. Preserve all existing measured-depth, stability and missing-data gates. Do not replace missing measured depth with generated geometry.
6. If this service improves the measured outcomes sufficiently for the agreed goals, substitute only the landmark provider before DepthLandmarkMapper. Maintain the same HandProfile so the fitter, cached renderer, throw rules and Step 4 continue unchanged. If latency fails the live flow, assess captured stable keyframes as a separate option rather than promising equal live responsiveness.

For fuller personalized shape, investigate measured contours and registered depth surfaces across views to obtain finger diameter and palm thickness. This would be a separate geometry/capture task. Existing optional profile fields and fitter consumers can receive those measurements without redesigning the rule engine, but quality must be validated first.

## Second priority: real report OCR

Perceptron documents image OCR and structured extraction. That is a closer fit for reading Rapsodo screenshots than using a general vision response as a physical ruler.

Current Rapsodo flow only recognizes exact bundled image bytes and copies saved fixture values. It has not tested model extraction. Unknown uploads are manual. Real OCR must send the image to the service, validate field labels, units and absent values, then populate the existing editable ThrowDraft for user confirmation. It must not get its expected answers from filename matching or saved fixture values.

Test the actual bundled baseball rapsodo1 image against manually checked visible readings, then independent photos and changed screenshots that cannot pass through exact fixture recognition. Current expected fixture: velocity 77.3 mph; total spin 1642 rpm; direction 01:56; efficiency 93.8%; horizontal break 18.6 in; vertical break 13.8 in. Verify visible signs/units rather than inferring handedness or movement conventions from this fixture. Absent release height, gyro angle and score must remain absent; unreadable values require review. Preserve cancellation, source replacement protections and confirmation before adding a throw. Any fixed two-second scan effect must reflect the actual request state and must not imply the API has finished before it returns.

Sources:

- https://docs.perceptron.inc/perceptron-mk1/capabilities/ocr
- https://docs.perceptron.inc/perceptron-mk1.5/capabilities/structured-outputs
- https://github.com/perceptron-ai-inc/perceptron

At the time of this initial research, no Perceptron key was configured and no authenticated API request, image upload, accuracy benchmark or live latency test had been performed. The first live attempt was blocked, but subsequent tests succeeded with key 2 and the official SDK. The current results are recorded in 2026-10-18-perceptron-live-test.md. Do not describe either integration as verified yet. Keep credentials on a server; the app can use HTTP through a small proxy without requiring a Python SDK in the iPhone app.
