# Codex status

Updated October 18, 2026.

Branch: `codex/perceptron-photo`. Folder: `/Users/jshum/Desktop/code-folders/gripit`.

## Prepared

- Published the parallel-work brief, ownership rules and API contract.
- Recorded the approved Free 3 / Pro 20 daily limits for each of photo scans and throw reviews.
- Recorded session-wide Step 4 aggregation and the repeated-sample demonstration flow.
- Preserved the existing local native signing changes and main demo.
- Added existing research reports to the collaboration baseline. Standard Node fetch and Mk1.5 image OCR were tested separately; hand landmark replacement is excluded.
- Registered Claude's worktree at `/Users/jshum/.codex/worktrees/c9ea/gripit` on `claude/mongodb-backend`. Shared starting documentation commit: `0d8b368`.

## Preparation checks

`npm install`: success, zero reported vulnerabilities. `npm test -- --maxWorkers=2`: 193 passed, 15 files. `npx tsc -b`: exit zero. Documentation preparation only; no new native build or app feature is being claimed.

## Remaining integration

1. Integrate Claude's auth/session/usage service after its tested milestones exist.
2. Add native account/session UI with Keychain tokens, daily-limit display and demo upgrade. The core photo client already supports bearer injection; the review screen currently connects to the standalone local photo service without a session token.
3. Test three completed reviews, blocked fourth and Pro unlock against actual backend counters. Quick sample stacking is implemented; quota UI is not.
4. Complete a physical-phone network/touch walkthrough, then integrate the tested combined result into main. Do not claim cloud persistence until Atlas is configured.

## Extractor milestone

Implemented the agreed `createPhotoExtractor({ apiKey, fetchImpl? })` export in `services/photo-reading/extract.ts`, with types and sanitized `PhotoExtractionError` codes in the adjacent files. Claude can now import the real module and mount it behind auth, image validation, quota reservation and idempotency. It makes one Mk1.5 call, allows 30 seconds, honors cancellation, and never automatically retries.

At the module-only milestone, `npx vitest run services/photo-reading/extract.test.ts --maxWorkers=2` passed 27 tests and root typechecking passed. Optional/missing values remain null; invalid values are cleared with warnings; all-empty or malformed output is rejected. Later milestones below add response-body timeout/size tests and complete the local/native path.

The module milestone is commit `6eb812b`. Claude can merge a tested Codex milestone into its branch to mount this export. Do not copy or reimplement it.

## Native and local service milestone

- Real OCR now fills editable photo-review fields for both uploads and the bundled baseball sample. Cancel does not append; confirmation validates; Retry preserves corrections. Missing fields stay blank.
- The two-second dotted scan loops during a request, then reveals real returned fields over two seconds. Reduce Motion skips animation/delay. There is no two-second network promise.
- Added the local development server (`npm run photo:dev`), bounded bodies/media checks, sanitized errors and bounded successful-request replay. Default host is 127.0.0.1; explicit GRIPIT_PHOTO_HOST=0.0.0.0 allows the same-Wi-Fi iPhone. This helper has no accounts/entitlements and must not be publicly deployed. It was stopped after verification.
- Added Add sample throw: one existing demo throw per tap, retaining previous throws, fresh IDs, empty-row reuse and confirmation before replacing personal entries. No new sample values or provider calls.
- Replaced the stale native-training-flow.md instructions about AI coaching with the actual native/photo-service setup.
- Read Claude's backend design commit `b64ce44`. Its root test-globbing concern is addressed: npm test now excludes backend/** so backend tests run through their own package/config. No shared contract change was needed.
- Claude's proposed review header check matches the contract: native integration will send Idempotency-Key equal to reviewId. A deliberate new review gets a new ID; returning to its result does not consume another review.

Verified: 229 TypeScript tests across 17 files, root typecheck exit zero; 104 native core tests, zero failures; signed iOS build-for-testing succeeded. Read-only review reported no critical/important findings. Image orientation/HEIC conversion and full phone interaction still need device checks.

One new live HTTP OCR call returned all six bundled baseball values correctly, with gyro/height/score null, in about 1.48 seconds. Identical retry reused the result. Estimated call cost $0.00040695; all 14 recorded inferences total about $0.0085128, not a verified billing balance. No physical phone was launched automatically, no API key was committed, and main remains at ab763a9.
