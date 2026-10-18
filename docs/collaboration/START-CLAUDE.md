# Start Claude Code

Open Claude Code in this folder:

```text
/Users/jshum/.codex/worktrees/c9ea/gripit
```

Or launch it from Terminal:

```sh
cd /Users/jshum/.codex/worktrees/c9ea/gripit
claude
```

Paste this prompt:

```text
Build GripIt's MongoDB backend while Codex handles Perceptron Mk1.5 photo reading and all native iPhone UI work in parallel.

Your working directory must be /Users/jshum/.codex/worktrees/c9ea/gripit on branch claude/mongodb-backend. Do not change branches in the original /Users/jshum/Desktop/code-folders/gripit checkout.

Read docs/collaboration/README.md, docs/collaboration/claude-backend-brief.md and docs/collaboration/backend-contract.md completely before coding. Follow their reading order for the historical docs. They contain the product context, current four-step native app flow, file ownership, API contract, prior Perceptron findings, safety constraints and test requirements.

You own backend/** and docs/collaboration/claude-status.md only. Implement real email/password accounts with Better Auth and MongoDB Atlas, saved training sessions, and server-side daily limits. Free allows 3 photo scans and 3 throw reviews per day; Pro allows 20 each. Subscription upgrades are demo-only with no real payment. No Atlas cluster exists yet: finish the independent backend work and give me the exact setup steps when needed.

Codex owns services/photo-reading/** and native integration. Start with an injected fake extractor in backend tests; do not fake successful OCR in the running service. Mount Codex's real extractor when its tested commit exists. Preserve on-device hand scanning, model rendering and deterministic feedback. Do not add AI coaching or chat.

Make small local commits at tested milestones, use Jared Shum <jaredshum101@gmail.com>, and stage exact file paths. Update only your own status file with hashes, checks, startup instructions and blockers. Both worktrees share Git history, so inspect Codex's committed progress with git show codex/perceptron-photo:docs/collaboration/codex-status.md. A commit is visible locally but does not automatically update your working files. Merge only clean, tested Codex milestones when needed for integration. Never force-reset, delete branches, force-push, stage credentials or modify local native signing files.

Keep communication short and plain. Run at most two test workers, no Xcode builds or simulator downloads. Start by checking your branch and the handoff, then proceed with backend implementation within this scope.
```

No key or MongoDB connection string belongs in the prompt. Claude will need environment values in its own ignored file. Codex has not automatically sent this prompt to Claude or started another Claude session.
