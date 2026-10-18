// The Swift host opens a native share sheet. Browsers keep their normal download.
export function downloadJSON(filename: string, value: unknown) {
  const content = JSON.stringify(value, null, 2);
  const native = (
    window as Window & {
      webkit?: {
        messageHandlers?: {
          gripit?: { postMessage: (payload: Record<string, string>) => void };
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
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
