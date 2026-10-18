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

- [ ] Write native tests for valid and invalid drafts, nulls, sample provenance,
      72% four-seam fixture, reach suppression, and release-height drift.
- [ ] Run `swift test --filter TrainingFlowTests`; expect missing-type errors.
- [ ] Import the unchanged shared validator, contracts and assessor from `c49cdab`.
- [ ] Bundle an IIFE exposing JSON-in/JSON-out validation and assessment.
- [ ] Implement native Codable contracts and the JavaScriptCore boundary.
- [ ] Repeat the selected test command; require all tests passing.

## Task 2: Native API and fitted-pitch reuse

**Files:** core `Training/CoachingClient.swift`, `Training/SessionTaskCache.swift`,
corresponding `CoachingClientTests.swift` and `SessionTaskCacheTests.swift`.

**Interfaces:** `CoachingContext(profile:plan:assessment:)`, `CoachingClient`,
`SessionTaskCache<Key,Value>.value(for:load:)`.

- [ ] Test JSON payload shape, existing endpoint paths, fallback on server/network
      errors, absent configuration, shared in-flight work, cache reuse, and retry.
- [ ] Run new tests and observe expected failures before implementation.
- [ ] Add the typed API adapter and a cache scoped to one immutable profile.
- [ ] Run the corresponding native tests; require all tests passing.

## Task 3: Native entry and feedback navigation

**Files:** app `Training/TrainingFlowModel.swift`, `ThrowEntryView.swift`,
`FocusAssessmentView.swift`, `GripViewer/GripViewerView.swift`, Xcode project.

**Interfaces:** Entry receives a `TrainingFlowModel` with the existing `GripPose`
and `GripPlan`. Results receive the same model and a snapshot `FocusAssessment`.

- [ ] Add a persistent studio action and preserve one draft per selected pitch.
- [ ] Build compact native entry fields, sample/real confirmation, inline errors,
      add/remove throw, and a feedback action using the existing validator.
- [ ] Render feedback with the same `GripSceneView` and `pose.id`, map colors,
      zone selection, one action, existing AI calls and back-to-entry loop.
- [ ] Add only the new source references to the Xcode project; preserve signing.
- [ ] Run `xcodebuild ... -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build`.

## Task 4: Review and verification

- [ ] Run the imported TypeScript tests and native tests; read complete summaries.
- [ ] Review input validation, stale tasks, provenance, model identity, and retries.
- [ ] Request a fresh whole-change code review and fix material findings.
- [ ] Verify bundle ID, local signing, Git history and diff, and build again if fixes require it.
- [ ] Document local API startup and remaining phone-only verification.
