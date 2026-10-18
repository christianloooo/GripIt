import { readFile } from "node:fs/promises";
import { once } from "node:events";
import type { AddressInfo } from "node:net";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createPhotoDemoServer } from "./photo-demo-server.ts";
import { PhotoExtractionError } from "../services/photo-reading/errors.ts";
import type { PhotoExtraction, PhotoExtractor } from "../services/photo-reading/types.ts";

const result: PhotoExtraction = { schemaVersion: "1.0.0", model: "perceptron-mk1.5", warnings: [], readings: {
  velocityMph: 77.3, totalSpinRpm: 1642, spinDirectionClock: "01:56", spinEfficiencyPercent: 93.8,
  gyroDegree: null, horizontalBreakInches: 18.6, verticalBreakInches: 13.8, releaseHeightFeet: null, rapsodoScore: null,
} };
const running: ReturnType<typeof createPhotoDemoServer>[] = [];
async function start(extractor = vi.fn<PhotoExtractor>(async () => result)) {
  const server = createPhotoDemoServer(extractor);
  running.push(server);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return { url: `http://127.0.0.1:${(server.address() as AddressInfo).port}`, extractor };
}
async function image() {
  return readFile("ios/GripItScannerCore/Sources/GripItScannerCore/Resources/rapsodo1.png");
}
async function post(url: string, body: Uint8Array, key = "scan-1", extra = {}) {
  return fetch(`${url}/api/photos/read`, { method: "POST", body: body as BodyInit,
    headers: { "Content-Type": "image/png", "Idempotency-Key": key, ...extra } });
}
afterEach(async () => {
  for (const server of running.splice(0)) {
    server.closeAllConnections();
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});

describe("local photo development server", () => {
  it("returns real extractor output and reuses a successful request without another paid call", async () => {
    const { url, extractor } = await start();
    const bytes = await image();
    const first = await post(url, bytes);
    expect(first.status).toBe(200);
    expect(await first.json()).toEqual({ ...result, requestId: "scan-1" });
    expect(first.headers.get("cache-control")).toBe("no-store");
    expect((await post(url, bytes)).status).toBe(200);
    expect(extractor).toHaveBeenCalledTimes(1);
    expect(extractor.mock.calls[0][0]).toMatchObject({ contentType: "image/png", bytes });
  });

  it("rejects a reused key with different image bytes", async () => {
    const { url, extractor } = await start();
    const bytes = await image();
    await post(url, bytes);
    const changed = Buffer.concat([bytes, Buffer.from("changed")]);
    expect((await post(url, changed)).status).toBe(409);
    expect(extractor).toHaveBeenCalledTimes(1);
  });

  it("does not start a second paid request while an identical scan is running", async () => {
    let release!: (value: PhotoExtraction) => void;
    const extractor = vi.fn<PhotoExtractor>(() => new Promise(resolve => { release = resolve; }));
    const { url } = await start(extractor);
    const bytes = await image();
    const first = post(url, bytes);
    await vi.waitFor(() => expect(extractor).toHaveBeenCalledTimes(1));
    const duplicate = await post(url, bytes);
    expect(duplicate.status).toBe(409);
    expect((await duplicate.json()).error.code).toBe("operation_in_progress");
    release(result);
    expect((await first).status).toBe(200);
    expect(extractor).toHaveBeenCalledTimes(1);
  });

  it("rejects invalid image bytes, missing keys, oversize bodies and unsupported media", async () => {
    const { url, extractor } = await start();
    expect((await post(url, Buffer.from("not an image"))).status).toBe(400);
    expect((await post(url, await image(), "")).status).toBe(400);
    expect((await post(url, await image(), "scan-2", { "Content-Type": "application/json" })).status).toBe(415);
    expect((await post(url, new Uint8Array(4 * 1024 * 1024 + 1))).status).toBe(413);
    expect(extractor).not.toHaveBeenCalled();
  });

  it("rejects browser-origin requests to the unauthenticated local-only service", async () => {
    const { url, extractor } = await start();
    expect((await post(url, await image(), "scan-1", { Origin: "https://unrelated.example" })).status).toBe(403);
    expect(extractor).not.toHaveBeenCalled();
  });

  it("returns sanitized provider failures and permits an explicit retry", async () => {
    const extractor = vi.fn().mockRejectedValueOnce(new PhotoExtractionError("provider_timeout")).mockResolvedValue(result);
    const { url } = await start(extractor);
    const failed = await post(url, await image());
    expect(failed.status).toBe(504);
    expect((await failed.json()).error.code).toBe("provider_timeout");
    expect((await post(url, await image())).status).toBe(200);
    expect(extractor).toHaveBeenCalledTimes(2);
  });

  it("offers health without leaking configuration", async () => {
    const { url } = await start();
    expect(await (await fetch(`${url}/health`)).json()).toEqual({ ok: true, mode: "local-photo-development" });
    expect((await fetch(`${url}/unknown`)).status).toBe(404);
  });
});
