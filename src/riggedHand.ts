import * as THREE from "three";
import type { Finger, FingerRig, Measurements } from "./grip";
const PREFIX: Record<Finger, string> = {
  thumb: "thumb",
  index: "index-finger",
  middle: "middle-finger",
  ring: "ring-finger",
  pinky: "pinky-finger",
};
function frameQuaternion(direction: THREE.Vector3) {
  const y = direction.clone().normalize();
  let x = y.clone().cross(new THREE.Vector3(0, 0, 1));
  if (x.lengthSq() < 1e-8) x = y.clone().cross(new THREE.Vector3(1, 0, 0));
  x.normalize();
  const z = x.clone().cross(y).normalize();
  return new THREE.Quaternion().setFromRotationMatrix(
    new THREE.Matrix4().makeBasis(x, y, z),
  );
}
// Retarget a flat WebXR skeleton to the same FK anchors used by the optimizer.
// Source topology stays connected; no skin mesh is regenerated as the pose changes.
export function retargetHand(
  source: THREE.SkinnedMesh,
  rigs: FingerRig[],
  m: Measurements,
) {
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
  mesh.updateMatrixWorld(true);
  const skeleton = new THREE.Skeleton(bones);
  mesh.bind(skeleton);
  const byName = new Map(bones.map((b) => [b.name, b]));
  const rest = new Map(
    bones.map((b) => [
      b.name,
      { position: b.position.clone(), quaternion: b.quaternion.clone() },
    ]),
  );
  const anchors: Record<string, THREE.Bone> = {};
  for (const rig of rigs) {
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
    let bend = 0;
    for (let i = 0; i < 4; i++) {
      if (i < 3) bend += rig.angles[i];
      const bone = byName.get(names[i])!,
        a = rest.get(names[Math.min(i, 2)])!,
        b = rest.get(names[Math.min(i, 2) + 1])!;
      const restFrame = frameQuaternion(b.position.clone().sub(a.position));
      const targetFrame = new THREE.Quaternion()
        .setFromAxisAngle(new THREE.Vector3(0, 0, 1), rig.yaw)
        .multiply(
          new THREE.Quaternion().setFromAxisAngle(
            new THREE.Vector3(1, 0, 0),
            bend,
          ),
        );
      bone.position.copy(rig.points[i]);
      bone.quaternion
        .copy(targetFrame)
        .multiply(restFrame.invert())
        .multiply(rest.get(names[i])!.quaternion);
      anchors[`${rig.name}:${i}`] = bone;
    }
  }
  mesh.updateMatrixWorld(true);
  skeleton.update();
  return { mesh, anchors };
}
