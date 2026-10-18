# Perceptron photo reading preparation and implementation plan

> **For agentic workers:** Use the executing-plans skill to implement one milestone at a time. The user requested preparation now; this file records the next implementation tasks, not completed functionality.

**Goal:** Read actual Rapsodo image values with Perceptron Mk1.5 and populate the existing native Step 3 confirmation flow without changing hand scanning or rule-based feedback.

**Architecture:** An isolated TypeScript extractor sends image bytes to Perceptron and validates the response. Claude's authenticated MongoDB API mounts it behind per-user usage enforcement. A Swift URLSession client maps readings into the existing editable ThrowDraft. A local standalone server supports development before the backend is ready.

**Tech stack:** Node fetch, TypeScript, Vitest, Swift Foundation/URLSession, SwiftUI, existing JavaScriptCore rules and SceneKit renderer.

## Constraints and decisions

- Native Xcode app, not a browser rewrite. MediaPipe/TrueDepth stay. Mk1.5 only; no Egocentric, AI coaching or chat.
- API protocol, ownership, quota semantics and persistence: `docs/collaboration/backend-contract.md`.
- Free has 3 scans and 3 reviews daily; Pro has 20 each. No real charge. Counts come from the backend.
- Step 4 continues evaluating all included rows for the selected pitch/current session. Preserve sample/manual separation and all existing rule/hand-fit behavior.
- Images must really be read, including bundled samples. No filename/value lookup or fixture fallback disguised as OCR. Missing measurements remain absent.
- Existing small-label OCR limitation needs editable manual fallback. Automatically finding chart crops is a separate feature and has not been validated.
- Keep the scan bar's one-second outward / one-second return motion. During network delay it continues; populate fields only after validated values arrive, with a two-second reveal. Respect Reduce Motion. Do not promise all network requests finish in two seconds.
- API key stays server-side. No automatic paid retries. Paid testing remains within Jared's $5 total budget; inspect the existing experiment ledger first.
- Exact-path staging and Jared's commit identity. Do not stage native project/Info.plist signing changes. Run builds serially, at most two jobs, scratch/derived output under /private/tmp.

## Preparation completed

- [x] Inspect the current native entry, draft, metrics and assessment boundaries.
- [x] Read HANDOFF.md, PRODUCT.md, handInstructions.md, original rule plan and Perceptron research. Record historical contradictions in Claude's brief.
- [x] Verify current dependencies, 193 tests and TypeScript baseline.
- [x] Write backend handoff, contract, ownership and separate status files.
- [ ] Register Claude's isolated worktree and branch from the shared documentation commit.

## Milestone 1: real extractor with a testable provider boundary

**Files to create:**

- `services/photo-reading/types.ts`: contract DTOs and field keys.
- `services/photo-reading/errors.ts`: sanitized typed failures.
- `services/photo-reading/extract.ts`: createPhotoExtractor(options), strict structured-output request, timeout and response mapping.
- `services/photo-reading/extract.test.ts`: mocked HTTP tests.
- `scripts/photo-demo-server.ts`: local-only development wrapper, raw JPEG/PNG requests, bounded bodies and health endpoint.
- `scripts/photo-demo-server.test.ts`: HTTP contract tests using an injected extractor.

**Existing files to inspect/modify as necessary:** root package.json (local server command), .env.example (server-only variable names), tsconfig.json (new service typechecking). Do not modify root dependencies from Claude's branch.

- [ ] Write failing tests using injected fetch: a complete response, absent values staying null, small/unreadable labels, invalid numeric/string values, malformed JSON, non-stop completion, provider rejection, timeout, cancellation and key redaction. Example acceptance: a response with `gyroDegree: null` and `spinEfficiencyPercent: 93.8` must still return a null gyro.
- [ ] Run `npx vitest run services/photo-reading/extract.test.ts --maxWorkers=2` and confirm the new tests fail for the missing implementation.
- [ ] Implement the contract exports. Use https://api.perceptron.inc/v1/chat/completions, model perceptron-mk1.5, reasoning_effort none, temperature 0 and strict nine-field JSON schema. The request contains image bytes and label/unit instructions, never the expected fixture readings. Use the tested prompts saved under work/experiments/perceptron-20261018 as reference.
- [ ] Validate only visible fields; reuse existing broad draft typo bounds without returning validateThrow's derived gyro/efficiency. Return warnings for missing/unreadable fields. Provider-side failure is a typed sanitized error rather than raw text shown to the user.
- [ ] Implement a local development wrapper on port 5173, explicitly separate from authenticated backend operation. Reuse body/media validation with tests. Never deploy this wrapper publicly. Load the working key entry explicitly without logging it; expose no key in app responses or bundles.
- [ ] Run focused tests and `npx tsc -b`. Commit exact new/modified paths and update codex-status.md so Claude can mount the real extractor.

## Milestone 2: native photo reading and confirmation

**Files to create:**

- `ios/GripItScannerCore/Sources/GripItScannerCore/Training/PhotoReadingClient.swift`: Sendable Codable DTOs, injectable URLSession transport, HTTP/error mapping and reading-to-draft conversion.
- `ios/GripItScannerCore/Tests/GripItScannerCoreTests/PhotoReadingClientTests.swift`: deterministic response/mapping/network failure/cancellation tests.

**Files to modify:** `ios/GripIt/Training/ThrowEntryView.swift`, and `docs/native-training-flow.md` to replace stale local AI-coaching instructions. Swift package discovers new core files without changing the app project file.

- [ ] Write failing Swift tests for the contract, all-null optional readings, clock strings, signed movement, malformed server JSON, 401/429/provider errors and cancellation.
- [ ] Implement the URLSession client using the configured GripItAPIBaseURL and injected bearer token. Preserve explicit null fields in JSON and blank editable fields in ThrowDraft. Never infer height/gyro from another number during OCR mapping.
- [ ] Replace prepareReadings fixture copying with a real request for all photos, including the bundled baseball sample. Preserve exact sample-source classification only for source identity, never answer values.
- [ ] Continue scanning while the request runs; reveal returned values across two seconds after success. On failure stop scanning, show Retry/manual entry, and keep user edits. A cancelled/dismissed task must not add a throw or overwrite another photo's edits. Reuse request ID for retry of the same operation.
- [ ] Serialize one native core test run and device build with two jobs, writing output under /private/tmp. Do not claim physical camera/upload behavior from compilation alone.
- [ ] Make a bounded actual HTTP OCR check using the local server and bundled image, with no expected answers in the request. Check all six visible values and missing-value behavior. Record cost estimate and avoid duplicate calls if saved evidence suffices.
- [ ] Commit tested native/client changes and update codex-status.md.

## Milestone 3: accounts, saved progress and demo limits integration

Claude's backend must have tested auth, persistence, usage and plan endpoints first. Codex owns native integration; do not silently expand Claude's file ownership.

**Files to modify:** `ios/GripIt/GripItApp.swift`, `ios/GripIt/Training/TrainingFlowModel.swift`, `ios/GripIt/Training/ThrowEntryView.swift`. Add client/model files in the core package and tests there; avoid unreferenced native source files that require project edits.

- [ ] Read Claude's committed status, backend README, tests and contract deviations. Integrate only a tested milestone, resolve contract differences once, and run its documented checks.
- [ ] Add native sign-up/sign-in/sign-out using Keychain session storage, restore saved sessions without source mixing, and keep the pine/glass theme. Expired sessions ask for sign-in without deleting the local draft.
- [ ] Read usage before expensive actions, handle authoritative 429 responses and display remaining scans/reviews plus reset time. A new review uses a new reviewId; reopening an existing result uses its existing result without consumption.
- [ ] Provide quick sample stacking using existing sample data, visibly identified as samples. Do not invent readings to promise improvement. Demonstrate three completed reviews, a blocked fourth, then the no-charge Pro upgrade with the same day's used counts. Local sample loading itself makes no provider call and uses no photo-scan quota.
- [ ] Test Free/Pro, retry, sign-out/sign-in restore, account isolation and session-wide assessment. Run root tests/typecheck, backend checks, required native bundle generation if shared code changes, core tests and device build serially. Use the same root Xcode project for the phone check.
- [ ] Review staged paths and the combined diff. Merge into main only after checks pass and report any remaining device/cloud limitations. Retain recovery archives and the original Step 2 detached copy.
