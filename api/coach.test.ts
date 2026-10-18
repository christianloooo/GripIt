import { describe, expect, it } from "vitest";
import { resolveCoachModel } from "./coach";

describe("model resolution", () => {
  // An unset key in a .env file arrives as "", not undefined, so `??` silently
  // sent an empty model and the API answered 400. The deterministic sentence
  // still shipped, which is exactly why this was invisible without a live call.
  it("falls back when the environment supplies an empty value", () => {
    expect(resolveCoachModel("")).toBe("claude-opus-5");
    expect(resolveCoachModel("   ")).toBe("claude-opus-5");
    expect(resolveCoachModel(undefined)).toBe("claude-opus-5");
  });

  it("uses an explicit override", () => {
    expect(resolveCoachModel("claude-haiku-4-5")).toBe("claude-haiku-4-5");
    expect(resolveCoachModel(" claude-sonnet-5 ")).toBe("claude-sonnet-5");
  });
});
