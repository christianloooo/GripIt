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

Extractor export is not implemented yet. Claude can use a test fake behind its injected provider boundary. No new paid test requests or deployment occurred during preparation.
