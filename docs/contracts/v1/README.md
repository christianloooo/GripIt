# GripIt Contract v1

This directory defines the boundary between the four GripIt workstreams. The examples below are the source of truth until executable JSON Schemas and language bindings are added.

## Data flow

```text
Scanner -> HandProfile
HandProfile + PitchDefinition -> GripPlan
Rapsodo form -> ThrowRecord
GripPlan + ThrowRecord[] -> FocusAssessment
```

## HandProfile

Required core fields:

```json
{
  "schemaVersion": "1.0.0",
  "profileId": "sample-average-right",
  "createdAt": "2026-10-17T00:00:00Z",
  "handedness": "right",
  "units": "millimeters",
  "coordinateSystem": "gripit-hand-v1",
  "measurements": {},
  "landmarks": {},
  "capture": {},
  "extensions": {}
}
```

`measurements` owns stable dimensions. `landmarks` owns named XYZ points and per-point confidence. `capture` owns method, device capability, calibration, coverage, and overall confidence. Camera images and depth buffers are not part of the contract.

## PitchDefinition

Required core fields:

```json
{
  "schemaVersion": "1.0.0",
  "pitchId": "four-seam",
  "name": "Four-seam fastball",
  "ballOrientation": {},
  "contacts": [],
  "palmDepth": {},
  "releaseInstructions": [],
  "extensions": {}
}
```

Contacts identify an anatomical zone, target surface, relationship to a seam, direction, pressure, and role. Grip rules come from `handInstructions.md` and require coaching review before being presented as validated advice.

## GripPlan

Required core fields:

```json
{
  "schemaVersion": "1.0.0",
  "gripPlanId": "sample-four-seam-average-right",
  "handProfileId": "sample-average-right",
  "pitchId": "four-seam",
  "ballTransform": {},
  "jointTransforms": {},
  "contacts": [],
  "instructionZones": [],
  "fit": {},
  "extensions": {}
}
```

## ThrowRecord

Required core fields:

```json
{
  "schemaVersion": "1.0.0",
  "throwId": "sample-throw-1",
  "sessionId": "sample-session-1",
  "pitchId": "four-seam",
  "recordedAt": "2026-10-17T00:00:00Z",
  "measurements": {},
  "source": "sample",
  "extensions": {}
}
```

The initial measurement names are `velocityMph`, `totalSpinRpm`, `spinDirectionClock`, `spinEfficiencyPercent`, `gyroDegree`, `releaseHeightFeet`, and `rapsodoScore`. Values unavailable from a device or session use `null` only when the field is optional.

## FocusAssessment

Required core fields:

```json
{
  "schemaVersion": "1.0.0",
  "assessmentId": "sample-assessment-1",
  "gripPlanId": "sample-four-seam-average-right",
  "throwIds": ["sample-throw-1"],
  "ruleVersion": "sample-rules-1",
  "zones": [],
  "nextAction": {},
  "confidence": 0.5,
  "classification": "grip-focus",
  "extensions": {}
}
```

`classification` is either `grip-focus` or `not-grip`. Zone severity is `green`, `yellow`, or `red`.

## Compatibility policy

- Consumers must reject unsupported major versions.
- Consumers must ignore unknown additive fields.
- Producers must not remove or reinterpret v1 required fields.
- Experimental fields belong under `extensions` with a namespaced key.
- Contract fixtures must remain valid when implementations change.
