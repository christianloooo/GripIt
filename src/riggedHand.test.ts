import { it, expect, beforeAll } from "vitest";
import { readFileSync } from "node:fs";
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import {
  assertHandSurface,
  inspectHandSurface,
  validateMeasurements,
} from "./handDiagnostics";
import { retargetHand } from "./riggedHand";
import { DEFAULT_MEASUREMENTS, FINGERS, PITCHES, solveGrip } from "./grip";
let source: THREE.SkinnedMesh;
beforeAll(async () => {
  const bytes = readFileSync(
    new URL("../public/models/right-hand.glb", import.meta.url),
  );
  const gltf = await new GLTFLoader().parseAsync(
    bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
    "",
  );

  gltf.scene.traverse((o) => {
    if ((o as THREE.SkinnedMesh).isSkinnedMesh) source = o as THREE.SkinnedMesh;
  });
  expect(source).toBeDefined();
});
it("retargets every authored hand joint to the solver FK anchors without changing the source mesh", () => {
  const original = source!.geometry.getAttribute("position").getX(0);
  const solution = solveGrip(DEFAULT_MEASUREMENTS, PITCHES[0]);
  const hand = retargetHand(source!, solution.fingers, DEFAULT_MEASUREMENTS);
  for (const finger of solution.fingers)
    for (let i = 0; i < 4; i++)
      expect(
        hand.anchors[`${finger.name}:${i}`]
          .getWorldPosition(new THREE.Vector3())
          .distanceTo(finger.points[i]),
      ).toBeLessThan(1e-8);
  // Check the actual skinned vertices too, not just bone metadata.
  for (let i = 0; i < hand.mesh.geometry.getAttribute("position").count; i++) {
    const p = hand.mesh.getVertexPosition(i, new THREE.Vector3());
    expect(Number.isFinite(p.x + p.y + p.z)).toBe(true);
    expect(p.length()).toBeLessThan(300);
  }
  expect(source!.geometry.getAttribute("position").getX(0)).toBe(original);
  hand.mesh.geometry.dispose();
  (hand.mesh.material as THREE.Material).dispose();
  hand.mesh.skeleton.dispose();
});

it("keeps personalized thumb skin bounded across scan proportions and every pitch", () => {
  for (const scale of [0.8, 1, 1.2]) {
    const m = structuredClone(DEFAULT_MEASUREMENTS);
    m.palmWidth *= scale;
    m.palmLength = 72 * scale;
    m.knuckles = {
      thumb: [28 * scale, -50 * scale, -24],
      index: [30 * scale, 0, -24],
      middle: [8 * scale, 0, -24],
      ring: [-14 * scale, -3 * scale, -24],
      pinky: [-29 * scale, -10 * scale, -24],
    };
    for (const f of FINGERS)
      m.segments[f] = m.segments[f].map((n) => n * scale) as [
        number,
        number,
        number,
      ];
    // Synthetic regression: shorter distal thumb with its base near the wrist.
    m.segments.thumb = [32 * scale, 25 * scale, 16 * scale];
    for (const pitch of PITCHES) {
      const solution = solveGrip(m, pitch);
      expect(
        solution.fingers.find((f) => f.name === "thumb")!.error,
      ).toBeLessThan(8);
      const hand = retargetHand(source, solution.fingers, m);
      const stats = inspectHandSurface(hand.mesh);
      expect(stats.maxStretch).toBeLessThan(5);
      expect(stats.stretchedEdges / stats.edges).toBeLessThan(0.005);
      hand.mesh.geometry.dispose();
      (hand.mesh.material as THREE.Material).dispose();
      hand.mesh.skeleton.dispose();
    }
  }
});
it("rejects corrupted thumb measurements before building a mesh", () => {
  for (const thumb of [
    [NaN, 24, 20],
    [64, 7, 7],
    [30, 24, 0],
  ]) {
    const m = structuredClone(DEFAULT_MEASUREMENTS);
    m.segments.thumb = thumb as [number, number, number];
    expect(() => validateMeasurements(m)).toThrow();
  }
});
it("detects a skin failure even when all bone positions are finite", () => {
  const solution = solveGrip(DEFAULT_MEASUREMENTS, PITCHES[0]);
  const hand = retargetHand(source, solution.fingers, DEFAULT_MEASUREMENTS);
  hand.anchors["thumb:1"].position.x += 160;
  hand.mesh.updateMatrixWorld(true);
  hand.mesh.skeleton.update();
  const stats = inspectHandSurface(hand.mesh);
  expect(stats.maxStretch).toBeGreaterThan(8);
  hand.mesh.geometry.dispose();
  (hand.mesh.material as THREE.Material).dispose();
  hand.mesh.skeleton.dispose();
});

it("rejects a collapsed finite skin and an unreachable thumb target", () => {
  const solution = solveGrip(DEFAULT_MEASUREMENTS, PITCHES[0]);
  const broken = solution.fingers.map((r) => ({
    ...r,
    error: r.name === "thumb" ? 80 : r.error,
  }));
  expect(() => retargetHand(source, broken, DEFAULT_MEASUREMENTS)).toThrow(
    "supported grip",
  );
  const hand = retargetHand(source, solution.fingers, DEFAULT_MEASUREMENTS);
  for (const bone of hand.mesh.skeleton.bones) {
    bone.position.set(0, 0, 0);
    bone.scale.set(0, 0, 0);
  }
  hand.mesh.updateMatrixWorld(true);
  hand.mesh.skeleton.update();
  expect(() => assertHandSurface(hand.mesh)).toThrow("collapsed triangles");
  hand.mesh.geometry.dispose();
  (hand.mesh.material as THREE.Material).dispose();
  hand.mesh.skeleton.dispose();
});
