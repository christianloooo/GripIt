# Pitch feedback research, 2026-10-17

## Finding

The current `sample-rules-1` table is a demonstration, not a validated finger
diagnosis. Its four-seam bands (80%, 90%), two-seam floor (65%), slider ceiling
(65%), zone confidence values, and consistency limits are product assumptions.
The sources below do not validate that complete table or its mapping to fingers.
Do not silently promote these values to researched coaching standards.

## Evidence and implications

| Pitch or signal | Evidence | Proposed rule direction | Missing inputs |
| --- | --- | --- | --- |
| Four-seam | Rapsodo describes higher active spin as useful for a conventional riding four-seam, alongside spin direction and break [1]. | Compare efficiency to an explicitly selected carry goal and the player's baseline. Describe a ball-flight finding once. | Intended shape, induced vertical and horizontal break, baseline, release context. |
| Two-seam/sinker | Rapsodo describes a broad efficiency range and different outcomes with arm slot and spin direction [1]. Nathan explains why seam-shifted wake can require some gyrospin in a two-seam orientation [3]. | Do not treat lower efficiency alone as a failed sinker. Evaluate intended run/depth against measured movement. | Movement, arm slot, intended shape. Current data cannot identify seam-shifted wake. |
| Slider | Rapsodo distinguishes gyro, topspin, and sidespin slider profiles [2]. | Ask which slider shape is intended before grading efficiency. Avoid one universal ceiling. | Slider subtype and movement. |
| Changeup | Rapsodo gives successful examples with different efficiency profiles and discusses pairing with the fastball [2]. | Compare with the same player's fastball session, including velocity separation and movement. | A matched fastball baseline and movement. |
| Individual fingers | Kinoshita et al. directly measured individual finger forces with an instrumented baseball in 11 pitchers [4]. | Grip instructions can describe contact roles. Rapsodo readings and a static hand model cannot directly measure those forces or identify the guilty finger. | Force/contact sensing or observed release evidence. |
| Repeated throws | Comparing controlled trials can reveal repeatability; the app's current spread cutoffs are not validated by these sources. | Report observed spread separately. Require repeated baseline and trial sets before calling an adjustment an improvement. | Enough matched throws, controlled effort, repeat sessions. |

These are engineering interpretations of the cited sources, not a coach-approved
replacement rule set. Manufacturer examples are educational examples, not
population norms or causal trials. Laboratory finger-force results do not make a
phone hand scan a force sensor.

## Proposed feedback structure

1. **Observed:** report the entered metric and comparison once, with throw count.
2. **Context:** explain the intended pitch shape and what cannot be inferred.
3. **Grip check:** show the selected zone's existing contact instruction, clearly
   identified as an instruction rather than a measured fault.
4. **Experiment:** one optional adjustment, repeat a comparable set, and compare
   against the player's saved baseline. Do not promise a result.

Keep geometrical fit warnings distinct from throw outcomes. A modeled contact
that cannot be reached is a fitting problem, not proof of a throwing mistake.
Avoid numerical confidence percentages until they are calibrated against labeled
outcomes. Keep unassessed zones neutral.

## Rule review backlog

- Define intended shape/subtype and optional movement fields before adding rules
  that depend on them. Declare units and movement sign conventions.
- Store baseline session references and distinguish manual entries from sample data.
- Give each rule an evidence source, assumptions, required inputs, missing-data
  behavior, version, and coach-review status.
- Test left/right handedness, subtype differences, missing baselines, contradictory
  metrics, small samples, boundary values, and unreachable contacts.
- Have a qualified pitching coach review candidate cues and test controlled
  baseline/adjustment sessions. Do not validate a rule by having an LLM agree.

No production thresholds or colors are changed by this research pass.

## Sources checked

1. [Rapsodo, Fastball spin rate and efficiency profiles (2022)](https://rapsodo.com/blogs/baseball/understanding-rapsodo-pitching-data-spin-rate-efficiency-profile-fastball).
2. [Rapsodo, Curveball, slider, and changeup profiles (2022)](https://rapsodo.com/blogs/baseball/understanding-rapsodo-pitching-data-spin-rate-efficiency-profile-curveball-slider-changeup/).
3. [Alan Nathan, Four-seam versus two-seam aerodynamics](https://baseball.physics.illinois.edu/Hawkeye-4S-2S.pdf). The search-indexed text supports the seam-orientation limitation; not used to derive numerical cutoffs.
4. [Kinoshita et al., Finger forces in fastball baseball pitching (2017), abstract](https://pubmed.ncbi.nlm.nih.gov/28500954/). Full text was not reviewed.
