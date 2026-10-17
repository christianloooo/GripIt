import * as THREE from "three";
import { MarchingCubes } from "three/examples/jsm/objects/MarchingCubes.js";
import type { FingerRig, Measurements } from "./grip";

// Reuse the scalar-field workspace across poses. Only the trimmed output is
// uploaded to WebGL, avoiding repeated large allocations during pitch switches.
let workspace: MarchingCubes | undefined;
// A continuous implicit skin surface. Smooth unions connect the palm, thumb pad,
// wrist, and tapered finger capsules without cylinder caps or disconnected joints.
export function createHandSurface(
  rigs: FingerRig[],
  measurements: Measurements,
) {
  const bounds = new THREE.Box3();
  for (const rig of rigs)
    for (const point of rig.points) {
      bounds.expandByPoint(point.clone().addScalar(rig.radius + 8));
      bounds.expandByPoint(point.clone().addScalar(-rig.radius - 8));
    }
  const palmLength = measurements.palmLength ?? 72;
  const width = measurements.palmWidth;
  bounds.expandByPoint(new THREE.Vector3(-width * 0.6, -palmLength - 45, -48));
  bounds.expandByPoint(new THREE.Vector3(width * 0.6, 12, 0));
  const extent = bounds.getSize(new THREE.Vector3());
  const size = Math.max(extent.x, extent.y, extent.z) + 20;
  const center = bounds.getCenter(new THREE.Vector3());
  const resolution = 104;
  if (!workspace)
    workspace = new MarchingCubes(
      resolution,
      new THREE.MeshStandardMaterial(),
      false,
      false,
      100000,
    );
  const mc = workspace;
  mc.normal_cache.fill(0);
  mc.isolation = 0;
  const capsules = rigs.flatMap((r) =>
    r.points.slice(0, -1).map((a, i) => {
      const b = r.points[i + 1],
        dx = b.x - a.x,
        dy = b.y - a.y,
        dz = b.z - a.z;
      return {
        a,
        dx,
        dy,
        dz,
        len: dx * dx + dy * dy + dz * dz,
        r: r.radius * (1 - i * 0.095),
      };
    }),
  );
  const smooth = (a: number, b: number, k = 4) => {
    const h = Math.max(k - Math.abs(a - b), 0) / k;
    return Math.min(a, b) - h * h * k * 0.25;
  };

  const ellipsoid = (
    x: number,
    y: number,
    z: number,
    cx: number,
    cy: number,
    cz: number,
    rx: number,
    ry: number,
    rz: number,
  ) => {
    x -= cx;
    y -= cy;
    z -= cz;
    const k0 = Math.hypot(x / rx, y / ry, z / rz),
      k1 = Math.hypot(x / (rx * rx), y / (ry * ry), z / (rz * rz));
    return k1 > 1e-8 ? (k0 * (k0 - 1)) / k1 : -Math.min(rx, ry, rz);
  };
  let index = 0;
  for (let z = 0; z < resolution; z++)
    for (let y = 0; y < resolution; y++)
      for (let x = 0; x < resolution; x++) {
        const px = (x / resolution - 0.5) * size + center.x,
          py = (y / resolution - 0.5) * size + center.y,
          pz = (z / resolution - 0.5) * size + center.z;
        let sdf = ellipsoid(
          px,
          py,
          pz,
          0,
          -palmLength * 0.43,
          -26,
          width * 0.48,
          palmLength * 0.55,
          13,
        );
        sdf = smooth(
          sdf,
          ellipsoid(
            px,
            py,
            pz,
            width * 0.3,
            -palmLength * 0.46,
            -20,
            width * 0.24,
            palmLength * 0.35,
            15,
          ),
          6,
        );
        sdf = smooth(
          sdf,
          ellipsoid(
            px,
            py,
            pz,
            -width * 0.25,
            -palmLength * 0.48,
            -25,
            width * 0.21,
            palmLength * 0.36,
            12,
          ),
          5,
        );
        sdf = smooth(
          sdf,
          ellipsoid(px, py, pz, 0, -palmLength - 8, -27, width * 0.3, 30, 13),
          6,
        );
        for (const c of capsules) {
          const t = Math.max(
            0,
            Math.min(
              1,
              ((px - c.a.x) * c.dx +
                (py - c.a.y) * c.dy +
                (pz - c.a.z) * c.dz) /
                c.len,
            ),
          );
          const d =
            Math.hypot(
              px - c.a.x - c.dx * t,
              py - c.a.y - c.dy * t,
              pz - c.a.z - c.dz * t,
            ) -
            c.r * (1 - 0.07 * t);
          sdf = smooth(sdf, d, 3);
        }
        mc.field[index++] = -sdf;
      }
  mc.update();
  // Trim unused buffer capacity. Bounds/culling must describe the generated skin,
  // not zero-filled allocation space; reject over-budget output rather than cuts.
  const count = mc.geometry.drawRange.count;
  if (count >= mc.geometry.attributes.position.count)
    throw new Error("Hand surface exceeded its mesh budget.");
  const geometry = new THREE.BufferGeometry();
  for (const name of ["position", "normal"]) {
    const source = mc.geometry.getAttribute(name);
    geometry.setAttribute(
      name,
      new THREE.Float32BufferAttribute(
        (source.array as Float32Array).slice(0, count * 3),
        3,
      ),
    );
  }
  geometry.setDrawRange(0, count);
  geometry.scale(size / 2, size / 2, size / 2);
  geometry.translate(center.x, center.y, center.z);
  // Stable UVs for fine skin pores. No scan photo is retained or projected.
  const pos = geometry.getAttribute("position"),
    uv = new Float32Array(pos.count * 2);
  for (let i = 0; i < pos.count; i++) {
    uv[i * 2] = pos.getX(i) / 100;
    uv[i * 2 + 1] = pos.getY(i) / 100;
  }
  geometry.setAttribute("uv", new THREE.BufferAttribute(uv, 2));
  geometry.computeBoundingBox();
  geometry.computeBoundingSphere();
  return geometry;
}
