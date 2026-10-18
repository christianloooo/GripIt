import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { handleCoachRequest } from "./coach";
import { handleAskRequest } from "./ask";
import health from "./health";

// Contract fixture matching the native context, with no key or provider call.
const body = JSON.parse(
  readFileSync(
    new URL(
      "../docs/contracts/v1/fixtures/hand-profile-average-right.json",
      import.meta.url,
    ),
    "utf8",
  ),
);
const assessment = JSON.parse(
  readFileSync(
    new URL(
      "../shared/contracts/fixtures/focus-assessment-four-seam.json",
      import.meta.url,
    ),
    "utf8",
  ),
);
const request = (value: unknown, path = "coach") =>
  new Request(`http://localhost/api/${path}`, {
    method: "POST",
    body: typeof value === "string" ? value : JSON.stringify(value),
  });

describe("coaching HTTP boundary", () => {
  it("keeps deterministic feedback when no key is configured", async () => {
    const response = await handleCoachRequest(
      request({ assessment }),
      undefined,
    );
    expect(response.status).toBe(200);
    const payload = await response.json();
    // The detail is the engine's sentence whether or not a key exists, so a
    // missing key is no longer a reason for anything. Without a hand and a
    // grip there is nothing to explain either, which fitReason says.
    expect(payload).toMatchObject({
      detail: assessment.nextAction.detail,
      rewritten: false,
      fitReason: "no-hand-data",
    });
    expect(payload).not.toHaveProperty("reason");
    expect(response.headers.get("server-timing")).toMatch(/total;dur=/);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("x-request-id")).toBeTruthy();
  });

  it("rejects malformed, incomplete and oversized bodies before generation", async () => {
    for (const value of [
      "{",
      {},
      { assessment: { nextAction: { detail: "fake" } } },
      { assessment, profile: body },
      { assessment, profile: body, plan: {} },
    ]) {
      expect((await handleCoachRequest(request(value), undefined)).status).toBe(
        400,
      );
    }
    expect(
      (await handleCoachRequest(request("x".repeat(256 * 1024 + 1)), undefined))
        .status,
    ).toBe(413);
  });

  it("rejects invalid follow-ups and non-POST coaching calls", async () => {
    expect(
      (
        await handleAskRequest(
          request({ assessment, question: "Hi" }, "ask"),
          undefined,
        )
      ).status,
    ).toBe(400);
    expect(
      (
        await handleCoachRequest(
          new Request("http://localhost/api/coach"),
          undefined,
        )
      ).status,
    ).toBe(405);
  });

  it("reports service health without exposing credentials", async () => {
    const response = await health(new Request("http://localhost/api/health"));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });
  });
});
