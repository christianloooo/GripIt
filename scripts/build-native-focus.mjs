import { build } from "esbuild";
await build({
  entryPoints: ["shared/nativeFocus.ts"],
  bundle: true,
  format: "iife",
  globalName: "GripItFocus",
  target: "safari17",
  outfile: "ios/GripItScannerCore/Sources/GripItScannerCore/Resources/focus-engine.js",
  legalComments: "inline",
});
