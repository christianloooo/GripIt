# Native Training Flow Implementation Plan

> **For agentic workers:** Use executing-plans inline and request one whole-change review.

**Goal:** Connect the native grip studio to Rapsodo entry and feedback using the existing model and assessment code.

**Architecture:** SwiftUI screens own navigation and entry drafts. The core package wraps the existing TypeScript validator and assessor in JavaScriptCore. AI requests retain the existing server contracts.

**Tech Stack:** SwiftUI, SceneKit, JavaScriptCore, TypeScript, esbuild, URLSession.

## Global Constraints

- Preserve the approved spec and all merged UI and renderer updates.
- No AI keys in the app, database, accounts, shared push, or remote merge.
- Step 4 uses the identical Step 2 pose, profile, and pitch.
- Retain nulls, sample provenance, real reach limits, and prototype labels.
- Signing remains local.

## Task 1: Shared engine and native contracts

**Files:** `shared/focus`, `shared/contracts`, `shared/throwEntry.ts`,
`scripts/build-native-focus.mjs`, core `Training` and `Resources/focus-engine.js`,
`Tests/GripItScannerCoreTests/TrainingFlowTests.swift`.

**Interfaces:** `ThrowDraft`, `ThrowSessionDraft`, `ThrowRecord`,
`FocusAssessment`, `NativeFocusEngine.validate(_:)`,
`NativeFocusEngine.assess(pitch:records:zones:gripPlanId:)`.

- [x] Write native tests for valid and invalid drafts, nulls, sample provenance,
      72% four-seam fixture, reach suppression, and release-height drift.
- [x] Run `swift test --filter TrainingFlowTests`; expect missing-type errors.
- [x] Import the unchanged shared validator, contracts and assessor from `c49cdab`.
- [x] Bundle an IIFE exposing JSON-in/JSON-out validation and assessment.
- [x] Implement native Codable contracts and the JavaScriptCore boundary.
- [x] Repeat the selected test command; require all tests passing.

## Task 2: Native API and fitted-pitch reuse

**Files:** core `Training/CoachingClient.swift`, `Training/SessionTaskCache.swift`,
corresponding `CoachingClientTests.swift` and `SessionTaskCacheTests.swift`.

**Interfaces:** `CoachingContext(profile:plan:assessment:)`, `CoachingClient`,
`SessionTaskCache<Key,Value>.value(for:load:)`.

- [x] Test JSON payload shape, existing endpoint paths, fallback on server/network
      errors, absent configuration, shared in-flight work, cache reuse, and retry.
- [x] Run new tests and observe expected failures before implementation.
- [x] Add the typed API adapter and a cache scoped to one immutable profile.
- [x] Run the corresponding native tests; require all tests passing.

## Task 3: Native entry and feedback navigation

**Files:** app `Training/TrainingFlowModel.swift`, `ThrowEntryView.swift`,
`FocusAssessmentView.swift`, `GripViewer/GripViewerView.swift`, Xcode project.

**Interfaces:** Entry receives a `TrainingFlowModel` with the existing `GripPose`
and `GripPlan`. Results receive the same model and a snapshot `FocusAssessment`.

- [x] Add a persistent studio action and preserve one draft per selected pitch.
- [x] Build compact native entry fields, sample/real confirmation, inline errors,
      add/remove throw, and a feedback action using the existing validator.
- [x] Render feedback with the same `GripSceneView` and `pose.id`, map colors,
      zone selection, one action, existing AI calls and back-to-entry loop.
- [x] Add only the new source references to the Xcode project; preserve signing.
- [x] Run `xcodebuild ... -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build`.

## Task 4: Review and verification

- [x] Run the imported TypeScript tests and native tests; read complete summaries.
- [x] Review input validation, stale tasks, provenance, model identity, and retries.
- [x] Request a fresh whole-change code review and fix material findings.
- [x] Verify bundle ID, local signing, Git history and diff, and build again if fixes require it.
- [x] Document local API startup and remaining phone-only verification.

## Execution record

- Local integration branch preserves the user's personal signing as unstaged changes.
- Original Step 4 worktree remains unchanged; its existing dev server is used for AI testing.
- 49 web tests passed; the web production build and unsigned iOS build passed.
- The first complete native regression run passed 79 tests in about 205 seconds.
- Final focused run passed 18 tests after the nullable-field fixes.
- Live `/api/coach` returned rewritten coaching and a measured-hand explanation.
- Live `/api/ask` returned a context-aware answer. No provider or model was changed.
- Fresh review found no Critical or Important flow defect. The review's two encoding
  findings were reproduced with failing tests and fixed to preserve the approved
  v1 contract. No remaining review findings are deferred.
- Implementation decision: reuse the TypeScript engine in JavaScriptCore rather
  than maintain duplicate coaching rules in Swift. Cost: a committed generated
  bundle must be refreshed when shared source changes.
- Implementation decision: keep only session-scoped fitted poses, with no disk
  cache. Cost: a fresh hand session still performs its first fit.
- Device smoke testing remains unavailable: no simulator runtime is installed and
  the paired iPhone currently reports unavailable.

Final verification: all 80 native core tests passed after fixes (202 seconds);
49 web tests passed; web production build passed; unsigned iOS app build and
iOS build-for-testing passed. Local AI coach and follow-up endpoints succeeded.
The integration is retained locally on its named branch; nothing is pushed.
Personal signing and the local Debug API URL remain outside the source commit.
