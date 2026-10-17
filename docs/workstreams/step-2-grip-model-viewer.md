# Step 2: Grip Model and Viewer

## Branch

`feature/step-2-grip-model-viewer`

## Goal

Build the stylized arcade hand, pitch-specific grip solver, and clickable instruction viewer. Develop against committed `HandProfile` fixtures so this work does not wait for TrueDepth.

## Product context

Read:

- `PRODUCT.md`
- `handInstructions.md`
- `docs/superpowers/specs/2026-10-17-gripit-four-workstream-design.md`
- `docs/contracts/v1/README.md`
- `src/grip.ts`
- `src/Scene.tsx`
- `src/riggedHand.ts`

The current model is a low-detail generic WebXR hand. The replacement should prioritize recognizable shape, contact geometry, and instructional clarity over skin realism.

## Inputs and outputs

Consumes:

- `HandProfile`
- `PitchDefinition`

Produces:

- `GripPlan`

The viewer renders `HandProfile + GripPlan`. It must not read camera frames, scan-worker messages, MediaPipe results, or native iOS types.

## Required pitch behavior

Use `handInstructions.md` as the initial grip source:

- Four-seam: index and middle pads cross the seam.
- Two-seam: index and middle pads follow separate seams.
- Slider: middle pad follows the seam, index rests on adjacent leather.
- Circle change: middle and ring fingers lead, index and thumb form a loop, pinky supports.

Pressure and release text are instructional annotations. They are not physical-force simulation.

## Scope

- Typed v1 contract consumers.
- Pitch definitions for all four pitches.
- A stylized solid hand with simple materials and optional grid lines.
- Proportional fitting from fixture measurements.
- Joint limits and ball collision.
- Finger-pad contact targets and orientations.
- Palm clearance or depth constraints.
- Clickable finger, palm, wrist, and seam zones.
- Instruction panel for contact, pressure, and release.
- Fit confidence and unresolved-contact display.
- Tests with small, average, large, and left-hand fixtures.

## Out of scope

- Camera scanning.
- TrueDepth.
- Rapsodo forms.
- Performance scoring.
- Photorealistic skin.
- Guaranteed biomechanical accuracy.

## Acceptance criteria

- Four pitch types produce visibly different grips.
- The circle change uses middle and ring as the primary upper contacts.
- The slider groups index and middle toward one seam.
- Small, average, large, and left-hand profiles render without invalid geometry.
- Users can rotate, zoom, and select every instruction zone.
- Unreachable contacts remain visible as unresolved constraints.
- The hand uses simple, consistent materials.
- Existing and new tests pass.

## Coordination rules

Treat `HandProfile` as immutable input. If a desired measurement is absent, use an explicit fallback and reduce fit confidence. Do not add scanner-specific fields to the renderer.

