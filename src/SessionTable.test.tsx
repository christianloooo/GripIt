// @vitest-environment jsdom
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { cleanup, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SessionTable } from "./SessionTable";
import type { SessionTableProps } from "./SessionTable";

beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(cleanup);
const props: SessionTableProps = {
  pitchId: "four-seam",
  pitchName: "Four-seam fastball",
  onBack: vi.fn(),
};

it("shows field-specific errors and keeps a typo for correction", async () => {
  const user = userEvent.setup();
  const onSaved = vi.fn();
  render(<SessionTable {...props} onSaved={onSaved} />);
  await user.type(screen.getByLabelText("Throw 1 Velocity"), "900");
  await user.click(
    screen.getByRole("button", { name: "Save & review session" }),
  );
  expect(screen.getByRole("alert").textContent).toContain(
    "Check the highlighted fields",
  );
  expect(
    screen.getByLabelText("Throw 1 Velocity").getAttribute("aria-invalid"),
  ).toBe("true");
  expect(
    (screen.getByLabelText("Throw 1 Velocity") as HTMLInputElement).value,
  ).toBe("900");
  expect(onSaved).not.toHaveBeenCalled();
});

it("saves one manual throw, preserves zero score and exposes the v1 callback", async () => {
  const user = userEvent.setup();
  const onSaved = vi.fn();
  render(<SessionTable {...props} onSaved={onSaved} />);
  for (const [name, value] of [
    ["Velocity", "82.4"],
    ["Total spin", "2180"],
    ["Spin direction", "12:30"],
    ["Spin efficiency", "84"],
    ["Release height", "5.8"],
    ["Rapsodo score", "0"],
  ]) {
    await user.type(screen.getByLabelText(`Throw 1 ${name}`), value);
  }
  await user.click(
    screen.getByRole("button", { name: "Save & review session" }),
  );
  const record = onSaved.mock.calls[0][0][0];
  expect(record).toMatchObject({
    schemaVersion: "1.0.0",
    pitchId: "four-seam",
    source: "manual",
    measurements: {
      spinDirectionClock: 12.5,
      spinEfficiencyPercent: 84,
      gyroDegree: null,
      rapsodoScore: 0,
    },
  });
  expect(
    screen.getByRole("heading", { name: "Your session at a glance." }),
  ).toBeTruthy();
  await user.click(
    screen.getByRole("button", { name: "Save & review session" }),
  );
  const history = screen.getByRole("region", { name: "Saved this visit" });
  expect(within(history).getAllByRole("listitem")).toHaveLength(1);
});

it("saves three sample throws, retains sample provenance after edits, and starts fresh manual entries", async () => {
  const user = userEvent.setup();
  const onSaved = vi.fn();
  render(<SessionTable {...props} onSaved={onSaved} />);
  await user.click(screen.getByRole("button", { name: "Load sample session" }));
  await user.clear(screen.getByLabelText("Throw 1 Velocity"));
  await user.type(screen.getByLabelText("Throw 1 Velocity"), "80");
  await user.click(
    screen.getByRole("button", { name: "Save & review session" }),
  );
  expect(onSaved.mock.calls[0][0]).toHaveLength(3);
  expect(
    onSaved.mock.calls[0][0].every(
      (record: { source: string }) => record.source === "sample",
    ),
  ).toBe(true);
  await user.click(screen.getByRole("button", { name: "Start real session" }));
  expect(
    (screen.getByLabelText("Throw 1 Velocity") as HTMLInputElement).value,
  ).toBe("");
  expect(
    screen.queryByText("These are made-up throws for testing.", {
      exact: false,
    }),
  ).toBeNull();
  expect(
    within(
      screen.getByRole("region", { name: "Saved this visit" }),
    ).getAllByRole("listitem"),
  ).toHaveLength(1);
});

it("clears efficiency when switching to gyro and preserves drafts across pitch changes", async () => {
  const user = userEvent.setup();
  const onSaved = vi.fn();
  const view = render(<SessionTable {...props} onSaved={onSaved} />);
  await user.click(screen.getByRole("button", { name: "Load sample session" }));
  await user.selectOptions(
    screen.getByLabelText("Throw 1 spin measurement"),
    "gyro",
  );
  expect(
    (screen.getByLabelText("Throw 1 Gyro degree") as HTMLInputElement).value,
  ).toBe("");
  await user.type(screen.getByLabelText("Throw 1 Gyro degree"), "-15");
  await user.click(screen.getByRole("button", { name: "Remove throw 3" }));
  await user.click(screen.getByRole("button", { name: "Remove throw 2" }));
  await user.click(
    screen.getByRole("button", { name: "Save & review session" }),
  );
  expect(onSaved.mock.calls[0][0][0].measurements).toMatchObject({
    spinEfficiencyPercent: null,
    gyroDegree: -15,
  });
  view.rerender(
    <SessionTable {...props} pitchId="slider" pitchName="Slider" />,
  );
  expect(
    ((await screen.findByLabelText("Throw 1 Velocity")) as HTMLInputElement)
      .value,
  ).toBe("");
  view.rerender(<SessionTable {...props} />);
  expect(
    ((await screen.findByLabelText("Throw 1 Velocity")) as HTMLInputElement)
      .value,
  ).toBe("82.4");
});
