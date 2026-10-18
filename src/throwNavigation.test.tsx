// @vitest-environment jsdom
import { afterEach, expect, it, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
vi.mock("./Scene", () => ({ Scene: () => <div>3D grip viewer</div> }));
import App from "./App";
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

it("takes the selected grip into throw entry and retains entries when going back", async () => {
  window.scrollTo = vi.fn();
  Element.prototype.scrollIntoView = vi.fn();
  const user = userEvent.setup();
  render(<App />);
  await user.click(screen.getByRole("button", { name: "Left" }));
  await user.click(screen.getByRole("button", { name: "Next: record throws" }));
  expect(
    screen.getByRole("heading", {
      name: "Let your next pitch tell the story.",
    }),
  ).toBeTruthy();
  expect(screen.getByText("Left-handed")).toBeTruthy();
  await user.type(screen.getByLabelText("Throw 1 Velocity"), "80");
  await user.click(screen.getByRole("button", { name: "Back to your grip" }));
  expect(
    screen.getByRole("heading", {
      name: /Great pitches start\s*with the right grip\./,
    }),
  ).toBeTruthy();
  await user.click(screen.getByRole("button", { name: "Next: record throws" }));
  expect(
    (screen.getByLabelText("Throw 1 Velocity") as HTMLInputElement).value,
  ).toBe("80");
});
