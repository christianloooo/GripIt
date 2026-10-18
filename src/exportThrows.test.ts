import { afterEach, expect, it, vi } from "vitest";
import { exportThrows } from "./exportThrows";
import { makeThrowRecords, sampleThrowSession } from "./throwEntry";
afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});
it("hands the exact v1 records to an iOS host when available", () => {
  const postMessage = vi.fn();
  vi.stubGlobal("window", {
    webkit: { messageHandlers: { gripit: { postMessage } } },
  });
  const records = makeThrowRecords(sampleThrowSession(), "four-seam");
  exportThrows(records);
  const payload = postMessage.mock.calls[0][0];
  expect(JSON.parse(payload.content)).toEqual(records);
  expect(payload.action).toBe("export");
  expect(payload.filename).toBe(`gripit-${records[0].sessionId}.json`);
});
it("downloads JSON in a browser and releases the blob URL", () => {
  vi.useFakeTimers();
  const anchor = { href: "", download: "", click: vi.fn() };
  const revokeObjectURL = vi.fn();
  vi.stubGlobal("window", {});
  vi.stubGlobal("document", { createElement: () => anchor });
  vi.stubGlobal("URL", {
    createObjectURL: () => "blob:throws",
    revokeObjectURL,
  });
  const records = makeThrowRecords(sampleThrowSession(), "four-seam");
  exportThrows(records);
  expect(anchor.click).toHaveBeenCalledOnce();
  vi.runAllTimers();
  expect(revokeObjectURL).toHaveBeenCalledWith("blob:throws");
  expect(() => exportThrows([])).toThrow();
});
