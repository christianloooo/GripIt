import * as THREE from "three";
import {
  assertHandSurface,
  assertThumbFit,
  inspectHandSurface,
  validateMeasurements,
} from "./handDiagnostics";
import type { Finger, FingerRig, Measurements } from "./grip";
const PREFIX: Record<Finger, string> = {
  thumb: "thumb",
  index: "index-finger",
  middle: "middle-finger",
  ring: "ring-finger",
  pinky: "pinky-finger",
};
// Retarget a flat WebXR skeleton to the same FK anchors used by the optimizer.
// Source topology stays connected; no skin mesh is regenerated as the pose changes.
export function retargetHand(
  source: THREE.SkinnedMesh,
  rigs: FingerRig[],
  m: Measurements,
) {
  validateMeasurements(m);
  assertThumbFit(rigs);
  source.updateWorldMatrix(true, true);
  const sourceBones = source.skeleton.bones;
  const sourcePosition = (name: string) => {
    const bone = sourceBones.find((b) => b.name === name);
    if (!bone) throw new Error(`Missing hand bone: ${name}`);
    return bone.getWorldPosition(new THREE.Vector3());
  };
  const wrist = sourcePosition("wrist"),
    middle = sourcePosition("middle-finger-phalanx-proximal");
  const y = middle.clone().sub(wrist).normalize();
  const x = sourcePosition("index-finger-phalanx-proximal").sub(
    sourcePosition("pinky-finger-phalanx-proximal"),
  );
  x.addScaledVector(y, -x.dot(y)).normalize();
  const z = x.clone().cross(y).normalize();
  const rotation = new THREE.Matrix4().makeBasis(x, y, z).invert();
  const rotateQ = new THREE.Quaternion().setFromRotationMatrix(rotation);
  const canonical = new THREE.Matrix4()
    .multiply(rotation)
    .multiply(
      new THREE.Matrix4().makeTranslation(-wrist.x, -wrist.y, -wrist.z),
    );
  const restLength = middle.distanceTo(wrist) * 1000;
  const restWidth =
    sourcePosition("index-finger-phalanx-proximal").distanceTo(
      sourcePosition("pinky-finger-phalanx-proximal"),
    ) *
    1000 *
    1.18;
  const palmLength = m.palmLength ?? 72;
  const affine = new THREE.Matrix4()
    .makeTranslation(0, -palmLength, -26)
    .multiply(
      new THREE.Matrix4().makeScale(
        m.palmWidth / restWidth,
        palmLength / restLength,
        m.palmWidth / restWidth,
      ),
    )
    .multiply(new THREE.Matrix4().makeScale(1000, 1000, 1000))
    .multiply(canonical);
  const geometry = source.geometry
    .clone()
    .applyMatrix4(
      new THREE.Matrix4().multiplyMatrices(affine, source.matrixWorld),
    );
  const material = new THREE.MeshPhysicalMaterial({
    color: "#c49b83",
    roughness: 0.59,
    clearcoat: 0.04,
  });
  const mesh = new THREE.SkinnedMesh(geometry, material);
  mesh.name = "Personalized anatomical hand";
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  mesh.frustumCulled = false;
  const bones = sourceBones.map((original) => {
    const bone = new THREE.Bone();
    bone.name = original.name;
    bone.position.copy(
      original.getWorldPosition(new THREE.Vector3()).applyMatrix4(affine),
    );
    bone.quaternion
      .copy(rotateQ)
      .multiply(original.getWorldQuaternion(new THREE.Quaternion()));
    mesh.add(bone);
    return bone;
  });
  const byName = new Map(bones.map((b) => [b.name, b]));
  const restPositions = new Map(bones.map((b) => [b.name, b.position.clone()]));
  const restRotations = new Map(
    bones.map((b) => [b.name, b.quaternion.clone()]),
  );
  const transforms = bones.map(() => new THREE.Matrix4());
  const chains = rigs.map((rig) => {
    const prefix = PREFIX[rig.name];
    const names =
      rig.name === "thumb"
        ? [
            `${prefix}-metacarpal`,
            `${prefix}-phalanx-proximal`,
            `${prefix}-phalanx-distal`,
            `${prefix}-tip`,
          ]
        : [
            `${prefix}-phalanx-proximal`,
            `${prefix}-phalanx-intermediate`,
            `${prefix}-phalanx-distal`,
            `${prefix}-tip`,
          ];
    const open = [rig.root.clone()];
    const directions: THREE.Vector3[] = [];
    for (let i = 0; i < 3; i++) {
      const start = restPositions.get(names[i])!,
        end = restPositions.get(names[i + 1])!;
      const direction = end.clone().sub(start).normalize();
      directions.push(direction);
      open.push(open[i].clone().addScaledVector(direction, rig.lengths[i]));
      // Resize the BIND skin along its own segment before posing. Merely
      // translating independent WebXR joints stretches the thumb web and tips.
      const ratio = rig.lengths[i] / start.distanceTo(end);
      const d = direction;
      const stretch = new THREE.Matrix4().set(
        1 + (ratio - 1) * d.x * d.x,
        (ratio - 1) * d.x * d.y,
        (ratio - 1) * d.x * d.z,
        0,
        (ratio - 1) * d.y * d.x,
        1 + (ratio - 1) * d.y * d.y,
        (ratio - 1) * d.y * d.z,
        0,
        (ratio - 1) * d.z * d.x,
        (ratio - 1) * d.z * d.y,
        1 + (ratio - 1) * d.z * d.z,
        0,
        0,
        0,
        0,
        1,
      );
      transforms[bones.indexOf(byName.get(names[i])!)]
        .makeTranslation(...open[i].toArray())
        .multiply(stretch)
        .multiply(
          new THREE.Matrix4().makeTranslation(-start.x, -start.y, -start.z),
        );
    }
    const tip = restPositions.get(names[3])!;
    transforms[bones.indexOf(byName.get(names[3])!)].makeTranslation(
      open[3].x - tip.x,
      open[3].y - tip.y,
      open[3].z - tip.z,
    );
    names.forEach((name, i) => byName.get(name)!.position.copy(open[i]));
    return { rig, names, directions };
  });
  const positions = geometry.getAttribute("position");
  const originalPositions = positions.clone();
  const indices = geometry.getAttribute("skinIndex"),
    weights = geometry.getAttribute("skinWeight");
  for (let i = 0; i < positions.count; i++) {
    const vertex = new THREE.Vector3().fromBufferAttribute(positions, i);
    const shaped = new THREE.Vector3();
    for (let j = 0; j < 4; j++) {
      const weight = weights.getComponent(i, j);
      if (weight)
        shaped.addScaledVector(
          vertex.clone().applyMatrix4(transforms[indices.getComponent(i, j)]),
          weight,
        );
    }
    positions.setXYZ(i, shaped.x, shaped.y, shaped.z);
  }
  geometry.computeVertexNormals();
  mesh.updateMatrixWorld(true);
  const skeleton = new THREE.Skeleton(bones);
  mesh.bind(skeleton);
  skeleton.update();
  try {
    const bindDiagnostics = inspectHandSurface(mesh, originalPositions);
    if (
      bindDiagnostics.maxStretch > 5 ||
      bindDiagnostics.stretchedEdges / bindDiagnostics.edges > 0.005 ||
      bindDiagnostics.collapsedTriangles / bindDiagnostics.triangles > 0.02
    ) {
      throw new Error(
        "Scanned thumb/palm attachments would stretch the hand skin excessively. Rescan with your palm flat and thumb visible.",
        { cause: { phase: "bind", ...bindDiagnostics } },
      );
    }
    const anchors: Record<string, THREE.Bone> = {};
    for (const { rig, names, directions } of chains) {
      for (let i = 0; i < 4; i++) {
        const segment = Math.min(i, 2);
        const targetDirection = rig.points[segment + 1]
          .clone()
          .sub(rig.points[segment])
          .normalize();
        // Minimum rotation preserves the authored thumb's opposition/roll. A
        // frame rebuilt against world Z has a discontinuity near vertical bones.
        const delta = new THREE.Quaternion().setFromUnitVectors(
          directions[segment],
          targetDirection,
        );
        const bone = byName.get(names[i])!;
        bone.position.copy(rig.points[i]);
        bone.quaternion.copy(delta).multiply(restRotations.get(names[i])!);
        anchors[`${rig.name}:${i}`] = bone;
      }
    }
    mesh.updateMatrixWorld(true);
    skeleton.update();
    const diagnostics = assertHandSurface(mesh);
    return { mesh, anchors, diagnostics, bindDiagnostics };
  } catch (error) {
    disposeHand({ mesh });
    throw error;
  }
}

export function disposeHand({ mesh }: { mesh: THREE.SkinnedMesh }) {
  mesh.geometry.dispose();
  (mesh.material as THREE.Material).dispose();
  mesh.skeleton.dispose();
}
