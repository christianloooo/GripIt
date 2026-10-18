# Native training flow

GripIt is the SwiftUI iPhone app at `/Users/jshum/Desktop/code-folders/gripit/ios/GripIt.xcodeproj`. Open that project for the demo. The browser UI under src/ is a separate surface.

## What runs where

1. MediaPipe finds hand landmarks on the phone. TrueDepth and camera calibration map synchronized observations into measured millimeters. Existing coverage, identity and stability gates produce HandProfile.
2. GripPoseSolver fits the selected grip. GripStudioSession caches the solved pose and derived rendering data per hand and pitch. The native SceneKit view supports rotation, zoom and interactive finger tips.
3. A selected report photo is sent to the photo service. Perceptron Mk1.5 reads visible numbers, and the app fills the existing editable draft. The user checks and confirms before a throw is added. Sample and personal throws retain their separate source behavior.
4. NativeFocusEngine evaluates all included rows for the selected pitch in the current session, using per-metric medians. It reuses the Step 2 model and displays the deterministic rules' heatmap and next action. Saved account history is not automatically added to the current assessment.

AI coaching and chat are removed. Perceptron reads report numbers only; it does not supply hand dimensions, render meshes, calculate severity or write coaching advice. The existing JavaScriptCore rule bundle remains authoritative for feedback.

## Photo reading

Both uploads and the bundled baseball photo go through real extraction. Exact bundled-image recognition is retained only for the sample label/source. It does not supply the photo-reading answers.

The provider key stays on the server. POST /api/photos/read accepts JPEG/PNG bytes, Content-Type and an Idempotency-Key. The native client allows 45 seconds; the provider call allows 30 seconds. Reusing a successful request ID with the same image reuses the result, avoiding another paid call. There are no automatic paid retries.

Missing/unreadable values remain blank, including height and gyro angle when the image does not show them. Extraction does not derive one displayed number from another. Existing confirmed-throw processing may still calculate gyro/efficiency as before. The user can correct any field before confirmation. Small chart labels can require manual entry; automatic chart cropping has not been implemented.

The dotted scan bar crosses outward in one second and returns in one second. It continues while the network request is running. Once actual values arrive, the app reveals them across a two-second pass. Reduce Motion skips animation and reveal delay. A provider request is not guaranteed to finish in two seconds.

Failures stop animation and unlock manual entry, with a Retry button. Retry keeps existing user corrections. Dismissing the review cancels its task and adds no throw. Confirmation still runs the existing input validator and source-replacement protection.

Add sample throw adds one existing demo reading at a time, retaining earlier throws and filling empty rows first. Further taps cycle the existing three demo readings with fresh throw IDs. Switching from personal entries asks before replacement. This is local sample data, not photo extraction, and makes no provider call.

## Local photo development service

The helper under scripts/photo-demo-server.ts is for local OCR development while Claude builds the authenticated backend. It has no account or plan service and must not be publicly deployed. Its bounded in-memory retry cache does not replace durable account usage enforcement.

From the original repository folder:

```sh
npm install
npm run photo:dev
```

The default address is http://127.0.0.1:5173. Configure a server-only PERCEPTRON_API_KEY in the ignored .env file. This local test setup also recognizes the verified PERCEPTRON_API_KEY2 entry. Malformed/missing credentials stop startup without printing them.

For an iPhone on the same Wi-Fi, explicitly allow LAN access:

```sh
GRIPIT_PHOTO_HOST=0.0.0.0 npm run photo:dev
```

The native GripItAPIBaseURL comes from the target's GRIPIT_API_BASE_URL build setting. The current local signing configuration uses http://Jareds-MacBook-Pro.local:5173. The phone and Mac must be reachable on the same network; allow the local-network prompt. Do not run Vite on the same port at the same time. Stop this helper when no longer testing.

GET /health reports mode local-photo-development. The helper rejects browser-origin requests, validates image headers/body size, and sanitizes provider failures. It binds only to loopback unless LAN access is explicitly configured. It never logs image bytes or keys.

Do not commit local signing, bundle IDs or base-URL changes in ios/GripIt.xcodeproj/project.pbxproj or ios/GripIt/Info.plist.

## MongoDB collaboration

Claude's separate backend worktree is `/Users/jshum/.codex/worktrees/c9ea/gripit`, branch claude/mongodb-backend. It owns real accounts, saved progress, server-side usage and the no-charge demo upgrade. Codex owns the extractor and native client/UI. See docs/collaboration/README.md and backend-contract.md for the exact split and current status.

Approved daily limits are Free: 3 photo scans and 3 throw reviews, Pro: 20 each, resetting at UTC midnight. A local sample row costs neither operation; a new completed review counts once. Native account/usage screens are a later integration milestone and are not supplied by the standalone helper. No payment provider is involved.

## Checks

Run checks serially to keep the Mac responsive:

```sh
npm test -- --maxWorkers=2
npx tsc -b
DEVELOPER_DIR=/Users/jshum/Desktop/Xcode.app/Contents/Developer /Users/jshum/Desktop/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test --package-path ios/GripItScannerCore --scratch-path /private/tmp/gripit-mvp-core --jobs 2
/Users/jshum/Desktop/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project ios/GripIt.xcodeproj -scheme GripIt -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/gripit-mvp-ios -jobs 2 build-for-testing
```

Run npm run ios:focus whenever shared rule code changes. This integration does not change those rules. Mocked HTTP tests do not make paid API requests. Live OCR evidence is recorded separately under the ignored work/experiments directory, with a sanitized research summary under docs/research. Compilation does not verify the physical camera, phone network permission or full touch flow.
