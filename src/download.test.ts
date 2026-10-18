import { afterEach, expect, it, vi } from "vitest";
import { downloadJSON } from "./download";
afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});
it("hands JSON exports to the Swift share bridge", () => {
  const postMessage = vi.fn();
  vi.stubGlobal("window", {
    webkit: { messageHandlers: { gripit: { postMessage } } },
  });
  downloadJSON("gripit-test.json", { value: 42 });
  expect(postMessage).toHaveBeenCalledWith({
    action: "export",
    filename: "gripit-test.json",
    content: JSON.stringify({ value: 42 }, null, 2),
  });
});
it("preserves normal browser downloads outside the iOS app", () => {
  vi.useFakeTimers();
  const a = { href: "", download: "", click: vi.fn() };
  vi.stubGlobal("window", {});
  vi.stubGlobal("document", { createElement: () => a });
  const createObjectURL = vi.fn(() => "blob:export");
  vi.stubGlobal("URL", { createObjectURL, revokeObjectURL: vi.fn() });
  downloadJSON("grip.json", { pitch: "slider" });
  expect(a.download).toBe("grip.json");
  expect(a.href).toBe("blob:export");
  expect(a.click).toHaveBeenCalledOnce();
  vi.runAllTimers();
});
