// @vitest-environment jsdom
import { describe, expect, it, vi, afterEach } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";
import fixture from "./contracts/fixtures/focus-assessment-four-seam.json";
import type { FocusAssessment } from "./contracts/assessment";
import { FocusPanel } from "./FocusPanel";

const assessment = fixture as FocusAssessment;

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function stubCoach(body: unknown, ok = true) {
  vi.stubGlobal(
    "fetch",
    vi.fn().mockResolvedValue(
      new Response(JSON.stringify(body), { status: ok ? 200 : 500 }),
    ),
  );
}

describe("FocusPanel", () => {
  it("shows the deterministic line before the rewrite arrives", () => {
    vi.stubGlobal("fetch", vi.fn().mockReturnValue(new Promise(() => {})));
    render(<FocusPanel assessment={assessment} />);
    // No spinner: the first sentence is already correct, so the model's
    // latency never blocks the player.
    expect(screen.getByText(assessment.nextAction.detail)).toBeTruthy();
  });

  it("swaps in the rewrite and marks it", async () => {
    stubCoach({ detail: "Stay behind the ball.", rewritten: true });
    render(<FocusPanel assessment={assessment} />);
    await waitFor(() =>
      expect(screen.getByText("Stay behind the ball.")).toBeTruthy(),
    );
    expect(screen.getByText("WRITTEN FOR YOU")).toBeTruthy();
  });

  it("keeps the deterministic line when the rewrite fails", async () => {
    stubCoach({}, false);
    render(<FocusPanel assessment={assessment} />);
    await waitFor(() =>
      expect(screen.getByText(assessment.nextAction.detail)).toBeTruthy(),
    );
    expect(screen.queryByText("WRITTEN FOR YOU")).toBeNull();
  });

  it("orders zones worst first", () => {
    stubCoach({ detail: assessment.nextAction.detail, rewritten: false });
    const { container } = render(<FocusPanel assessment={assessment} />);
    const severities = [...container.querySelectorAll(".focus-dot")].map(
      (dot) => dot.className.replace("focus-dot ", ""),
    );
    expect(severities).toEqual(["red", "red", "yellow", "yellow"]);
  });

  it("explains a fit problem instead of asking for more pressure", () => {
    stubCoach({ detail: assessment.nextAction.detail, rewritten: false });
    render(
      <FocusPanel
        assessment={{ ...assessment, unreachableZones: ["thumb-pad"] }}
      />,
    );
    expect(screen.getByText(/fit problem, not something to fix/)).toBeTruthy();
  });

  it("does not colour fingers when the finding is not about the grip", () => {
    stubCoach({ detail: "Work on your release.", rewritten: false });
    const { container } = render(
      <FocusPanel
        assessment={{
          ...assessment,
          classification: "not-grip",
          zones: [],
          nextAction: { ...assessment.nextAction, zoneId: null },
        }}
      />,
    );
    expect(screen.getByText("This one is not your grip")).toBeTruthy();
    expect(container.querySelectorAll(".focus-dot")).toHaveLength(0);
  });

  it("labels prototype advice and names the rule version", () => {
    stubCoach({ detail: assessment.nextAction.detail, rewritten: false });
    render(<FocusPanel assessment={assessment} />);
    expect(screen.getByText(/Sample advice/)).toBeTruthy();
    expect(screen.getByText(/sample-rules-1/)).toBeTruthy();
  });
});
