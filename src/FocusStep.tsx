import { useState, type ReactNode } from "react";
import type { FocusAssessment } from "./contracts/assessment";
import { toSeverityMap, type ZoneId, type ZoneSeverityMap } from "./contracts/zones";
import { FocusPanel } from "./FocusPanel";
import "./focusStep.css";

export interface FocusStepProps {
  assessment: FocusAssessment;
  /**
   * The tinted grip model from step 2. Taken as a slot rather than imported so
   * this screen can be built and demoed before that component exists, and so
   * step 4 never reaches into step 2's geometry.
   */
  renderViewer?: (props: {
    zoneSeverity: ZoneSeverityMap;
    selectedZone: ZoneId | null;
    onZoneSelect: (zoneId: ZoneId) => void;
  }) => ReactNode;
}

/**
 * The step 4 screen: the same hand and ball from step 2, tinted by the
 * assessment, beside the reasons for those colours. Selection runs both ways,
 * so tapping a finger on the model highlights its row and tapping a row
 * highlights the finger.
 */
export function FocusStep({ assessment, renderViewer }: FocusStepProps) {
  const [selectedZone, setSelectedZone] = useState<ZoneId | null>(null);
  const zoneSeverity = toSeverityMap(assessment.zones);

  const toggle = (zoneId: ZoneId) =>
    setSelectedZone((current) => (current === zoneId ? null : zoneId));

  return (
    <div className="focus-step">
      <div className="focus-viewer">
        {renderViewer ? (
          renderViewer({ zoneSeverity, selectedZone, onZoneSelect: toggle })
        ) : (
          <p className="focus-viewer-placeholder">
            The tinted grip model appears here.
          </p>
        )}
      </div>
      <FocusPanel
        assessment={assessment}
        selectedZone={selectedZone}
        onZoneSelect={toggle}
      />
    </div>
  );
}
