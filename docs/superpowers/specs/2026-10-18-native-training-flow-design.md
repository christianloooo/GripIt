# Native training flow

Approved in conversation on October 17, 2026. Implementation stays in the isolated
Step 2 test copy on `integration/native-grip-flow`.

## Integrated sources

- Step 2 refinement: `9efc922`.
- Landing-page PR #3: `dd30c9d`.
- Minimal scanner and viewer UI: `ed09cc9`.
- Existing Step 3/4 TypeScript contracts, validation, rules, and AI endpoints:
  Step 4 worktree at `c49cdab`.

## Experience

The grip studio gains a persistent **Record throws** action, enabled after a
successful fit. Step 3 retains the pitch and hand and says **Record your throw on
Rapsodo**. The player enters velocity, spin, spin direction, efficiency or gyro,
release height, and an optional score. One valid throw enables **See feedback**.
Additional throws stay in the same session. Sample throws remain visibly labeled
after editing; switching to real data starts a fresh session with confirmation.

Step 4 renders the actual Step 2 pose and plan with assessment colors. Selecting
a zone shows its reason. One next action appears, followed by optional existing
AI coaching, a measured-hand fit explanation, and a follow-up question field.
**Record another throw** returns to entry and preserves previous entries. Back
navigation preserves the grip, selected pitch, and drafts for each pitch.

## Boundaries

Reuse the existing pure TypeScript assessment and validation in a bundled
JavaScriptCore bridge. Do not duplicate or revise coaching thresholds. Native
adapters pass real Step 2 zone reach values, never default all zones to reachable.
Step 4 receives the already fitted pose; it never solves a second model.

Cache successful fitted poses and in-flight fitting by pitch for one immutable
hand profile. Failed fits can be retried. No persistent model cache, account
system, database, new AI provider, remote merge, or deployment is included.

AI requests go to the existing `/api/coach` and `/api/ask` server. The native app
holds only a server URL, never an API key. With no configured server or a failed
request, rule feedback stays visible and AI is labeled unavailable. A local server
may be used for device testing; a production host is a later deployment decision.

Unassessed zones remain untinted, unreachable contacts receive no pressure advice,
and insufficient evidence does not become a claim about arm mechanics. Advice
retains its prototype label. Unknown numeric values encode as null.

Preserve Jared's local team, `com.jaredshum.gripit.step2demo20261017`, and the
`GripIt Step 2` display name. Keep signing changes out of shared commits.

## Verification

Native tests cover entry errors and boundary values, null encoding, sample
provenance, assessment fixture parity, real reach constraints, release-height
drift, pitch isolation, cache reuse and retry, and AI fallback/request payloads.
Run the imported assessment tests, native core tests, an unsigned device build,
and an iPhone smoke test when a device or simulator is available. Visual and
live-network checks are reported separately from compile and unit-test results.
