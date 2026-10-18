# Coaching performance implementation plan

**Goal:** Reduce repeat AI latency while preserving the current native flow and provider.

**Architecture:** Existing proxy handlers plus bounded process-local and native caches.
**Tech stack:** TypeScript, Vite, existing Anthropic SDK, Swift concurrency.

## Constraints

- Preserve personal signing, display name, and API provider.
- Never cache failures or key by assessment ID alone.
- Six-second provider deadline, no automatic SDK retries.
- No rule threshold changes from unreviewed research.

## Tasks

- [x] Import existing Step 4 API and prompt modules into this branch; preserve contracts.
- [x] Write failing tests for bounded cache expiry/eviction, concurrent sharing and retry.
  Implement `ResponseCache<T>.get(key, work, cacheable)` and verify tests.
- [x] Add generation tests for model/input key changes and provider timeout settings.
  Integrate the cache and deadline in `api/_client.ts`.
- [x] Add request tests for methods, invalid shapes, limits and health. Implement
  `api/_http.ts` and shared dev/exported handlers; type-check API and shared sources.
- [x] Write native failing tests for repeated/concurrent coach requests and recovery.
  Implement a bounded actor cache in `CoachingClient.swift`, keyed by sorted body.
- [x] Run targeted native tests, all web tests/build, then signed app build.
- [x] Switch the local server to this integrated copy, test real cold/warm requests,
  update startup/limitations documentation, and install/launch the app if connected.

The later approved AI interpretation extension is implemented and reviewed.
Native 82-test suite passed; final coaching payload tests passed separately.
Web 79 tests and signed app/test builds passed. Installation and normal launch
succeeded. The opt-in phone test found a framework search-path defect and then a
case-sensitive hostname 403; both root causes were fixed. Lowercase-host health
and coaching calls now succeed. Automatic phone launches stopped after the user
raised concern; manual UI and post-fix phone networking verification remain.

Existing source modules are imported, not rewritten. New cache behavior uses
test-first verification. Execute inline within the existing isolated integration
branch. No remote push or deployment is part of this pass.
