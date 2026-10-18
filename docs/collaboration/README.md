# Parallel work: Perceptron and MongoDB

Prepared October 18, 2026. Start here when resuming either chat.

## Agreed split

- Codex, in the original GripIt folder on `codex/perceptron-photo`: real Perceptron Mk1.5 photo reading, native iPhone integration, sample flow and final integration.
- Claude Code, in a separate managed worktree on `claude/mongodb-backend`: MongoDB Atlas, accounts, saved progress, demo plans and server-side usage limits.
- `main` remains the existing demo until tested changes are integrated. These two branches are temporary collaboration branches, explicitly requested after the earlier branch cleanup.

Read [Claude's brief](claude-backend-brief.md), [the API contract](backend-contract.md), and [the Codex preparation plan](../superpowers/plans/2026-10-18-perceptron-photo.md). Each chat updates only its own status file.

## Working together

Worktrees share local Git history, so a committed change is visible to the other chat without a push. Uncommitted changes stay in the working folder that owns them. A commit makes work available; it does not automatically update the other folder's files.

Inspect the other side without switching branches:

```sh
git log --oneline -6 claude/mongodb-backend
git show claude/mongodb-backend:docs/collaboration/claude-status.md
git log --oneline -6 codex/perceptron-photo
git show codex/perceptron-photo:docs/collaboration/codex-status.md
```

Commit a small, coherent, tested milestone and record its hash, checks and any changed interface in your status file. Save a passing implementation before starting another risky change. Do not commit broken checkpoints as passing milestones. Use explicit paths:

```sh
git add backend/package.json backend/package-lock.json
git -c user.name='Jared Shum' -c user.email='jaredshum101@gmail.com' commit -m 'Add backend dependencies'
```

Claude can merge a clean, committed Codex milestone into its branch to receive the OCR module. Do not merge in both directions continuously or cherry-pick changes that will later be merged in full. Codex handles the final integration, reviews conflicts, runs the combined checks, and merges the finished result into main. Nobody resets main or replaces its tree wholesale.

## Protected work

Never stage `ios/GripIt.xcodeproj/project.pbxproj` or `ios/GripIt/Info.plist`. The original checkout has local signing settings. Never use `git add -A`, `git add .`, forced resets, branch deletion, worktree cleanup or force-pushes.

Leave `.worktrees/step-1-truedepth-scanner` and the other older detached worktrees untouched. Recovery archives and bundles are retained. Ignore unrelated untracked files, `.superpowers/`, root sample WebP files and `RESUME-HERE.md` unless explicitly needed.

Never copy `.env` to a commit or include keys in a status file. The backend needs its own ignored environment file and example with empty placeholders.

## Baseline

Starting main: `ab763a9`. `npm install` succeeded on October 18, 2026, with zero reported vulnerabilities. `npm test -- --maxWorkers=2` passed 193 tests across 15 files. `npx tsc -b` exited zero. These are the current checks, not the historical 207-test count in HANDOFF.md. No new native build has been run for this documentation-only preparation.

The iPhone project to open remains `/Users/jshum/Desktop/code-folders/gripit/ios/GripIt.xcodeproj`. Claude must not open another GripIt Xcode project or alter the native project.
