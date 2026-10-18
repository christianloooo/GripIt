import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
const sdk = vi.hoisted(() => ({ parse: vi.fn(), options: vi.fn() }));
vi.mock("@anthropic-ai/sdk", () => {
  class Client {
    static APIError = class extends Error {};
    static APIConnectionTimeoutError = class extends Error {};
    messages = { parse: sdk.parse };
    constructor(options: unknown) {
      sdk.options(options);
    }
  }
  return { default: Client };
});
import { generate } from "./_client";

describe("generation performance", () => {
  beforeEach(() => {
    vi.stubEnv("COACH_MODEL", "test-model");
    sdk.parse
      .mockReset()
      .mockResolvedValue({
        parsed_output: { text: "Keep your current grip." },
      });
    sdk.options.mockClear();
  });
  afterEach(() => vi.unstubAllEnvs());
  const options = (input: string) => ({
    apiKey: "test-credential",
    system: "Test system",
    input,
    maxTokens: 400,
    reject: () => null,
  });

  it("reuses accepted input and uses a bounded timeout without retries", async () => {
    const a = options("repeat-call");
    await Promise.all([generate(a), generate(a)]);
    await generate(a);
    expect(sdk.parse).toHaveBeenCalledTimes(1);
    expect(sdk.options).toHaveBeenCalledWith(
      expect.objectContaining({ timeout: 6000, maxRetries: 0 }),
    );
  });

  it("changes the key when input, prompt, model or token limit changes", async () => {
    const a = options("changed-call");
    await generate(a);
    await generate({ ...a, input: "updated measurement" });
    await generate({ ...a, system: "New prompt version" });
    await generate({ ...a, maxTokens: 300 });
    vi.stubEnv("COACH_MODEL", "new-model");
    await generate(a);
    expect(sdk.parse).toHaveBeenCalledTimes(5);
  });

  it("does not cache provider failures or rejected text", async () => {
    const a = options("retry-call");
    sdk.parse.mockRejectedValueOnce(new Error("offline"));
    expect((await generate(a)).ok).toBe(false);
    expect((await generate(a)).ok).toBe(true);
    const b = { ...options("rejected-call"), reject: () => "rejected" };
    expect((await generate(b)).ok).toBe(false);
    expect((await generate({ ...b, reject: () => null })).ok).toBe(true);
    expect(sdk.parse).toHaveBeenCalledTimes(4);
  });
});
