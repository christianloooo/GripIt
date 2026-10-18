# Native Steps 1 through 4

The integrated test copy is `.worktrees/step-2-teammate-demo`, branch
`integration/native-grip-flow`. Open `ios/GripIt.xcodeproj` there. The local
installed app is **GripIt Step 2**. The Xcode scheme remains **GripIt**.

## Try the flow

1. Scan, import a hand profile, or choose **Load sample profile**.
2. Choose **Explore my grips**, select a pitch, and tap **Record throws**.
3. Record the selected pitch on Rapsodo and enter its readings. For a quick
   demonstration, choose **Use sample throws** instead.
4. Tap **See feedback**. Rotate the same fitted hand and select a grip zone.
5. Read the AI interpretation or ask a follow-up question. Prototype rule notes
   and their color overlay are optional, inside a disclosure.
6. **Record another throw** returns to entry with the previous throws preserved.
   Back navigation also preserves drafts when switching between the four pitches.

The Rapsodo values are entered manually. There is no Rapsodo account connection
or automatic recording/import. Sample throws retain their label after edits.
Replacing entries with sample data or a fresh real session requires confirmation.

## Existing AI server

The native app calls `/api/coach` and `/api/ask` in this integrated copy.
It never contains an AI key. Set the **GripIt** target's user-defined build setting
`GRIPIT_API_BASE_URL` to the server's origin, then rebuild. The Info.plist expands
this into `GripItAPIBaseURL`.

For local testing, start this copy's server. The existing ignored Step 4 `.env`
is read from its current location without copying its key:

```sh
cd /Users/jshum/Desktop/code-folders/gripit/.worktrees/step-2-teammate-demo
env __VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS=Jareds-MacBook-Pro.local GRIPIT_DEV_ENV_DIR=/Users/jshum/Desktop/code-folders/gripit/.worktrees/step-4-assessment npm run dev -- --port 5173 --strictPort
```

The hostname allow-list is required: without it Vite rejects phone requests with
HTTP 403. The config allows both the configured hostname and its lowercase
spelling because URLSession lowercases it and Vite compares explicit hosts
case-sensitively. Both spellings were tested; no wildcard host access is enabled.
The key stays in that server's ignored `.env`. This test copy has a local Debug
URL of `http://Jareds-MacBook-Pro.local:5173`. Keep the iPhone and Mac on the same
network, allow local network access when prompted, and keep the server running.
The machine-specific URL and signing settings are not part of shared commits.
A production HTTPS API URL can use the same native client later.
For a separate setup, copy `.env.example` to `.env` in this copy and set the
server key there; omit `GRIPIT_DEV_ENV_DIR` when starting that server.

If AI is unavailable or declines, the rule engine's original feedback remains
available under prototype notes. AI explanations never decide the colors. Unassessed zones remain
untinted, and contacts the fitted hand cannot reach do not receive technique
advice. The current coaching rules remain prototype guidance.

## Responsiveness

Each hand session keeps one fitted pose and plan per pitch and shares in-flight
fitting work. Changing pitch and returning reuses the result. Step 4 renders the
already fitted pose without running the solver again. A new hand session gets
a fresh cache. Accepted AI generations are cached in the server for ten minutes,
up to 256 entries; duplicate in-flight calls share work. The native client also
caches complete successful responses for ten minutes, up to 32 entries per hand
session. Failures and partial native responses are not cached. Retry can recover
missing coaching or fit text. Provider calls time out after six seconds with no
automatic retries; native coaching waits up to ten seconds.

Server keys hash the actual prompt/input, model, token limit and credential
fingerprint. Native keys hash the complete sorted request, using the exact
records captured when assessment ran. IDs alone never determine cache identity.
The caches are bounded and process-local. They do not persist across app/server
restarts or span multiple server instances. There is no database, durable session
save, account system, cloud sync, or hosted deployment in this pass.

`GET /api/health` returns service availability. Request IDs, timing headers and
generation cache status help distinguish networking, provider and cache behavior.
Logs omit questions, prompts, measurements and keys. Request validation and a
256 KiB body limit apply in both development and exported handlers. Before public
hosting, add authenticated ownership, shared rate limits and a shared cache.

## AI and deterministic responsibilities

Deterministic code validates units, computes summaries, checks modeled contact
reach and retains versioned prototype rules. The AI receives actual throw
readings, their computed summaries, measured hand dimensions and grip intent.
It can interpret those observations, question the unvalidated sample-rule
suggestion, explain general principles from the supplied research context, and
name missing evidence. It is no longer limited to rewriting one preset sentence.
It cannot observe finger force or release mechanics from this static model.

The selected zone shows the grip instruction rather than repeating a shared
efficiency warning. The original rule colors are off by default and can be
inspected under **Prototype rule notes**. See [pitch-rule-research.md](pitch-rule-research.md)
for evidence, limitations and the rule review backlog. No sample thresholds were
promoted to validated coaching rules.

The original rule source was imported from Step 4 commit `c49cdab`. Native model
updates through `2f1e31e` are merged. The
native JavaScript bundle can be regenerated with `npm run ios:focus`. Xcode
builds use the committed bundle and do not require Node.

## Verification of this integration

- 82 native core tests passed. The seven coaching tests also passed after the
  final raw-record payload changes.
- 79 web tests and the web production build passed. The existing web bundle-size
  warning remains.
- Signed iOS app and signed build-for-testing passed. App installation and normal
  launch succeeded with the preserved personal bundle ID.
- Live local coaching, fit explanations and follow-up API calls succeeded.
  A repeated accepted coaching request took approximately 6–7 ms versus 4–5 s cold.
- Review findings for timestamp cache misses, partial-result Retry and numeric
  validation were fixed and rechecked.
- An opt-in device test in `LiveCoachingTests` reproduced the phone HTTP 403.
  Its first run also exposed a missing framework runtime search path, now fixed.
  The second run reached HTTP but was blocked by the lowercase hostname. The
  server now accepts that spelling, verified through health and coaching calls.
  After the user raised concern about repeated launches, automatic phone runs
  stopped. The device test has not been rerun after the server fix. Normal tests skip live API calls
  unless `GRIPIT_LIVE_COACH_SMOKE=1` is supplied to the test process.
- On-phone feedback appearance, gestures and the full interaction flow still
  need a manual smoke test of the installed build.
