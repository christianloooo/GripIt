# GripIt integration status

Updated October 18, 2026. This supersedes the paused implementation status in RESUME-HERE.md, which remains the detailed recovery history.

## Approved direction

Keep the teammate's Steps 1 and 2 scanner, optimized personalized fitting, minimalist explorer and interactive nodes. Connect that same solved hand and ball to throw entry and rule-based Step 4 feedback. Remove AI chat and generated coaching. Keep their original branch separate. Test the combined app before promoting it to main.

The photo flow is a local visual prototype while Perceptron is on hold. Session photos appear above upload controls. Selecting a bundled Rapsodo capture opens the image beside editable readings, sweeps a scan animation and fills values from that actual capture. Unknown uploads require manual readings. Confirmation adds the throw. Missing release height stays absent. Step 4 uses rule reasons in the interactive nodes and fuller explanations below the model, with blended colors around the relevant finger surfaces.

## Implemented

- Incoming Step 2 source is merged in the working tree. Its scanner, solver, model assets and UI are retained. The two viewer conflicts preserve our cached render and training navigation.
- Step 4 reuses that cached model, plan and surface. Winning checks are red, other firing checks yellow, checked clean regions green, unassessed regions neutral. Missing data and shared-cause guards apply to every color. Contact/effort weights remain separate from feedback colors.
- Baselines use current valid fastball drafts from the same studio and source. Handedness reaches the engine. No new coaching targets, wrist severity or slider index-driving instruction were added.
- AI backend routes, provider dependency, prompts, native client and chat/coaching requests are removed. Scanner hand detection remains. The protected plist retains unused historical server metadata without an active consumer.
- Photo entry includes rapsodo1 (softball) and rapsodo2 (baseball), Photos and Files uploads, session retention, zoom, editable fields, source replacement confirmation and nullable release height. Arbitrary images receive no invented readings.
- The native focus bundle has been regenerated from the updated shared engine.

## Verification so far

- Web suite: 191 passing tests after removing AI feature tests and adding severity and photo-input regressions.
- TypeScript build and web production build pass.
- Complete native core suite: 88 passing tests, zero failures.
- Final signed iOS build-for-testing succeeds, including compilation of the new feedback-node interaction test. Compilation does not mean the app-hosted tests ran.
- Final independent code review approved the implemented scope after the missing-efficiency severity fix. No open Critical or Important findings.
- Phone runtime and visual checks are still pending. The iPhone currently reports unavailable; a Mac-compatible test destination did not start and was stopped. No claim that the phone UI has been verified.

## Git and opening the right project

Integration branch: `jared/feedback-rules`. The integration is being committed and pushed here for device testing. Main has not changed.

Open `/Users/jshum/Desktop/code-folders/gripit/ios/GripIt.xcodeproj` for the integration. Avoid the similarly named older worktree projects in Xcode's recent list.

The original Step 2 remains at `backup/step-2-original-20261018` and `.worktrees/step-2-original`, with a remote backup. The recovered feedback engine also has a remote `backup/feedback-before-step2-20261018`. Do not overwrite either fallback.

The project index includes required incoming source references and optimization settings with repository signing values. Jared's local signing settings exist only in the working copy. Never stage the current project file wholesale. Stage all other files by exact path; never use `git add -A`.

Builds must run one at a time, with two workers, and derived/scratch data in `/private/tmp` to avoid iCloud signing metadata. Remaining work is app-hosted tests and a phone walkthrough: Steps 1–2 fitting and node interaction, Step 3 bundled scan/cancel/confirm/upload, and Step 4 rotation, colors and rule explanations. Keep main unchanged until device validation is complete.
