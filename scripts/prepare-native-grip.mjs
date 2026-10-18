// Convert our licensed GLB assets to data consumed directly by the Swift viewer.
// Run only when changing source models. Xcode consumes the checked-in outputs.
import * as T from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { GLTFExporter } from "three/examples/jsm/exporters/GLTFExporter.js";
import { readFileSync, writeFileSync, copyFileSync } from "node:fs";
const out = "ios/GripItScannerCore/Sources/GripItScannerCore/Resources/";
const bytes = readFileSync("public/models/right-hand.glb");
const gltf = await new GLTFLoader().parseAsync(
  bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
  "",
);
let mesh;
gltf.scene.traverse((o) => {
  if (o.isSkinnedMesh) mesh = o;
});
mesh.updateWorldMatrix(true, true);
const bones = mesh.skeleton.bones;
const at = (n) =>
  bones.find((b) => b.name === n).getWorldPosition(new T.Vector3());
const wrist = at("wrist"),
  y = at("middle-finger-phalanx-proximal").sub(wrist).normalize();
const x = at("index-finger-phalanx-proximal").sub(
  at("pinky-finger-phalanx-proximal"),
);
x.addScaledVector(y, -x.dot(y)).normalize();
const z = x.clone().cross(y).normalize();
const rotation = new T.Matrix4().makeBasis(x, y, z).invert();
const canonical = (p) =>
  p.clone().sub(wrist).applyMatrix4(rotation).multiplyScalar(1000).toArray();
const pos = mesh.geometry.getAttribute("position"),
  si = mesh.geometry.getAttribute("skinIndex"),
  sw = mesh.geometry.getAttribute("skinWeight");
// Weld UV duplicates before subdivision, so joint creases and normals stay connected.
let vertices = [],
  weights = [],
  triangles = [],
  weld = new Map(),
  remap = [];
for (let i = 0; i < pos.count; i++) {
  const p = canonical(
    new T.Vector3().fromBufferAttribute(pos, i).applyMatrix4(mesh.matrixWorld),
  );
  const key = p.map((v) => v.toFixed(5)).join(",");
  if (!weld.has(key)) {
    weld.set(key, vertices.length);
    vertices.push(p);
    const w = Array(bones.length).fill(0);
    for (let j = 0; j < 4; j++)
      w[si.getComponent(i, j)] += sw.getComponent(i, j);
    weights.push(w);
  }
  remap.push(weld.get(key));
}
const ix = mesh.geometry.index;
for (let i = 0; i < ix.count; i += 3)
  triangles.push([0, 1, 2].map((j) => remap[ix.getX(i + j)]));
const blend = (arrays, coeff) =>
  arrays[0].map((_, i) => arrays.reduce((s, a, j) => s + a[i] * coeff[j], 0));
for (let iteration = 0; iteration < 2; iteration++) {
  const edges = new Map(),
    neighbors = vertices.map(() => new Set());
  for (const tri of triangles)
    for (let j = 0; j < 3; j++) {
      const a = tri[j],
        b = tri[(j + 1) % 3],
        c = tri[(j + 2) % 3],
        key = [Math.min(a, b), Math.max(a, b)].join(":");
      if (!edges.has(key)) edges.set(key, { a, b, op: [] });
      edges.get(key).op.push(c);
      neighbors[a].add(b);
      neighbors[b].add(a);
    }
  const boundary = vertices.map(() => []);
  for (const e of edges.values())
    if (e.op.length === 1) {
      boundary[e.a].push(e.b);
      boundary[e.b].push(e.a);
    }
  const smooth = (values) =>
    values.map((v, i) => {
      const near = boundary[i].length === 2 ? boundary[i] : [...neighbors[i]],
        beta =
          boundary[i].length === 2
            ? 1 / 8
            : near.length === 3
              ? 3 / 16
              : 3 / (8 * near.length);
      return blend(
        [v, ...near.map((j) => values[j])],
        [1 - near.length * beta, ...near.map(() => beta)],
      );
    });
  const nv = smooth(vertices),
    nw = smooth(weights);
  for (const e of edges.values()) {
    e.index = nv.length;
    const ids = e.op.length === 2 ? [e.a, e.b, ...e.op] : [e.a, e.b],
      co = e.op.length === 2 ? [3 / 8, 3 / 8, 1 / 8, 1 / 8] : [0.5, 0.5];
    nv.push(
      blend(
        ids.map((i) => vertices[i]),
        co,
      ),
    );
    nw.push(
      blend(
        ids.map((i) => weights[i]),
        co,
      ),
    );
  }
  const edge = (a, b) =>
    edges.get([Math.min(a, b), Math.max(a, b)].join(":")).index;
  const nt = [];
  for (const [a, b, c] of triangles) {
    const ab = edge(a, b),
      bc = edge(b, c),
      ca = edge(c, a);
    nt.push([a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]);
  }
  vertices = nv;
  weights = nw;
  triangles = nt;
}
const joints = bones.map((b) => ({
  name: b.name,
  position: canonical(b.getWorldPosition(new T.Vector3())),
}));
// XR tip markers sit inside the pad. The scan contract measures to the visible
// fingertip, so move those reference markers to the mesh cap before resizing.
for (const finger of ["thumb", "index", "middle", "ring", "pinky"]) {
  const prefix = finger === "thumb" ? "thumb" : `${finger}-finger`;
  const a = joints.findIndex((j) => j.name === `${prefix}-phalanx-distal`);
  const b = joints.findIndex((j) => j.name === `${prefix}-tip`);
  const start = new T.Vector3(...joints[a].position);
  const dir = new T.Vector3(...joints[b].position).sub(start).normalize();
  let end = 0;
  vertices.forEach((v, i) => {
    if (weights[i][a] + weights[i][b] > 0.6)
      end = Math.max(end, new T.Vector3(...v).sub(start).dot(dir));
  });
  joints[b].position = start.addScaledVector(dir, end).toArray();
}
// Anatomical bind-surface refinement. Keep the wrist/palm weights anchored below
// MCP/CMC joints; smooth subdivision alone spreads bending weights into the palm.
const smoothstep = (x) => {
  const t = Math.max(0, Math.min(1, x));
  return t * t * (3 - 2 * t);
};
const wristIndex = joints.findIndex((j) => j.name === "wrist");
for (const finger of ["thumb", "index", "middle", "ring", "pinky"]) {
  const prefix = finger === "thumb" ? "thumb" : `${finger}-finger`;
  const names =
    finger === "thumb"
      ? [
          "thumb-metacarpal",
          "thumb-phalanx-proximal",
          "thumb-phalanx-distal",
          "thumb-tip",
        ]
      : [
          `${prefix}-phalanx-proximal`,
          `${prefix}-phalanx-intermediate`,
          `${prefix}-phalanx-distal`,
          `${prefix}-tip`,
        ];
  const ids = names.map((n) => joints.findIndex((j) => j.name === n));
  const centers = ids.map((id) => new T.Vector3(...joints[id].position));
  const segments = centers.slice(0, 3).map((a, k) => {
    const d = centers[k + 1].clone().sub(a);
    return { a, length: d.length(), dir: d.normalize() };
  });
  const rootAxis = segments[0].dir;
  const palmBone =
    finger === "thumb"
      ? wristIndex
      : joints.findIndex((j) => j.name === `${prefix}-metacarpal`);
  vertices.forEach((position, i) => {
    const v = new T.Vector3(...position);
    const rootAlong = v.clone().sub(centers[0]).dot(rootAxis);
    const attachment = smoothstep((rootAlong + 5) / 14);
    const released = weights[i][ids[0]] * (1 - attachment);
    weights[i][ids[0]] -= released;
    weights[i][palmBone] += released;
    const influence = ids.reduce((n, id) => n + weights[i][id], 0);
    if (influence < 0.65 || rootAlong < 4) return;
    let nearest;
    segments.forEach((segment, k) => {
      const along = v.clone().sub(segment.a).dot(segment.dir);
      const t = Math.max(0, Math.min(segment.length, along));
      const center = segment.a.clone().addScaledVector(segment.dir, t);
      const distance = center.distanceTo(v);
      if (!nearest || distance < nearest.distance)
        nearest = { segment, k, along, center, distance };
    });
    // Leave the terminal cap untouched, preserving measured skin-tip calibration.
    if (nearest.k === 2 && nearest.along > nearest.segment.length * 0.75)
      return;
    const radial = v.clone().sub(nearest.center);
    const palmar = Math.max(0, radial.clone().normalize().z);
    const dorsal = Math.max(0, -radial.clone().normalize().z);
    const distances = [1, 2].map((k) => {
      const delta = v.clone().sub(centers[k]);
      return delta.dot(segments[k].dir);
    });
    const bulge = distances.reduce(
      (n, d) => n + 0.075 * Math.exp(-Math.pow(d / 4.2, 2)),
      0,
    );
    const crease =
      distances.reduce(
        (n, d) => n + 0.1 * Math.exp(-Math.pow(d / 1.25, 2)),
        0,
      ) *
      palmar *
      palmar;
    const shape =
      (bulge * (0.3 + 0.7 * dorsal) - crease) *
      smoothstep((influence - 0.6) / 0.3);
    vertices[i] = v.addScaledVector(radial, shape).toArray();
  });
}
// Low relief palmar creases preserve the connected topology and palm volume.
vertices = vertices.map((position, i) => {
  const [x, y, z] = position;
  const fingerWeight = joints.reduce(
    (sum, j, k) =>
      sum +
      (j.name.includes("phalanx") || j.name.endsWith("tip")
        ? weights[i][k]
        : 0),
    0,
  );
  if (fingerWeight > 0.25 || y < 12 || y > 80) return position;
  const front = smoothstep((z - 6) / 15);
  const across = 65 + 0.12 * x - 0.004 * x * x;
  const mid = 44 - 0.22 * x;
  const crease =
    0.7 * Math.exp(-Math.pow((y - across) / 1.4, 2)) +
    0.5 * Math.exp(-Math.pow((y - mid) / 1.5, 2));
  return [x, y, z - crease * front * smoothstep((38 - Math.abs(x)) / 12)];
});
writeFileSync(
  out + "grip-hand.json",
  JSON.stringify({ vertices, weights, joints, indices: triangles.flat() }),
);
// A portable, genuinely rigged 3D review asset shares the native bind geometry.
// Native rendering retains all dense weights; glTF's standard four influences
// are normalized here for tools that do not support the native dense format.
const reviewGeometry = new T.BufferGeometry();
reviewGeometry.setAttribute(
  "position",
  new T.Float32BufferAttribute(
    vertices.flat().map((v) => v / 1000),
    3,
  ),
);
reviewGeometry.setIndex(triangles.flat());
reviewGeometry.computeVertexNormals();
const skinIndices = [],
  skinWeights = [];
let maxDiscardedWeight = 0;
for (const weight of weights) {
  const sorted = weight
    .map((value, index) => ({ value, index }))
    .sort((a, b) => b.value - a.value)
    .slice(0, 4);
  const sum = sorted.reduce((total, w) => total + w.value, 0);
  maxDiscardedWeight = Math.max(maxDiscardedWeight, 1 - sum);
  skinIndices.push(...sorted.map((w) => w.index));
  skinWeights.push(...sorted.map((w) => w.value / sum));
}
reviewGeometry.setAttribute(
  "skinIndex",
  new T.Uint16BufferAttribute(skinIndices, 4),
);
reviewGeometry.setAttribute(
  "skinWeight",
  new T.Float32BufferAttribute(skinWeights, 4),
);
const reviewBones = joints.map((j) => {
  const bone = new T.Bone();
  bone.name = j.name;
  return bone;
});
const reviewScene = new T.Scene();
for (let i = 0; i < reviewBones.length; i++) {
  const parent = bones.indexOf(bones[i].parent);
  const position = new T.Vector3(...joints[i].position).divideScalar(1000);
  if (parent >= 0)
    position.sub(new T.Vector3(...joints[parent].position).divideScalar(1000));
  reviewBones[i].position.copy(position);
  (parent >= 0 ? reviewBones[parent] : reviewScene).add(reviewBones[i]);
}
const reviewMesh = new T.SkinnedMesh(
  reviewGeometry,
  new T.MeshStandardMaterial({
    color: 0xb6a090,
    roughness: 0.78,
    metalness: 0,
  }),
);
reviewMesh.name = "GripIt anatomical hand";
reviewScene.add(reviewMesh);
reviewScene.updateMatrixWorld(true);
reviewMesh.bind(new T.Skeleton(reviewBones));
reviewScene.userData = {
  license: readFileSync("public/models/HAND-LICENSE.md", "utf8"),
  source: "Immersive Web WebXR Input Profiles, refined for GripIt",
  maxDiscardedWeight,
};
// GLTFExporter uses the browser FileReader API for its binary Blob output.
globalThis.FileReader = class {
  readAsArrayBuffer(blob) {
    blob.arrayBuffer().then((result) => {
      this.result = result;
      this.onloadend?.();
    });
  }
};
const reviewGLB = await new GLTFExporter().parseAsync(reviewScene, {
  binary: true,
});
writeFileSync(
  "public/models/gripit-anatomical-hand.glb",
  Buffer.from(reviewGLB),
);
console.log(
  `Rigged review GLB exported; maximum four-weight truncation ${(maxDiscardedWeight * 100).toFixed(2)}%.`,
);
// Decode GLB buffer accessors and embedded base-color image without a graphics context.
const ball = readFileSync("public/models/baseball.glb"),
  jsonLength = ball.readUInt32LE(12),
  doc = JSON.parse(ball.subarray(20, 20 + jsonLength)),
  bin = ball.subarray(28 + jsonLength);
const read = (id) => {
  const a = doc.accessors[id],
    v = doc.bufferViews[a.bufferView],
    n = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 }[a.type],
    size = { 5123: 2, 5125: 4, 5126: 4 }[a.componentType];
  return Array.from({ length: a.count }, (_, i) =>
    Array.from({ length: n }, (_, j) => {
      const offset =
        (v.byteOffset ?? 0) +
        (a.byteOffset ?? 0) +
        i * (v.byteStride ?? n * size) +
        j * size;
      return a.componentType === 5126
        ? bin.readFloatLE(offset)
        : size === 2
          ? bin.readUInt16LE(offset)
          : bin.readUInt32LE(offset);
    }),
  );
};
const primitive = doc.meshes[0].primitives[0],
  image =
    doc.images[
      doc.textures[
        doc.materials[primitive.material].pbrMetallicRoughness.baseColorTexture
          .index
      ].source
    ],
  view = doc.bufferViews[image.bufferView];
const texture =
  "grip-baseball." + (image.mimeType === "image/png" ? "png" : "jpg");
writeFileSync(
  out + texture,
  bin.subarray(view.byteOffset, view.byteOffset + view.byteLength),
);
const cloud = JSON.parse(readFileSync("src/baseballSeams.json", "utf8")).map(
  (p) => new T.Vector3(...p).multiplyScalar(36.5),
);
const seams = [];
for (
  let i = 0;
  i < cloud.length;
  i += Math.max(1, Math.ceil(cloud.length / 600))
) {
  const p = cloud[i],
    near = cloud.filter((q) => q.distanceTo(p) < 12),
    mean = near
      .reduce((v, q) => v.add(q), new T.Vector3())
      .divideScalar(near.length);
  let d = new T.Vector3(1, 0.7, 0.3).normalize();
  for (let k = 0; k < 10; k++) {
    const next = new T.Vector3();
    for (const q of near) {
      const a = q.clone().sub(mean);
      next.addScaledVector(a, a.dot(d));
    }
    d = next.normalize();
  }
  seams.push({ position: p.toArray(), tangent: d.toArray() });
}
writeFileSync(
  out + "grip-baseball.json",
  JSON.stringify({
    vertices: read(primitive.attributes.POSITION),
    normals: read(primitive.attributes.NORMAL),
    normalTexture: "grip-baseball-normal.png",
    materialTexture: "grip-baseball-material.png",
    sourceSHA256: doc.extras?.sourceSHA256,
    variant: doc.extras?.variant,
    radiusMm: 36.5,
    uv: read(primitive.attributes.TEXCOORD_0),
    indices: read(primitive.indices).flat(),
    texture,
    seams,
  }),
);
copyFileSync("public/models/HAND-LICENSE.md", out + "grip-hand-license.txt");
// Ball attribution and native PBR maps are generated by import-baseball.py.
console.log(
  `Exported ${vertices.length} connected hand vertices and ${seams.length} seam samples.`,
);
