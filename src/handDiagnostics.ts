import * as THREE from "three";
import { FINGERS } from "./grip";
import type { FingerRig, Measurements } from "./grip";

export function validateMeasurements(m: Measurements) {
  if (
    !Number.isFinite(m.palmWidth) ||
    m.palmWidth < 45 ||
    m.palmWidth > 125 ||
    !Number.isFinite(m.palmLength ?? 72) ||
    (m.palmLength ?? 72) < 40 ||
    (m.palmLength ?? 72) > 125
  )
    throw new Error(
      "Palm proportions are outside the supported scan range. Rescan with the ball beside your palm.",
    );
  for (const finger of FINGERS) {
    const lengths = m.segments[finger];
    if (!lengths || lengths.some((n) => !Number.isFinite(n) || n < 6 || n > 65))
      throw new Error(
        `${finger}: invalid segment lengths. Rescan with straight fingers and your thumb visible.`,
      );
    if (Math.max(...lengths) / Math.min(...lengths) > 3.5)
      throw new Error(
        `${finger}: inconsistent joint proportions. The scan may have misplaced a joint.`,
      );
    const root = m.knuckles?.[finger];
    if (
      root &&
      (root.length !== 3 ||
        root.some((n) => !Number.isFinite(n) || Math.abs(n) > 150))
    )
      throw new Error(`${finger}: invalid knuckle position.`);
  }
  if (m.knuckles) {
    const thumb = m.knuckles.thumb;
    const palmLength = m.palmLength ?? 72;
    if (
      thumb[0] < 0 ||
      thumb[0] > m.palmWidth * 0.9 ||
      thumb[1] < -palmLength * 1.2 ||
      thumb[1] > -palmLength * 0.12
    )
      throw new Error(
        "Thumb base is inconsistent with the palm. Spread your thumb to the side and rescan with your wrist visible.",
      );
  }
}

export function assertThumbFit(rigs: FingerRig[]) {
  const thumb = rigs.find((r) => r.name === "thumb");
  if (
    !thumb ||
    !Number.isFinite(thumb.error + thumb.clearance) ||
    thumb.error > 12 ||
    thumb.clearance < -2
  )
    throw new Error(
      "Thumb cannot form a supported grip on this baseball with these measurements. Rescan with your whole thumb and wrist visible.",
      {
        cause: {
          phase: "thumb-fit",
          targetGapMm: thumb?.error,
          clearanceMm: thumb?.clearance,
          angles: thumb?.angles,
        },
      },
    );
}

// Compare every triangle edge in the actual posed skin against the personalized
// bind skin. Joint-coordinate agreement alone cannot detect tearing/stretching.
export function inspectHandSurface(
  mesh: THREE.SkinnedMesh,
  reference?: THREE.BufferAttribute | THREE.InterleavedBufferAttribute,
) {
  const positions = mesh.geometry.getAttribute("position");
  const restPositions = reference ?? positions;
  const index = mesh.geometry.index;
  const posed: THREE.Vector3[] = [];
  for (let i = 0; i < positions.count; i++) {
    const p = mesh.getVertexPosition(i, new THREE.Vector3());
    if (!Number.isFinite(p.x + p.y + p.z) || p.length() > 350)
      throw new Error(`Invalid hand surface at vertex ${i}.`);
    posed.push(p);
  }
  let maxStretch = 1,
    stretchedEdges = 0,
    edges = 0,
    collapsedTriangles = 0,
    triangles = 0;
  const seen = new Set<string>();
  for (let i = 0; i < (index?.count ?? positions.count); i += 3) {
    const triangle = [0, 1, 2].map((j) => (index ? index.getX(i + j) : i + j));
    const [a, b, c] = triangle;
    const restA = new THREE.Vector3().fromBufferAttribute(restPositions, a);
    const restArea = new THREE.Vector3()
      .fromBufferAttribute(restPositions, b)
      .sub(restA)
      .cross(
        new THREE.Vector3().fromBufferAttribute(restPositions, c).sub(restA),
      )
      .length();
    if (restArea > 0.5) {
      triangles++;
      const area = posed[b]
        .clone()
        .sub(posed[a])
        .cross(posed[c].clone().sub(posed[a]))
        .length();
      if (area / restArea < 0.05) collapsedTriangles++;
    }
    for (let j = 0; j < 3; j++) {
      const a = triangle[j],
        b = triangle[(j + 1) % 3];
      const key = `${Math.min(a, b)}:${Math.max(a, b)}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const rest = new THREE.Vector3()
        .fromBufferAttribute(restPositions, a)
        .distanceTo(new THREE.Vector3().fromBufferAttribute(restPositions, b));
      if (rest < 0.5) continue; // UV seam duplicates and tiny authored edges
      const stretch = posed[a].distanceTo(posed[b]) / rest;
      maxStretch = Math.max(maxStretch, stretch);
      edges++;
      if (stretch > 3) stretchedEdges++;
    }
  }
  return { maxStretch, stretchedEdges, edges, collapsedTriangles, triangles };
}

export function assertHandSurface(mesh: THREE.SkinnedMesh) {
  const stats = inspectHandSurface(mesh);
  if (
    stats.maxStretch > 5 ||
    stats.stretchedEdges / stats.edges > 0.005 ||
    stats.collapsedTriangles / stats.triangles > 0.02
  )
    throw new Error(
      `Hand skin deformation rejected (${stats.maxStretch.toFixed(1)}× maximum edge stretch, ${stats.stretchedEdges} severely stretched edges, ${stats.collapsedTriangles} collapsed triangles). Try a clearer scan.`,
      { cause: { phase: "pose", ...stats } },
    );
  return stats;
}
