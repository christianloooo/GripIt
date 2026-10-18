# Natural hand proportions and supplied ball

The native hand uses a slimmer palm and closer digit spacing. The reference
profile previously used 82 mm as index-to-pinky MCP-center span, effectively
spreading the fingers by the external breadth of a hand. The reference now uses
62 mm MCP span and 82 mm wrist-to-MCP length. Actual imported/scanned dimensions
and root landmarks remain authoritative.

Missing palm thickness uses a 14 mm estimate calibrated against the actual
central bind-surface thickness. Provided thickness still controls the fit.
Palm-depth scaling blends into the finger and thumb-base radii, avoiding a large
thenar lump. Neutral fingers gently converge. Grip fitting raises the ball,
adjusts upper-pad targets, and searches additional bounded joint configurations
to maintain contact without the earlier abrupt finger arches.

## Supplied Ball.glb

- Original: `assets/source/Ball.glb`, copied unchanged from the supplied file.
- SHA-256: `29dffd40550f1a938d2caa63a2061a1c3b57e5e5e055637ba5bed30f49c0a0ca`.
- Runtime: `public/models/baseball.glb`, one clean variant, centered and normalized
  to radius 36.5 mm. Original UVs and diffuse/normal/roughness/metallic data remain;
  maps are reduced to 2048 pixels. The dirty variant remains in the source file.
- Native resources: matching mesh, unit normals, diffuse image, normal map, and
  packed roughness/metallic map in `GripItScannerCore/Resources`.
- Stitch references: 16,978 source-texture samples for the web and 586 reduced
  native samples with local tangent directions. These replace the old seam cloud.
- The source has no embedded creator/license metadata. Provenance is recorded
  accurately without assigning the previous ball's author or license to it.

Regenerate from the repository root (Pillow is needed only for asset preparation):

```sh
python3 -m venv /tmp/gripit-assets-venv
/tmp/gripit-assets-venv/bin/pip install Pillow
/tmp/gripit-assets-venv/bin/python scripts/import-baseball.py
node scripts/prepare-native-grip.mjs
```

Generated assets are bundled; running Xcode does not require these preparation
commands. The full two-variant source is outside `public` and the app resources.
Native UIImage textures use the original UVs directly, without an extra V flip.
Packed material channels use green for roughness and blue for metallic.

## Verification

- 64 Swift core tests passed, including measured dimensions, palm depth,
  reference spacing, all four pitch fits, seam contacts, and source-ball identity.
- 15 iOS tests passed, including skin-attached nails, mirroring, heat-map scene
  reuse, export reload, and supplied PBR texture loading/channel assignments.
- 33 web tests passed; production Vite build passed.
- Simulator Debug build and unsigned iPhone Release build passed.
- Native mesh review includes palm, true side profile, back, and a bent pose.
  Grip renders cover all four pitches, plus back and thumb-side heat-map views.
  Actual render artifacts are in local ignored `ios/build/reviews/natural-fit/`.

The reference renders inspect a generic measured hand. They do not reproduce
an unavailable failing phone profile. Physical-device scan and coach validation
remain separate from these rendering and geometric checks.
