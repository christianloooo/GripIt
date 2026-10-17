import { it, expect } from "vitest";
import { readFileSync } from "node:fs";
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { retargetHand } from "./riggedHand";
import { DEFAULT_MEASUREMENTS, PITCHES, solveGrip } from "./grip";
it("retargets every authored hand joint to the solver FK anchors without changing the source mesh", async () => {
  const bytes = readFileSync(
    new URL("../public/models/right-hand.glb", import.meta.url),
  );
  const gltf = await new GLTFLoader().parseAsync(
    bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
    "",
  );
  let source: THREE.SkinnedMesh | undefined;
  gltf.scene.traverse((o) => {
    if ((o as THREE.SkinnedMesh).isSkinnedMesh) source = o as THREE.SkinnedMesh;
  });
  expect(source).toBeDefined();
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
