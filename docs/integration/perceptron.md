# Optional Perceptron Integration

## Recommendation

Perceptron is useful for GripIt. It should be an optional perception sidecar, not the measurement engine.

TrueDepth and camera calibration produce metric XYZ values. MediaPipe names the hand joints. Perceptron can reason about the scene, localize objects, track them through video, and explain what the user should do next.

## Best hackathon use

Use Perceptron for scan QA and coaching:

1. The iOS app captures a low-rate keyframe or short clip when local scan quality stalls.
2. The app uploads it to the GripIt server. The API key never ships in the app.
3. The server asks Perceptron to identify the visible hand side, finger occlusion, baseball visibility, framing, and the best next rotation.
4. The app shows one short instruction such as `Rotate toward your thumb side`.
5. Local `CoverageTracker` remains the source of progress and completion.

Use a strict app-owned result shape:

```json
{
  "schemaVersion": "1.0.0",
  "view": "thumb-side",
  "handVisible": true,
  "baseballVisible": true,
  "occludedZones": ["thumb-tip"],
  "instruction": "Rotate slightly toward your thumb side and separate your thumb from your palm.",
  "confidence": 0.86
}
```

Validate the response on the server. Treat malformed, slow, or low-confidence output as unavailable. The local scanner must continue without it.

## Strong second use

Apply Perceptron to a pitch video after Step 1:

- Find ball release.
- Track the throwing hand and baseball around release.
- Select the most useful frames for the Step 4 review.
- Describe visible grip or release differences in plain language.

This use is likely more impressive for the Perceptive track because it uses temporal video understanding rather than a single image. It can later produce an optional observation consumed by Step 4. It must not claim spin, velocity, or exact joint angles without a calibrated source.

## API boundary

- Keep `PERCEPTRON_API_KEY` on a server-side proxy.
- Send sampled frames or short clips, not the full live camera stream.
- Obtain explicit user consent before upload.
- Delete uploaded media after analysis when the hackathon API permits it.
- Never let model output write `HandProfile.measurements` or metric landmark coordinates.
- Store only an advisory summary under a namespaced `extensions` key when persistence is useful.

Perceptron's public SDK describes detection, localization, captioning, OCR, and visual question answering. Its Mk family also supports image and video reasoning. The workshop API may expose richer structured tracking than the public cloud endpoint, so confirm the exact model ID and response format during the workshop before implementing the adapter.

## Suggested demo story

1. TrueDepth builds the metric hand profile.
2. The arcade hand fills as local coverage completes.
3. Perceptron notices an occluded thumb or missing baseball and gives one corrective instruction.
4. GripIt creates the personalized grip model.
5. Perceptron finds the release event in a short pitch video for the coaching screen.

This keeps Perceptron visibly important while preserving deterministic measurement quality.

## References

- [Perceptron Python SDK](https://github.com/perceptron-ai-inc/perceptron)
- [Perceptron Vision API](https://perceptron.cloud/docs/vision)
- [Perceptron Mk1.5](https://www.perceptron.inc/blog/introducing-perceptron-mk1-5)
- [Isaac model repository](https://github.com/perceptron-ai-inc/isaac)
