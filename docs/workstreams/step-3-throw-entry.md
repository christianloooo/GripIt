# Step 3: Throw Entry

## Branch

`feature/step-3-throw-entry`

## Goal

Build the Rapsodo entry flow and produce validated, versioned `ThrowRecord` values. This branch can work entirely from product requirements and contract fixtures.

## Product context

Read:

- `PRODUCT.md`
- `docs/superpowers/specs/2026-10-17-gripit-four-workstream-design.md`
- `docs/contracts/v1/README.md`
- `src/App.tsx`
- `src/styles.css`

The product asks for velocity, total spin, spin direction, spin efficiency or gyro degree, release height, and an optional Rapsodo score.

## Inputs and outputs

Consumes:

- Selected `pitchId`
- Optional `HandProfile.profileId`
- User-entered or explicitly labeled sample data

Produces:

- One or more `ThrowRecord` values grouped by `sessionId`

This workstream does not decide which grip area caused a result.

## Scope

- Pitch-aware throw-entry route or panel.
- Fields and units defined by the v1 contract.
- Clear choice between spin efficiency and gyro degree when appropriate.
- Field-level range and format validation.
- Session grouping.
- Single-throw completion.
- Multiple-throw history.
- A clearly labeled sample-throw loader.
- JSON export or local handoff to Step 4.
- Keyboard and screen-reader accessibility.
- Unit and component tests.

## Initial validation behavior

- Reject impossible values such as 900 mph.
- Keep invalid values visible so the user can correct them.
- Distinguish missing optional values from zero.
- Store normalized numeric values, not formatted strings.
- Label fixture and demo records with `source: sample`.

Exact coaching ranges are not part of this branch.

## Out of scope

- Direct Rapsodo API integration.
- Camera scanning.
- 3D grip solving.
- Inferring finger mistakes.
- Final coaching thresholds.
- Authentication or cloud persistence.

## Acceptance criteria

- A user can save one valid throw.
- Invalid fields show specific messages.
- Three or more throws can be reviewed as one session.
- Sample data is always labeled.
- Saved records match the shared `ThrowRecord` example.
- Refresh behavior is explicit. Data is either restored locally or clearly described as temporary.
- Existing and new tests pass.

## Coordination rules

Do not place display-only strings in persisted numeric fields. Do not add assessment results to `ThrowRecord`. Step 4 owns analysis.

