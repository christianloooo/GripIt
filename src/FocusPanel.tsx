import { useEffect, useState } from "react";
import type { FocusAssessment } from "./contracts/assessment";
import type { ZoneId } from "./contracts/zones";
import { coach } from "./focus/coach";
import "./focusPanel.css";

const ZONE_LABELS: Record<ZoneId, string> = {
  "index-pad": "Index finger",
  "middle-pad": "Middle finger",
  "ring-side": "Ring finger",
  pinky: "Pinky",
  "thumb-pad": "Thumb",
  palm: "Palm",
  wrist: "Wrist",
};

const SEVERITY_ORDER = { red: 0, yellow: 1, green: 2 } as const;

export interface FocusPanelProps {
  assessment: FocusAssessment;
  /** Zone currently highlighted on the model, if any. */
  selectedZone?: ZoneId | null;
  /** Raised when a row is chosen, so the model can highlight the same zone. */
  onZoneSelect?: (zoneId: ZoneId) => void;
}

export function FocusPanel({
  assessment,
  selectedZone,
  onZoneSelect,
}: FocusPanelProps) {
  // The deterministic sentence renders immediately and the rewrite swaps in
  // when it arrives. A spinner here would put the model's latency in front of
  // the player for no benefit: the first sentence is already correct.
  const [detail, setDetail] = useState(assessment.nextAction.detail);
  const [rewritten, setRewritten] = useState(assessment.nextAction.rewritten);

  useEffect(() => {
    let active = true;
    setDetail(assessment.nextAction.detail);
    setRewritten(assessment.nextAction.rewritten);
    coach(assessment).then((result) => {
      if (!active) return;
      setDetail(result.detail);
      setRewritten(result.rewritten);
    });
    return () => {
      active = false;
    };
  }, [assessment]);

  const zones = [...assessment.zones].sort(
    (a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity],
  );
  const notGrip = assessment.classification === "not-grip";

  return (
    <section className="focus-card" aria-labelledby="focus-heading">
      <div className="focus-heading">
        <span className="eyebrow">WHERE TO FOCUS</span>
        <span className="focus-confidence">
          {Math.round(assessment.confidence * 100)}% confidence
        </span>
      </div>
      <h2 id="focus-heading">
        {notGrip ? "This one is not your grip" : "Your focus areas"}
      </h2>
      <p className="focus-description">
        {notGrip
          ? "The numbers point at the arm and timing rather than the hand, so nothing on the grip is marked."
          : "Colours come from the throw you entered. Green looks fine, yellow is worth a look, red is where to start."}
      </p>

      {zones.length > 0 && (
        <div className="focus-zones">
          {zones.map((zone) => {
            const selected = selectedZone === zone.zoneId;
            return (
              <button
                type="button"
                className={`focus-zone${selected ? " selected" : ""}`}
                key={zone.zoneId}
                aria-pressed={selected}
                onClick={() => onZoneSelect?.(zone.zoneId)}
              >
                <span
                  className={`focus-dot ${zone.severity}`}
                  aria-hidden="true"
                />
                <span>
                  <strong>
                    {ZONE_LABELS[zone.zoneId]}
                    <span className="entry-sr-only"> — {zone.severity}</span>
                  </strong>
                  <span className="focus-reason">{zone.reason}</span>
                </span>
              </button>
            );
          })}
        </div>
      )}

      <div className="focus-action">
        <span className="eyebrow">TRY THIS NEXT</span>
        <strong>{assessment.nextAction.summary}</strong>
        <p>{detail}</p>
        {rewritten && <span className="focus-written">WRITTEN FOR YOU</span>}
      </div>

      {assessment.unreachableZones.length > 0 && (
        <p className="focus-fit">
          This grip asks for contact your hand cannot comfortably reach at{" "}
          {assessment.unreachableZones
            .map((zoneId) => ZONE_LABELS[zoneId].toLowerCase())
            .join(" and ")}
          . That is a fit problem, not something to fix with pressure.
        </p>
      )}

      <p className="focus-footnotes">
        {assessment.prototypeAdvice && (
          <>
            Sample advice. These thresholds have not been reviewed by a pitching
            coach.{" "}
          </>
        )}
        Based on {assessment.throwIds.length}{" "}
        {assessment.throwIds.length === 1 ? "throw" : "throws"} · rules{" "}
        {assessment.ruleVersion}
        {assessment.consistency?.inconsistent && (
          <>
            {" "}
            · your throws varied enough that single-throw advice is less
            reliable
          </>
        )}
      </p>
    </section>
  );
}
