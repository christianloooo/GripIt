// JSON boundary for JavaScriptCore. Validation and coaching rules remain the
// same sources used by the web Step 3/4 implementation.
import { validateThrow, makeThrowRecords } from "./throwEntry";
import { assess } from "./focus/assess";
import { DEFAULT_RULE_SET } from "./focus/rules";

export function validateJSON(json: string): string {
  return JSON.stringify(validateThrow(JSON.parse(json)));
}

export function recordsJSON(json: string): string {
  const input = JSON.parse(json);
  return JSON.stringify(makeThrowRecords(input.session, input.pitchId, input.options));
}

export function assessJSON(json: string): string {
  return JSON.stringify(assess({ ...JSON.parse(json), ruleSet: DEFAULT_RULE_SET }));
}
