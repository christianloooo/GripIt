# Shared Step 3 and Step 4

Imported unchanged from the Step 4 worktree at `c49cdab`. The TypeScript validator
and deterministic assessment remain the source of truth. Native SwiftUI calls a
bundled JavaScriptCore entry point, not a second set of coaching rules.

Regenerate after changes with `npm run ios:focus`. The generated JavaScript is
committed so Xcode builds do not require Node. Native tests exercise this exact
bundle, including actual Step 2 reach constraints.

The AI server remains in the existing Step 4 worktree. The native client uses
its unchanged `/api/coach` and `/api/ask` request/response contracts.
