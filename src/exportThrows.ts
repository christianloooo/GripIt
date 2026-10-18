import type { ThrowRecord } from "./throwEntry";

/** The JSON is an array of v1 ThrowRecord values, ready for Step 4. */
export function exportThrows(records: ThrowRecord[]) {
  if (!records.length) throw new Error("There are no saved throws to export.");
  const filename = `gripit-${records[0].sessionId}.json`;
  const content = JSON.stringify(records, null, 2);
  const native = (
    window as Window & {
      webkit?: {
        messageHandlers?: {
          gripit?: { postMessage: (message: Record<string, string>) => void };
        };
      };
    }
  ).webkit?.messageHandlers?.gripit;
  if (native) {
    native.postMessage({ action: "export", filename, content });
    return;
  }
  const url = URL.createObjectURL(
    new Blob([content], { type: "application/json" }),
  );
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
