import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { PITCHES, solveGrip } from "./grip";
import type { Measurements } from "./grip";
import { validateMeasurements } from "./handDiagnostics";
import { retargetHand, disposeHand } from "./riggedHand";
let sourcePromise: Promise<THREE.SkinnedMesh> | undefined;
function loadSource() {
  return (sourcePromise ??= new GLTFLoader()
    .loadAsync(`${import.meta.env.BASE_URL}models/right-hand.glb`)
    .then((gltf) => {
      let source: THREE.SkinnedMesh | undefined;
      gltf.scene.traverse((o) => {
        if ((o as THREE.SkinnedMesh).isSkinnedMesh)
          source = o as THREE.SkinnedMesh;
      });
      if (!source) throw new Error("Hand asset has no skeleton.");
      return source;
    })
    .catch((error) => {
      sourcePromise = undefined;
      throw error;
    }));
}
export async function preflightHand(m: Measurements) {
  validateMeasurements(m);
  const source = await loadSource();
  // Commit measurements only after the actual skin passes every pitch. Yield
  // between pitches so scan review remains responsive during validation.
  for (const pitch of PITCHES) {
    await new Promise((resolve) => setTimeout(resolve, 0));
    try {
      const hand = retargetHand(source, solveGrip(m, pitch).fingers, m);
      disposeHand(hand);
    } catch (error) {
      throw new Error(
        `${pitch.name}: ${error instanceof Error ? error.message : "Invalid hand model"}`,
        { cause: error instanceof Error ? error.cause : undefined },
      );
    }
  }
}
