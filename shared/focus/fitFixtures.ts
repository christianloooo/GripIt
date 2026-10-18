import profileFixture from "../contracts/fixtures/hand-profile-small-right.json";
import planFixture from "../contracts/fixtures/grip-plan-four-seam.json";
import type { HandProfile } from "../contracts/handProfile";
import type { GripPlan } from "../contracts/gripPlan";

/** Stand-ins until the scanner and step 2 supply real ones. */
export const profile = profileFixture as HandProfile;
export const plan = planFixture as GripPlan;
