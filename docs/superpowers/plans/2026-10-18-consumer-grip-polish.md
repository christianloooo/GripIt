# Consumer grip polish implementation plan

User direction approved October 18: only rapsodo1, represented as baseball; one easy action per node in Steps 2 and 4; readings and full explanations behind a bottom-right Details button; larger heatmap coverage and high-contrast yellow markers; explain secondary yellow adjustments; animated dotted scan bar while values appear.

## Constraints

Keep the Step 2 solver, geometry, cached rendering and original branch intact. No coaching target or ranking changes. Preserve slider index relaxation, fit gates, handedness and no wrist severity. Plain-English cues paraphrase handInstructions.md, with original technical text retained in Details. Image/demo numbers come from the existing baseball capture, not invented targets. Keep local signing unstaged, stage exact paths, run heavy checks serially with two workers.

## Tasks

- [x] Add short consumer cue copy beside existing source instructions and rule copy. Add optional per-zone action to the shared/native contract so secondary yellow findings have real actions, not just a measured reason. Tests must prove the demo produces distinct thumb and finger actions, clean zones have no corrective action, and all fired rule cues exist.
- [x] Add native pitch/zone guide copy and assessment presentation helpers, with tests for slider relaxation, missing data, deduplicated secondary actions and simple gate guidance.
- [x] Replace the bundled two-capture selector with one baseball rapsodo1. Edit the rapsodo1 image using the existing capture as the layout target and rapsodo2 as the reading source. Populate exactly 77.3 mph, 1642 rpm, 01:56, 93.8%, 18.6 horizontal and 13.8 vertical; other readings stay absent. Retain original root images for recovery.
- [x] Use concise instructions in graph cards. Remove reading/effort paragraphs from default cards. Add persistent opaque marker backgrounds, contrasting white rings, severity accents and shadows. Keep fit warnings before advice.
- [x] Simplify Step 4 main panel to first action and deduplicated yellow follow-up actions. Put measured summary, reasons, expected changes, original source instructions and consistency in a Details sheet. Put equivalent full placement information in Step 2 Details, opened from bottom right.
- [x] Expand feedback finger influence toward the finger base with a smooth fade, keeping contact masks, pressure weights, palm/wrist ownership and picking unchanged. Test wider feedback coverage and finite bounded weights.
- [x] Replace the single scan sweep with a translucent dotted band that moves both ways throughout progressive field population; stop on completion/cancellation and respect reduced motion.
- [x] Regenerate native bundle, run web tests/typecheck, native core tests, and signed build-for-testing serially. Review changed source before commit/push. Device visual validation remains required before main.

## Execution ledger

Inline execution on jared/feedback-rules, starting at 993e57c. The user's message specifies the design; no repeated approval prompt is needed. Final fresh review required. Existing local signing and root recovery files stay out of commits.

Completed all eight tasks. Web verification: 193 tests pass, TypeScript and production build pass, native bundle regenerated. Native core: 93 tests pass. Regression proof: restoring the old heatmap region causes the new middle-finger-coverage test to fail; restoring broader coverage passes. Signed iOS build-for-testing passes, including updated app-hosted interaction test compilation. Physical phone remains unavailable, so visual UI and app-hosted test execution remain pending.

Final fresh review: no Critical or Important findings. Reviewed image matches all six fixture readings. Minor deferred: historical assessment JSON lacking optional action fields uses a missing-readings fallback rather than its older technical change text; the current app recomputes assessments through the bundled engine and does not restore stored historical assessments.
