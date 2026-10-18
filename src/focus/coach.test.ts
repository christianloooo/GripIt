import { describe, expect, it, vi, afterEach } from "vitest";
import fixture from "../contracts/fixtures/focus-assessment-four-seam.json";
import type { FocusAssessment } from "../contracts/assessment";
import { buildCoachInput, isUsableRewrite } from "./coachPrompt";
import { coach, withCoaching } from "./coach";

const assessment = fixture as FocusAssessment;

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("rewrite guard", () => {
  it("accepts a rewrite that only reuses numbers it was shown", () => {
    expect(
      isUsableRewrite(
        "Your spin efficiency came in at 72%. Keep the wrist firm and stay behind the ball.",
        assessment,
      ),
    ).toBe(true);
  });

  it("rejects a number the model was never given", () => {
    // 2400 appears nowhere in the assessment. A fabricated figure reads as
    // authoritative, which makes it worse than an awkward sentence.
    expect(
      isUsableRewrite("Your spin was 2400 rpm, so stay behind the ball.", assessment),
    ).toBe(false);
  });

  it("rejects a rewrite naming a zone this hand cannot reach", () => {
    const unreachable: FocusAssessment = {
      ...assessment,
      unreachableZones: ["thumb-pad"],
    };
    expect(
      isUsableRewrite("Press a little firmer with the thumb pad.", unreachable),
    ).toBe(false);
    expect(
      isUsableRewrite("Keep the wrist firm through release.", unreachable),
    ).toBe(true);
  });

  it("rejects output that is empty or runs long enough to break the panel", () => {
    expect(isUsableRewrite("ok", assessment)).toBe(false);
    expect(isUsableRewrite("word ".repeat(200), assessment)).toBe(false);
  });

  it("shows the model the findings but never the ids it should not echo", () => {
    const input = buildCoachInput(assessment);
    expect(input).toContain("72%");
    expect(input).toContain("wrist");
    expect(input).not.toContain("assessmentId");
    expect(input).not.toContain("ruleVersion");
  });
});

describe("coach client", () => {
  it("uses the rewrite when the proxy returns one", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({ detail: "Stay behind it.", rewritten: true }),
          { status: 200 },
        ),
      ),
    );
    const result = await coach(assessment);
    expect(result).toEqual({
      detail: "Stay behind it.",
      rewritten: true,
      reason: undefined,
    });
  });

  // The demo must survive a bad venue network. Each of these returns the
  // deterministic sentence rather than nothing.
  it.each([
    ["a server error", () => Promise.resolve(new Response("", { status: 500 }))],
    ["a network failure", () => Promise.reject(new Error("offline"))],
    [
      "an empty body",
      () => Promise.resolve(new Response(JSON.stringify({}), { status: 200 })),
    ],
  ])("falls back on %s", async (_label, impl) => {
    vi.stubGlobal("fetch", vi.fn().mockImplementation(impl));
    const result = await coach(assessment);
    expect(result.detail).toBe(assessment.nextAction.detail);
    expect(result.rewritten).toBe(false);
  });

  it("falls back when the proxy hangs past the timeout", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockImplementation(
        (_url: string, init: RequestInit) =>
          new Promise((_resolve, reject) => {
            init.signal?.addEventListener("abort", () =>
              reject(Object.assign(new Error("aborted"), { name: "AbortError" })),
            );
          }),
      ),
    );
    const result = await coach(assessment, { timeoutMs: 10 });
    expect(result.detail).toBe(assessment.nextAction.detail);
    expect(result.reason).toBe("timeout");
  });

  it("folds a rewrite in without disturbing any finding", () => {
    const merged = withCoaching(assessment, {
      detail: "Stay behind it.",
      rewritten: true,
    });
    expect(merged.nextAction.detail).toBe("Stay behind it.");
    expect(merged.nextAction.rewritten).toBe(true);
    expect(merged.zones).toEqual(assessment.zones);
    expect(merged.confidence).toBe(assessment.confidence);
    expect(merged.nextAction.zoneId).toBe(assessment.nextAction.zoneId);
  });
});
