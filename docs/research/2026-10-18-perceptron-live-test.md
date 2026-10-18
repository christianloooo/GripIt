# Perceptron Mk1.5 live test results

Date: October 18, 2026. Standalone evaluation only. No app, scanner, model-fitting, rule-engine or main-branch code was changed.

## Outcome

The second key works with the official Perceptron Python SDK 0.4.0 and the standard perceptron-mk1.5 model. Authentication, an actual text completion, model metadata and image inference all succeeded. No Egocentric access was requested or used.

Keep MediaPipe for Step 1 with the tested configuration. Proceed toward real photo OCR for Step 3, retaining editable confirmation and missing-value handling. These small tests establish feasibility, not production accuracy or full iPhone integration.

## Connection troubleshooting

The initial urllib GET /v1/models?extended=true with the original entry received Cloudflare HTTP 403 / error 1010. The original environment entry contains internal whitespace; it was not used again. A proper dotenv parser, the new PERCEPTRON_API_KEY2 entry, and the official SDK's normal client successfully completed requests. Both credential and client changed, so the exact cause of the earlier block is not isolated. The earlier conclusion that provider intervention was necessarily required was premature. The saved original error is historical, not the current access status.

The working setup uses bearer authentication through the standard API endpoint and SDK default transport. Credentials remain in the Git-ignored .env file and are not copied into reports or the app.

## Step 1: hand landmark comparison

Used public Google MediaPipe hand photos, rather than user camera uploads. Four cases come from three source photos, including a mirrored derivative. The baseline uses the same public/mediapipe/hand_landmarker.task file referenced by the iOS project, executed with Python MediaPipe 1.1.1 on this Mac. This is not a timing benchmark of the iPhone runtime.

Mk1.5 received image bytes and a strict schema describing the app's 21 named anatomical landmarks in its documented 0-1000 image coordinates. No MediaPipe positions or expected answers were included. Initial requests used no reasoning; one follow-up used low reasoning and an explicit instruction to check finger identities. Image model responses were compared numerically and drawn over the input photos for visual inspection.

| Case | MediaPipe time on Mac | Mk1.5 request time | Observation |
| --- | ---: | ---: | --- |
| back-right | 0.0083 s | 2.312 s | Mk1.5 places some finger joints on the wrong finger or outside the visible finger. |
| back-mirrored | 0.0093 s | 2.099 s | Mk1.5 keeps the right-hand label after mirroring; MediaPipe changes to left. Several joints are misplaced. |
| palm-crop | 0.0112 s | 2.057 s | Mk1.5 clusters multiple finger locations away from the visible fingertips. |
| pointing_up | 0.0125 s | 2.123 s | Both find a hand, but several Mk1.5 locations on the curled fingers disagree visibly with their anatomy. |

All initial Mk1.5 responses contained 21 uniquely named points within numeric bounds. Valid JSON and complete point counts did not establish correct anatomy. The low-reasoning back-hand follow-up took 4.099 seconds, still misplaced joints and changed the physical handedness label incorrectly. This does not prove every possible prompt fails, but it does not justify replacing the working specialized tracker.

The saved mean point disagreements against MediaPipe are not ground-truth errors. No measured hand dimensions, paired TrueDepth frames, physical reference measurements, live tracking continuity or side-view scan completion were tested. Cloud request times of roughly two seconds per image also do not support an immediate replacement for the scanner's current up-to-eight-frame-per-second input flow. Captured keyframe refinement would be a different design requiring its own accuracy evidence.

Side-by-side PNG overlays, raw sanitized JSON, source image files and the executable comparison script are under work/experiments/perceptron-20261018/. Green is MediaPipe, red is Mk1.5. The results are in the same image coordinate frame.

Image sources:

- https://storage.googleapis.com/mediapipe-assets/right_hands.jpg
- https://storage.googleapis.com/mediapipe-assets/woman_hands.jpg
- https://storage.googleapis.com/mediapipe-assets/pointing_up.jpg

Crop/mirror transforms are explicit in evaluate_hands.py. The thumb_up.jpg asset was downloaded but not used in inference.

## Step 3: actual image OCR

The API was given image bytes and field/unit instructions, without fixture values, filenames as lookup keys, or example answers. Expected values were checked locally against the visible images. The test uses strict structured output and null for unreadable or absent fields.

| Input | Result | Request time |
| --- | --- | ---: |
| Bundled baseball rapsodo1.png | All six displayed readings match; missing gyro, height and score remain null. | 1.057 s |
| Original baseball rapsodo2.webp | Speed, total spin, clock and efficiency match. Two small chart break labels were missed and returned null. | 2.166 s |
| Original screenshot with different readings, rapsodo1.webp | All visible requested readings match, including negative gyro. True spin is not substituted for total spin; stride length is not mistaken for release height. This is a test-only original image, not a new UI fixture. | 0.691 s |
| Partial crop with velocity and spin removed | Visible remaining values match; removed velocity and total spin stay null. | 0.740 s |
| Magnified crop of the original baseball chart labels | Correctly reads horizontal 18.6 in and vertical 13.8 in; all other fields null. | 0.655 s |
| Fresh repeat of bundled baseball sample | All six readings match again, absent fields remain null. | 1.135 s |

The recovered chart crop was explicitly selected by us. Automatic detection of these regions was not tested. A production implementation needs a crop/review strategy or manual fallback for small labels. These six requests are a small sample and include derived images; they do not establish an overall OCR success percentage.

The existing Step 3 photo review can consume extracted values as ThrowDraft without changes to the Step 4 rules. Future implementation needs a small server proxy for the key, validated field mapping, source identity and units, user confirmation, cancellation and failure states. The two-second scan effect must remain tied to real request completion rather than showing guessed values before the API returns. No request-time guarantee follows from these timings.

## Usage and reproduction

Completed model inference requests: 12. Estimated total model cost: $0.0080967, below the authorized $5 ceiling. Pricing comes from authenticated Mk1.5 metadata: $0.15 per million input tokens and $1.50 per million output tokens. The estimate uses returned usage and does not verify the account's actual balance or billing invoice. Testing stopped at the local twelve-request cap.

Saved artifacts:

- work/experiments/perceptron-20261018/mk15-key2-smoke.json
- work/experiments/perceptron-20261018/mk15-model-info.json
- work/experiments/perceptron-20261018/hand-summary.json
- work/experiments/perceptron-20261018/ocr-summary.json
- work/experiments/perceptron-20261018/usage-ledger.json
- work/experiments/perceptron-20261018/probe_mk15.py
- work/experiments/perceptron-20261018/evaluate_hands.py
- work/experiments/perceptron-20261018/evaluate_ocr.py

The scripts use an isolated local venv and key 2. The hand/OCR harness reuses saved results for identical labels rather than rerunning calls, and applies a request-count ceiling and conservative cost reservation using authenticated model limits/prices. Budget constants are test spending controls, not coaching thresholds. Review the ledger before intentionally making additional paid requests.

Official client reference: https://docs.perceptron.inc/perceptron-mk1.5/guides/python/getting-started
