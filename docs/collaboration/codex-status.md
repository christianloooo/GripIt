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

## Current checks

`npm install`: success, zero reported vulnerabilities. `npm test -- --maxWorkers=2`: 193 passed, 15 files. `npx tsc -b`: exit zero. Documentation preparation only; no new native build or app feature is being claimed.

## Next implementation

1. Test and implement the isolated extractor in `services/photo-reading/` against the contract.
2. Add native URLSession types/client, real photo population, editable review, cancellation and manual fallback.
3. Integrate Claude's auth/session/usage service after its tested milestones exist.
4. Add quick sample stacking, daily-limit display and demo upgrade; retain current Step 4 engine.

## Extractor milestone

Implemented the agreed `createPhotoExtractor({ apiKey, fetchImpl? })` export in `services/photo-reading/extract.ts`, with types and sanitized `PhotoExtractionError` codes in the adjacent files. Claude can now import the real module and mount it behind auth, image validation, quota reservation and idempotency. It makes one Mk1.5 call, allows 30 seconds, honors cancellation, and never automatically retries.

`npx vitest run services/photo-reading/extract.test.ts --maxWorkers=2`: 27 passed. Optional/missing values remain null; invalid values are cleared with warnings; all-empty or malformed output is rejected. Root typechecking includes services now. No new paid requests yet. Local dev server and native integration are in progress; they are not part of this first module milestone.
