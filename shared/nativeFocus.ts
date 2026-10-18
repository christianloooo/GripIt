// JSON boundary for JavaScriptCore. Validation and coaching rules remain the
// same sources used by the web Step 3/4 implementation.
import { validateThrow, makeThrowRecords } from "./throwEntry";
import { assess } from "./focus/assess";

export function validateJSON(json: string): string {
  return JSON.stringify(validateThrow(JSON.parse(json)));
}

export function recordsJSON(json: string): string {
  const input = JSON.parse(json);
  return JSON.stringify(makeThrowRecords(input.session, input.pitchId, input.options));
}

// The payload now carries the rules with it: assess() reads GRIP_RULES, so
// there is no rule set to inject here. `baseline` and `handedness` ride in on
// the same object when the caller sends them.
export function assessJSON(json: string): string {
  return JSON.stringify(assess(JSON.parse(json)));
}
