# Native Steps 1 through 4

The integrated test copy is `.worktrees/step-2-teammate-demo`, branch
`integration/native-grip-flow`. Open `ios/GripIt.xcodeproj` there. The local
installed app is **GripIt Step 2**. The Xcode scheme remains **GripIt**.

## Try the flow

1. Scan, import a hand profile, or choose **Load sample profile**.
2. Choose **Explore my grips**, select a pitch, and tap **Record throws**.
3. Record the selected pitch on Rapsodo and enter its readings. For a quick
   demonstration, choose **Use sample throws** instead.
4. Tap **See feedback**. Rotate the same fitted hand and select a colored zone.
5. Read the single next action or ask a follow-up question.
6. **Record another throw** returns to entry with the previous throws preserved.
   Back navigation also preserves drafts when switching between the four pitches.

The Rapsodo values are entered manually. There is no Rapsodo account connection
or automatic recording/import. Sample throws retain their label after edits.
Replacing entries with sample data or a fresh real session requires confirmation.

## Existing AI server

The native app calls the unchanged Step 4 `/api/coach` and `/api/ask` endpoints.
It never contains an AI key. Set the **GripIt** target's user-defined build setting
`GRIPIT_API_BASE_URL` to the server's origin, then rebuild. The Info.plist expands
this into `GripItAPIBaseURL`.

For local testing, start the existing Step 4 worktree's server:

```sh
cd /Users/jshum/Desktop/code-folders/gripit/.worktrees/step-4-assessment
env __VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS=Jareds-MacBook-Pro.local npm run dev -- --port 5173 --strictPort
```

The hostname allow-list is required: without it Vite rejects phone requests with HTTP 403. Only this Mac hostname is added. The key stays in that server's ignored `.env`. This test copy has a local Debug
URL of `http://Jareds-MacBook-Pro.local:5173`. Keep the iPhone and Mac on the same
network, allow local network access when prompted, and keep the server running.
The machine-specific URL and signing settings are not part of shared commits.
A production HTTPS API URL can use the same native client later.

If AI is unavailable or declines, the rule engine's original feedback remains
visible. AI explanations never decide the colors. Unassessed zones remain
untinted, and contacts the fitted hand cannot reach do not receive technique
advice. The current coaching rules remain prototype guidance.

## Responsiveness

Each hand session keeps one fitted pose and plan per pitch and shares in-flight
fitting work. Changing pitch and returning reuses the result. Step 4 renders the
already fitted pose without running the solver again. A new hand session gets
a fresh cache. There is no disk cache, account system, or database in this pass.

The shared TypeScript source was imported from Step 4 commit `c49cdab`; the
native JavaScript bundle can be regenerated with `npm run ios:focus`. Xcode
builds use the committed bundle and do not require Node.

## Verification of this integration

- 80 native core tests passed, including the imported renderer's geometry checks.
- 49 web tests passed, including the shared assessment and throw-entry tests.
- Web production build, unsigned iOS app build, and iOS build-for-testing passed.
- Live local coach and follow-up API calls succeeded.
- A fresh review found no remaining blocking issues after the JSON contract fixes.
- Phone appearance, touch navigation, camera capture, and phone-to-Mac network
  access still need an on-device smoke test. The paired phone was unavailable
  and no Simulator runtime was installed during this integration.
