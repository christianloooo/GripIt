// @vitest-environment jsdom
import { describe, expect, it, vi, afterEach } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import fixture from "./contracts/fixtures/focus-assessment-four-seam.json";
import type { FocusAssessment } from "./contracts/assessment";
import { FocusStep } from "./FocusStep";

const assessment = fixture as FocusAssessment;

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function stubCoach() {
  vi.stubGlobal(
    "fetch",
    vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({ detail: assessment.nextAction.detail, rewritten: false }),
        { status: 200 },
      ),
    ),
  );
}

describe("FocusStep", () => {
  it("hands the viewer the colours without exposing anything else", () => {
    stubCoach();
    const renderViewer = vi.fn().mockReturnValue(<div>viewer</div>);
    render(<FocusStep assessment={assessment} renderViewer={renderViewer} />);
    // Step 4 gives step 2 a colour per zone and nothing more: no reasons, no
    // confidence, no throw data.
    expect(renderViewer.mock.calls[0][0].zoneSeverity).toEqual({
      wrist: "red",
      "middle-pad": "red",
      "index-pad": "yellow",
      "thumb-pad": "yellow",
    });
  });

  it("still renders without the step 2 component", () => {
    stubCoach();
    render(<FocusStep assessment={assessment} />);
    expect(screen.getByText(/tinted grip model appears here/)).toBeTruthy();
    expect(screen.getByText("Your focus areas")).toBeTruthy();
  });

  it("selecting a row tells the viewer to highlight the same zone", async () => {
    stubCoach();
    const renderViewer = vi.fn().mockReturnValue(<div>viewer</div>);
    render(<FocusStep assessment={assessment} renderViewer={renderViewer} />);
    expect(renderViewer.mock.calls.at(-1)![0].selectedZone).toBeNull();

    await userEvent.click(screen.getByRole("button", { name: /Wrist/ }));
    expect(renderViewer.mock.calls.at(-1)![0].selectedZone).toBe("wrist");
  });

  it("selecting a zone on the viewer marks the matching row", async () => {
    stubCoach();
    let select: ((zoneId: "wrist") => void) | undefined;
    render(
      <FocusStep
        assessment={assessment}
        renderViewer={({ onZoneSelect }) => {
          select = onZoneSelect;
          return <div>viewer</div>;
        }}
      />,
    );
    await vi.waitFor(() => expect(select).toBeTruthy());
    select!("wrist");
    await vi.waitFor(() =>
      expect(
        screen.getByRole("button", { name: /Wrist/ }).getAttribute("aria-pressed"),
      ).toBe("true"),
    );
  });

  it("selecting the same zone twice clears it", async () => {
    stubCoach();
    render(<FocusStep assessment={assessment} />);
    const row = screen.getByRole("button", { name: /Wrist/ });
    await userEvent.click(row);
    expect(row.getAttribute("aria-pressed")).toBe("true");
    await userEvent.click(row);
    expect(row.getAttribute("aria-pressed")).toBe("false");
  });
});
