import { useEffect, useRef, useState } from "react";
import {
  ArrowLeft,
  ArrowRight,
  ArrowDownToLine,
  Check,
  Plus,
  Trash2,
} from "lucide-react";
import {
  emptyThrow,
  makeThrowRecords,
  newThrowSession,
  sampleThrowSession,
  validateThrow,
} from "./throwEntry";
import type {
  EntryField,
  ThrowDraft,
  ThrowRecord,
  ThrowSessionDraft,
} from "./throwEntry";
import { exportThrows } from "./exportThrows";
import "./throwEntry.css";

export interface SessionTableProps {
  pitchId: string;
  pitchName: string;
  handProfileId?: string;
  handedness?: "left" | "right";
  onBack: () => void;
  onSaved?: (records: ThrowRecord[]) => void;
}
type SavedSession = { name: string; records: ThrowRecord[] };

export function SessionTable({
  pitchId,
  pitchName,
  handProfileId,
  handedness = "right",
  onBack,
  onSaved,
}: SessionTableProps) {
  const contextKey = `${pitchId}:${handProfileId ?? "unlinked"}:${handedness}`;
  const [drafts, setDrafts] = useState<Record<string, ThrowSessionDraft>>(
    () => ({ [contextKey]: newThrowSession() }),
  );
  const [history, setHistory] = useState<SavedSession[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [attempted, setAttempted] = useState(false);
  const [touched, setTouched] = useState<Record<string, boolean>>({});
  const [exportError, setExportError] = useState("");
  const reviewRef = useRef<HTMLHeadingElement>(null);
  const panelRef = useRef<HTMLElement>(null);
  const session = drafts[contextKey];
  useEffect(() => {
    setDrafts((prev) =>
      prev[contextKey] ? prev : { ...prev, [contextKey]: newThrowSession() },
    );
    setAttempted(false);
    setTouched({});
    setSelected(null);
  }, [contextKey]);
  useEffect(() => {
    if (selected) {
      reviewRef.current?.focus({ preventScroll: true });
      reviewRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }, [selected, history]);
  if (!session) return <p role="status">Preparing your throw session…</p>;
  const validations = session.rows.map(validateThrow);
  const completeCount = validations.filter((row) => row.measurements).length;
  const review = history.find(
    (saved) => saved.records[0].sessionId === selected,
  );
  const update = (next: ThrowSessionDraft) => {
    setDrafts((prev) => ({ ...prev, [contextKey]: next }));
    setSelected(null);
    setExportError("");
  };
  const updateRow = (id: string, patch: Partial<ThrowDraft>) =>
    update({
      ...session,
      rows: session.rows.map((row) =>
        row.id === id ? { ...row, ...patch } : row,
      ),
    });
  const replaceDraft = (next: ThrowSessionDraft) => {
    update(next);
    setAttempted(false);
    setTouched({});
  };
  const save = () => {
    setAttempted(true);
    if (completeCount !== session.rows.length) {
      requestAnimationFrame(() =>
        panelRef.current
          ?.querySelector<HTMLInputElement>("[aria-invalid=true]")
          ?.focus(),
      );
      return;
    }
    const records = makeThrowRecords(session, pitchId, { handProfileId });
    setHistory((prev) => [
      { name: pitchName, records },
      ...prev.filter(
        (saved) => saved.records[0].sessionId !== session.sessionId,
      ),
    ]);
    setSelected(session.sessionId);
    onSaved?.(records);
  };
  const download = (records: ThrowRecord[]) => {
    try {
      exportThrows(records);
      setExportError("");
    } catch {
      setExportError("The export could not open. Please try again.");
    }
  };
  const field = (
    row: ThrowDraft,
    index: number,
    key: EntryField,
    label: string,
    placeholder: string,
    unit: string,
    optional = false,
  ) => {
    const id = `${row.id}-${key}`;
    const error =
      attempted || touched[id] ? validations[index].errors[key] : undefined;
    return (
      <div className="entry-field">
        <label htmlFor={id}>
          {label}{" "}
          <span>
            {unit}
            {optional ? " · optional" : ""}
          </span>
        </label>
        <input
          id={id}
          aria-label={`Throw ${index + 1} ${label}`}
          type="text"
          inputMode={
            key === "spinDirectionClock" ||
            (key === "spinValue" && row.spinMode === "gyro")
              ? "text"
              : "decimal"
          }
          autoComplete="off"
          autoCapitalize="off"
          spellCheck={false}
          required={!optional}
          value={row[key]}
          placeholder={placeholder}
          aria-invalid={Boolean(error)}
          aria-describedby={error ? `${id}-error` : undefined}
          onBlur={() => setTouched((prev) => ({ ...prev, [id]: true }))}
          onChange={(event) => updateRow(row.id, { [key]: event.target.value })}
        />
        {error && (
          <small id={`${id}-error`} className="entry-error">
            {error}
          </small>
        )}
      </div>
    );
  };

  return (
    <section
      className="throw-entry"
      ref={panelRef}
      aria-labelledby="throw-entry-heading"
    >
      <button className="entry-back" onClick={onBack}>
        <ArrowLeft size={16} /> Back to your grip
      </button>
      <div className="entry-progress">
        <span>
          <Check size={13} /> GRIP SELECTED
        </span>
        <i />
        <strong>03 / THROW & RECORD</strong>
      </div>
      <div className="entry-intro">
        <div>
          <span className="eyebrow">TAKE YOUR GRIP TO THE MOUND</span>
          <h1 id="throw-entry-heading" tabIndex={-1}>
            Let your next pitch <br />
            <em>tell the story.</em>
          </h1>
          <p>
            Throw when you’re ready. Copy the readings from your Rapsodo screen.
          </p>
        </div>
        <div className="entry-context">
          <span className="eyebrow">YOUR SESSION</span>
          <strong>{pitchName}</strong>
          <span>{handedness === "left" ? "Left" : "Right"}-handed</span>
          <button onClick={onBack}>
            Change grip <ArrowLeft size={13} />
          </button>
        </div>
      </div>
      <div className="entry-card">
        <div className="entry-card-heading">
          <div>
            <span className="eyebrow">RAPSODO / MANUAL ENTRY</span>
            <h2>Record your throws</h2>
          </div>
          <span className="entry-count">
            {completeCount} / {session.rows.length} complete
          </span>
        </div>
        <p className="entry-description">
          Five readings per throw. One throw is enough to save a session.
          Rapsodo score is optional.
        </p>
        <div className="entry-sample-tools">
          <span>
            Want to try it first? Sample data replaces unsaved entries.
          </span>
          <button onClick={() => replaceDraft(sampleThrowSession())}>
            Load sample session <ArrowRight size={14} />
          </button>
        </div>
        {session.source === "sample" && (
          <div className="entry-sample-banner" role="status">
            <strong>SAMPLE DATA</strong>
            <span>
              These are made-up throws for testing. Edited sample rows stay
              labeled as sample.
            </span>
            <button onClick={() => replaceDraft(newThrowSession())}>
              Start real session <ArrowRight size={14} />
            </button>
          </div>
        )}
        <form
          noValidate
          onSubmit={(event) => {
            event.preventDefault();
            save();
          }}
        >
          <div className="entry-table-wrap">
            <table className="entry-table">
              <caption className="entry-sr-only">
                Rapsodo readings for {pitchName}. Enter one row per throw.
              </caption>
              <thead>
                <tr>
                  <th scope="col">Throw</th>
                  <th scope="col">
                    Velocity<span>mph</span>
                  </th>
                  <th scope="col">
                    Total spin<span>rpm</span>
                  </th>
                  <th scope="col">
                    Spin direction<span>hh:mm</span>
                  </th>
                  <th scope="col">
                    Efficiency / gyro<span>% or degrees</span>
                  </th>
                  <th scope="col">
                    Release height<span>ft</span>
                  </th>
                  <th scope="col">
                    Rapsodo score<span>optional</span>
                  </th>
                  <th scope="col">
                    <span className="entry-sr-only">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {session.rows.map((row, index) => (
                  <tr key={row.id}>
                    <th scope="row">
                      <span className="entry-row-mobile">Throw </span>
                      {String(index + 1).padStart(2, "0")}
                    </th>
                    <td>
                      {field(
                        row,
                        index,
                        "velocityMph",
                        "Velocity",
                        "e.g. 82.4",
                        "mph",
                      )}
                    </td>
                    <td>
                      {field(
                        row,
                        index,
                        "totalSpinRpm",
                        "Total spin",
                        "e.g. 2180",
                        "rpm",
                      )}
                    </td>
                    <td>
                      {field(
                        row,
                        index,
                        "spinDirectionClock",
                        "Spin direction",
                        "e.g. 12:30",
                        "hh:mm",
                      )}
                    </td>
                    <td className="entry-spin-cell">
                      <label
                        className="entry-sr-only"
                        htmlFor={`${row.id}-mode`}
                      >
                        Throw {index + 1} spin measurement
                      </label>
                      <select
                        id={`${row.id}-mode`}
                        value={row.spinMode}
                        onChange={(event) =>
                          updateRow(row.id, {
                            spinMode: event.target
                              .value as ThrowDraft["spinMode"],
                            spinValue: "",
                          })
                        }
                      >
                        <option value="efficiency">Efficiency (%)</option>
                        <option value="gyro">Gyro degree (°)</option>
                      </select>
                      {field(
                        row,
                        index,
                        "spinValue",
                        row.spinMode === "efficiency"
                          ? "Spin efficiency"
                          : "Gyro degree",
                        row.spinMode === "efficiency" ? "e.g. 84" : "e.g. 15",
                        row.spinMode === "efficiency" ? "%" : "°",
                      )}
                    </td>
                    <td>
                      {field(
                        row,
                        index,
                        "releaseHeightFeet",
                        "Release height",
                        "e.g. 5.8",
                        "ft",
                      )}
                    </td>
                    <td>
                      {field(
                        row,
                        index,
                        "rapsodoScore",
                        "Rapsodo score",
                        "If shown",
                        "",
                        true,
                      )}
                    </td>
                    <td className="entry-remove-cell">
                      {session.rows.length > 1 && (
                        <button
                          type="button"
                          aria-label={`Remove throw ${index + 1}`}
                          onClick={() =>
                            update({
                              ...session,
                              rows: session.rows.filter((r) => r.id !== row.id),
                            })
                          }
                        >
                          <Trash2 size={16} />
                          <span className="entry-row-mobile">Remove</span>
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <button
            type="button"
            className="entry-add"
            onClick={() =>
              update({
                ...session,
                rows: [...session.rows, emptyThrow(session.source)],
              })
            }
          >
            <Plus size={16} /> Add another throw
          </button>
          {attempted && completeCount !== session.rows.length && (
            <p role="alert" className="entry-error-summary">
              Check the highlighted fields. Your entries are kept so you can
              correct them.
            </p>
          )}
          <div className="entry-actions">
            <p>
              Sessions stay in memory during this visit.
              <br />
              Export before refreshing or closing the app.
            </p>
            <button className="primary" type="submit">
              Save & review session <ArrowRight size={16} />
            </button>
          </div>
        </form>
      </div>
      <div className="entry-footnotes">
        <p>
          <strong>Efficiency or gyro?</strong> Use whichever your Rapsodo shows.
          Changing the selection clears the old value.
        </p>
        <p>
          <strong>Clock direction:</strong> enter 12:30, not an angle. Input
          limits catch likely typos; they are not performance targets.
        </p>
      </div>
      {review && (
        <section
          className="entry-review"
          aria-labelledby="entry-review-heading"
        >
          <span className="eyebrow">
            {review.records[0].source === "sample"
              ? "SAMPLE SESSION SAVED"
              : "SESSION SAVED FOR THIS VISIT"}
          </span>
          <h2 id="entry-review-heading" ref={reviewRef} tabIndex={-1}>
            Your session at a glance.
          </h2>
          <div className="entry-stats">
            <div>
              <strong>{review.records.length}</strong>
              <span>
                {review.records.length === 1
                  ? "throw recorded"
                  : "throws recorded"}
              </span>
            </div>
            <div>
              <strong>
                {(
                  review.records.reduce(
                    (sum, row) => sum + row.measurements.velocityMph,
                    0,
                  ) / review.records.length
                ).toFixed(1)}
                <small> mph</small>
              </strong>
              <span>average velocity</span>
            </div>
            <div>
              <strong>
                {Math.round(
                  review.records.reduce(
                    (sum, row) => sum + row.measurements.totalSpinRpm,
                    0,
                  ) / review.records.length,
                )}
                <small> rpm</small>
              </strong>
              <span>average total spin</span>
            </div>
          </div>
          <p>
            Your readings are saved for this visit. Export the session to keep a
            copy.
          </p>
          <button className="primary" onClick={() => download(review.records)}>
            <ArrowDownToLine size={16} /> Export{" "}
            {review.records[0].source === "sample" ? "sample" : "session"} JSON
          </button>
        </section>
      )}
      {exportError && (
        <p role="alert" className="entry-error-summary">
          {exportError}
        </p>
      )}
      {history.length > 0 && (
        <section
          className="entry-history"
          aria-labelledby="entry-history-heading"
        >
          <div>
            <h2 id="entry-history-heading">Saved this visit</h2>
            <button onClick={() => replaceDraft(newThrowSession())}>
              <Plus size={15} /> Start new session
            </button>
          </div>
          <ul>
            {history.map((saved) => (
              <li key={saved.records[0].sessionId}>
                <div>
                  <strong>{saved.name}</strong>
                  <span>
                    {saved.records.length}{" "}
                    {saved.records.length === 1 ? "throw" : "throws"} ·{" "}
                    {new Date(saved.records[0].recordedAt).toLocaleTimeString(
                      [],
                      { hour: "2-digit", minute: "2-digit" },
                    )}
                    {saved.records[0].source === "sample"
                      ? " · SAMPLE DATA"
                      : " · Manual entry"}
                  </span>
                </div>
                <div>
                  <button
                    onClick={() => setSelected(saved.records[0].sessionId)}
                  >
                    Review
                  </button>
                  <button
                    aria-label={`Export ${saved.records[0].sessionId}`}
                    onClick={() => download(saved.records)}
                  >
                    <ArrowDownToLine size={16} /> JSON
                  </button>
                </div>
              </li>
            ))}
          </ul>
        </section>
      )}
    </section>
  );
}
