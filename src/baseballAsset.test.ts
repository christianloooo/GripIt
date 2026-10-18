import { it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
it("renders the imported ball at a 73 mm bounding-sphere diameter", () => {
  const data = readFileSync(
    new URL("../public/models/baseball.glb", import.meta.url),
  );
  expect(data.readUInt32LE(0)).toBe(0x46546c67);
  const length = data.readUInt32LE(12),
    gltf = JSON.parse(data.subarray(20, 20 + length).toString());
  const accessor =
      gltf.accessors[gltf.meshes[0].primitives[0].attributes.POSITION],
    view = gltf.bufferViews[accessor.bufferView];
  const start = 20 + length + 8 + view.byteOffset;
  let radius = 0;
  for (let i = 0; i < accessor.count; i++) {
    const offset = start + i * 12;
    radius = Math.max(
      radius,
      Math.hypot(
        data.readFloatLE(offset),
        data.readFloatLE(offset + 4),
        data.readFloatLE(offset + 8),
      ),
    );
  }
  expect(radius * 2).toBeCloseTo(73, 4);
  const source = readFileSync(
    new URL("../assets/source/Ball.glb", import.meta.url),
  );
  expect(gltf.extras.sourceSHA256).toBe(
    createHash("sha256").update(source).digest("hex"),
  );
  expect(gltf.nodes).toHaveLength(1);
  expect(gltf.nodes[0].name).toBe("Baseball_Ball_Clean");
  expect(gltf.materials[0].normalTexture).toBeDefined();
  expect(
    gltf.materials[0].pbrMetallicRoughness.metallicRoughnessTexture,
  ).toBeDefined();
});
