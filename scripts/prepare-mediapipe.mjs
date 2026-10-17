import "./copy-mediapipe.mjs";
import { buildSync } from "esbuild";
buildSync({
  entryPoints: ["src/scan.worker.ts"],
  outfile: "public/mediapipe/scan-worker.js",
  bundle: true,
  format: "iife",
  platform: "browser",
  target: "es2022",
  minify: true,
});
