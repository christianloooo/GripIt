import { afterEach, expect, it, vi } from "vitest";
import {
  clearFailures,
  getFailures,
  recordFailure,
  subscribeFailures,
} from "./failureLog";
afterEach(() => {
  clearFailures();
  vi.unstubAllGlobals();
});
it("records errors and diagnostics, notifies the log UI, and bounds persisted history", () => {
  const storage = { setItem: vi.fn() };
  vi.stubGlobal("localStorage", storage);
  const changed = vi.fn();
  const unsubscribe = subscribeFailures(changed);
  for (let i = 0; i < 55; i++)
    recordFailure("model", new Error(`failure ${i}`), { maxStretch: i });
  expect(getFailures()).toHaveLength(50);
  expect(getFailures()[0].message).toBe("failure 5");
  expect(getFailures()[49].details).toEqual({ maxStretch: 54 });
  expect(JSON.parse(storage.setItem.mock.calls.at(-1)![1])).toHaveLength(50);
  expect(changed).toHaveBeenCalledTimes(55);
  unsubscribe();
});
it("keeps the failure log usable when browser storage is blocked", () => {
  vi.stubGlobal("localStorage", {
    setItem: () => {
      throw new Error("Storage blocked");
    },
  });
  expect(() =>
    recordFailure("scan", new Error("No usable frames"), {
      rejections: { "Thumb hidden": 40 },
    }),
  ).not.toThrow();
  expect(getFailures().at(-1)?.message).toBe("No usable frames");
  clearFailures();
  expect(getFailures()).toHaveLength(0);
});
