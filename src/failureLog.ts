export type FailureEntry = {
  id: string;
  time: string;
  stage: "scan" | "model" | "asset";
  message: string;
  details?: unknown;
};
const KEY = "gripit.failures.v1";
const listeners = new Set<() => void>();
let entries: FailureEntry[] = [];
try {
  const saved: unknown = JSON.parse(localStorage.getItem(KEY) ?? "[]");
  if (Array.isArray(saved))
    entries = saved
      .filter(
        (e) => e && typeof e.message === "string" && typeof e.time === "string",
      )
      .slice(-50);
} catch {
  /* Logging must work even when browser storage is unavailable. */
}
export const getFailures = () => entries;
export const subscribeFailures = (listener: () => void) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};
function save() {
  try {
    localStorage.setItem(KEY, JSON.stringify(entries));
  } catch {
    /* Keep the in-memory log. */
  }
  listeners.forEach((listener) => listener());
}
export function recordFailure(
  stage: FailureEntry["stage"],
  error: unknown,
  details?: unknown,
) {
  const message = error instanceof Error ? error.message : String(error);
  entries = [
    ...entries,
    {
      id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
      time: new Date().toISOString(),
      stage,
      message,
      details,
    },
  ].slice(-50);
  save();
}
export function clearFailures() {
  entries = [];
  save();
}
export function downloadFailures() {
  const url = URL.createObjectURL(
    new Blob(
      [
        JSON.stringify(
          {
            version: 1,
            app: "GripIt",
            rigVersion: "proportioned-bind-minimum-rotation-v2",
            failures: entries,
          },
          null,
          2,
        ),
      ],
      { type: "application/json" },
    ),
  );
  const a = document.createElement("a");
  a.href = url;
  a.download = "gripit-failure-log.json";
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
