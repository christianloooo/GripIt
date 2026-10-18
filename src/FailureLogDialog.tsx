import { useEffect, useRef, useSyncExternalStore } from "react";
import { X } from "lucide-react";
import {
  clearFailures,
  downloadFailures,
  getFailures,
  subscribeFailures,
} from "./failureLog";
export function FailureLogDialog({ onClose }: { onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const entries = useSyncExternalStore(subscribeFailures, getFailures);
  useEffect(() => {
    const dialog = ref.current;
    dialog?.showModal();
    return () => dialog?.close();
  }, []);
  return (
    <dialog
      ref={ref}
      className="scan-dialog failure-log"
      onCancel={onClose}
      aria-labelledby="failure-title"
    >
      <button
        className="dialog-close icon-button"
        onClick={onClose}
        aria-label="Close failure log"
      >
        <X size={20} />
      </button>
      <div className="eyebrow">MODEL DIAGNOSTICS</div>
      <h2 id="failure-title">Failure log</h2>
      <p>
        The last 50 failures stay in this browser. Downloads include measurement
        and deformation diagnostics, never video or images.
      </p>
      <div className="scan-actions">
        <button className="secondary" onClick={downloadFailures}>
          Download log
        </button>
        <button
          className="secondary"
          onClick={clearFailures}
          disabled={!entries.length}
        >
          Clear log
        </button>
      </div>
      {!entries.length ? (
        <p>No failures recorded since logging was added.</p>
      ) : (
        <ol className="failure-entries">
          {[...entries].reverse().map((entry) => (
            <li key={entry.id}>
              <small>
                {new Date(entry.time).toLocaleString()} · {entry.stage}
              </small>
              <p>{entry.message}</p>
              {entry.details !== undefined && (
                <details>
                  <summary>Diagnostic details</summary>
                  <pre>{JSON.stringify(entry.details, null, 2)}</pre>
                </details>
              )}
            </li>
          ))}
        </ol>
      )}
    </dialog>
  );
}
