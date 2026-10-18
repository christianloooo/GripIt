# Simplified native scan screens

The landing and completion screens use SwiftUI and actual Lucide SVG icons from
the existing pinned `lucide-react` package. Xcode compiles the selected SVGs as
native template images. No JavaScript runtime or web view is needed for these
screens. shadcn/ui's React components are not installed in the Swift app.

- Landing: short introduction, left/right selection, and one Scan my hand action.
  Selecting a hand no longer immediately starts capture. Sample mode is a quiet
  secondary action; import is available in the profile menu.
- Completion: clearly labeled sample or personal profile, palm span/length summary,
  and one Explore my grips action. Scan again remains available.
- View measurements opens a sheet with all palm/finger measurements, unavailable
  thickness values, scan quality, diagnostics, and JSON export. Export is also in
  the profile menu. Missing measurements remain unavailable.
- The existing capture pipeline, scan guidance, file import/export, and 3D viewer
  retain their behavior. These screens do not change the measurement contract.

The font styles support Dynamic Type, primary actions stay outside the scrolling
content, and hand selection exposes its selected state to accessibility.

Regenerate icons after installing dependencies:

```sh
node scripts/prepare-native-icons.mjs
```

SVGs are checked into the asset catalog. The Lucide ISC notice is included in the
native package resources as `ui-lucide-license.txt`. Source: https://lucide.dev/.

Debug preview launch arguments (bundled sample only, no camera):

```text
--scan-results-preview
--scan-results-preview --profile-details-preview
```

Review screenshots are local ignored artifacts in `ios/build/reviews/simple-ui/`.

Verification: simulator build, signed iPhone Debug build, and all eight scanner
adapter tests pass. Landing, completion, and measurement-sheet renders were
reviewed on the simulator. The initial three-second capture showed startup; it
was replaced by completed six-second captures.
