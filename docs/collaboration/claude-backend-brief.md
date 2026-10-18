# Claude Code: GripIt backend handoff

## Your assignment

Build the backend while Codex builds real Perceptron photo reading and the native app integration. Work only in the designated Claude worktree, on `claude/mongodb-backend`. Read `backend-contract.md` before implementing. Do not switch the original checkout's branch or run Xcode.

Jared wants a working demo of real accounts and saved progress using MongoDB. The app cannot be published right now, but it runs from Xcode on his iPhone. Real payment processing is out of scope. Claude is a separate session; Codex cannot send you messages automatically. Coordinate through committed status files and the agreed contract.

## Product and actual current state

GripIt is for baseball pitchers training with Rapsodo. It connects a hand-fitted grip with throw measurements and a clear next action.

1. Step 1 measures the hand using on-device MediaPipe landmarks, synchronized TrueDepth, camera calibration and multi-view stability/coverage checks. It produces HandProfile in millimeters. Keep it.
2. Step 2 solves a grip for the selected pitch and renders a personalized hand holding a baseball. It is native SwiftUI and SceneKit, not a web Three.js page. Its optimized fit/render cache and interactive finger tips came from the teammate's Step 2 branch and are already merged. The user reports roughly three-second fitting in their demo; that is an observation, not a backend performance promise.
3. Step 3 accepts editable throw readings and photo uploads. Its existing scan animation copies bundled fixture values rather than performing OCR. Codex will replace that path with actual Perceptron Mk1.5 extraction, preserving user confirmation and manual fallback.
4. Step 4 reuses the Step 2 model and overlays rule-based feedback. It evaluates all rows currently included for the selected pitch in the current session, using per-metric medians. It does not regenerate the mesh from the newest throw or automatically include account history. Consistency checks require at least three throws. Keep saved sessions separate unless the user explicitly loads one.

Four-seam, two-seam, slider and changeup are supported. Sample and real/manual sources remain separate; importing a different source already prompts before replacing existing entries. Do not mix sample history with real performance silently.

The design is the approved B / Glass theme: pine green, white text, soft depth, floating panels and consistent glass buttons. Codex owns all native account/plan screens, matching this theme. No website redesign is requested.

All AI coaching/chat was removed. Feedback uses deterministic TypeScript rules bundled into JavaScriptCore on the device. Perceptron is for reading numbers from report images, not coaching or generating hand measurements.

## What was tested about Perceptron

Mk1.5 hand keypoint tests misplaced joints, so MediaPipe remains. Egocentric is unavailable to this account and is explicitly excluded. Actual photo OCR succeeded on the bundled baseball image twice, reading all six displayed values and leaving missing values null. Another report missed tiny chart labels until a manually selected crop enlarged them. Do not claim generic automatic cropping or universal OCR accuracy is solved.

The standard Node fetch endpoint works. Codex owns the provider implementation. API credentials stay on the server. Jared authorized a $5 testing budget; completed inference estimates remain below one cent, not a live billing balance. Do not run paid provider tests, add another provider, or alter keys independently.

See `docs/research/2026-10-18-perceptron-live-test.md` for evidence and limitations. `PERCEPTRON_API_KEY2` is the working local entry; the original `PERCEPTRON_API_KEY` entry is malformed. Never print either. Do not copy the root environment file into your worktree.

## Backend deliverables

Create a self-contained Node/TypeScript service under `backend/`, with its own package.json, lockfile, tests, TypeScript config, README and `.env.example`. Keep root dependencies and scripts untouched so Codex's work does not collide.

Use MongoDB Atlas for durable data. No cluster exists yet. Prepare the service, indexes, migrations/setup commands and tests first; provide a concise Atlas setup checklist for Jared. Do not sign up using his email, create paid resources, or claim cloud verification without an actual connection. If credentials are unavailable, complete all independent work and report the exact remaining setup. Do not fake persistent storage as a successful Atlas integration.

Use Better Auth email/password with its MongoDB adapter and bearer session support. Verify the current installed adapter import and supported versions against official documentation. Wrap auth in the public endpoints in the contract so native code does not depend on auth-library response details. Passwords are hashed by the library; secrets and sessions must not appear in logs. Real email delivery/password reset is outside this first demo; describe that limitation honestly.

Implement authenticated user-scoped session save/list/load/delete. Store the HandProfile, per-pitch ThrowSessionDraft and optional assessment snapshot. Preserve existing IDs, source labels, units and schemas. Do not store raw hand videos, depth frames, rendered meshes or uploaded photos for this milestone. Reconstruct the model from its saved profile on device. A stored assessment is a historical display snapshot, never trusted entitlement data or proof that current rules ran.

Implement plan and usage APIs:

| Plan | Successful photo scans per UTC day | Completed throw reviews per UTC day |
| --- | ---: | ---: |
| Free | 3 | 3 |
| Pro | 20 | 20 |

These exact product limits were chosen by Jared on October 18. They are unrelated to coaching thresholds. Return server counts and the UTC reset timestamp; the app must not decide entitlement from a local preference. Upgrading is a clearly identified demo upgrade without a card, charge or billing provider. Upgrading keeps the same day's usage rather than resetting it.

Photo scans and reviews are separate quotas. Adding a throw row or loading a local sample is not itself a photo scan or a review. Codex will prepare sample throws so a presenter can add them, run repeated reviews, reach the Free limit, and demonstrate Pro. Reopening an already completed review or retrying a request must not consume usage again. The real server counters must back the limit screen. No automatic quota resets for the demo.

Reserve photo usage atomically before a provider request so concurrency cannot bypass the cap. Commit it only for a successful validated extraction; release the reservation on failure. A successful provider result can count even if the user later cancels adding the throw. Review requests consume usage once before a new locally validated Step 4 review is displayed. Keep an idempotent operation ledger with unique user/kind/request keys and a payload digest. A reused key with different input is a conflict. Resolve stale reservations explicitly without silently releasing an active provider operation. Add tests for failure, retry, concurrency and cross-user access.

Mount Codex's extractor behind auth and photo quota enforcement. Until that module is committed, use an injected fake provider in tests and return an explicit service-unavailable error for live OCR. Do not substitute fixture numbers. The provider boundary is defined in the contract.

Provide health/readiness checks, bounded bodies, request timeouts, sanitized errors and startup validation. A local API must listen on a host reachable by an iPhone on the same Wi-Fi. A hosted API needs HTTPS and environment-based credentials. Prepare deployment instructions/configuration; do not publish or create paid hosting without Jared's instruction.

## Ownership

Claude owns `backend/**` and `docs/collaboration/claude-status.md` only. Codex owns `services/photo-reading/**`, `scripts/photo-demo-server.ts`, all native files, root config and dependencies, OCR research docs, and `docs/collaboration/codex-status.md`.

`docs/collaboration/backend-contract.md` is shared but Codex maintains it to prevent simultaneous edits. Suggest any required change in your status file before changing endpoint behavior. Prefer the agreed interface over an auth framework's default public interface. Never modify shared rules, `src/`, renderer code, handInstructions.md, or native signing files.

## Reading order and stale context

Read this brief and the contract first, then `HANDOFF.md`, `handInstructions.md`, `PRODUCT.md` and `docs/superpowers/plans/2026-10-18-grip-feedback-rules.md`. The last three product/history docs contain historical plans, not current implementation status. In particular, HANDOFF's patch replay, merge work, AI question box, absent severity data and 207-test instructions are historical. Do not replay patches, recreate deleted branches, reintroduce chat, or undo the completed Step 2/UI work.

Inspect these current files for the actual boundaries:

- `ios/GripIt/Training/TrainingFlowModel.swift`: cached hand model and per-pitch throw sessions.
- `ios/GripIt/Training/ThrowEntryView.swift`: upload, review, confirmation and sample/source behavior.
- `ios/GripItScannerCore/Sources/GripItScannerCore/Training/ThrowRecord.swift`: native draft and record shapes.
- `ios/GripItScannerCore/Sources/GripItScannerCore/Contracts/HandProfile.swift` and `shared/contracts/handProfile.ts`: profile schemas.
- `shared/throwEntry.ts`: draft validation and records; it derives gyro/efficiency for downstream use, which OCR must not confuse with visible source readings.
- `shared/focus/metrics.ts`, `assess.ts`, `gripFeedback.ts`: existing deterministic review.

Six engine rules apply throughout: never invent coaching thresholds; guard rules sharing a cause; respect mirrored handedness targets; no wrist severity; no slider advice asking the index to drive/press/grip; source all coaching copy from handInstructions.md. This backend work needs no changes to any of them.

## Git, checks and handoff

See README.md in this directory for collaboration commands. Use Jared Shum <jaredshum101@gmail.com> for commits and exact paths for staging. Commit at useful milestones: service/auth, persistence, plans/quotas, mounted OCR/integration. Update your own status file with hashes, checks, setup blockers, environment variable names and precise run commands. Never include credential values.

Run backend tests with at most two workers. Test auth sign-in/out, expiration and unauthorized requests; ownership isolation; persistence across server restart; profile/source round trips; atomic quota enforcement at the boundary; idempotent retries and conflicts; reset-day behavior with an injected clock; failed provider calls; plan changes preserving usage; and disabled demo mutations when the demo flag is off. Keep real provider calls mocked.

Do not run simulator downloads, Xcode builds, broad process killing or another copy of the app. Codex coordinates the final combined tests and native build, serially. The Mac previously overheated during parallel builds.

Official references to verify during implementation:

- https://better-auth.com/docs/authentication/email-password
- https://better-auth.com/docs/plugins/bearer
- https://github.com/better-auth/better-auth/blob/main/docs/content/docs/adapters/mongo.mdx
- https://www.mongodb.com/docs/atlas/tutorial/deploy-free-tier-cluster/
