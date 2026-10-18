import { afterEach, describe, expect, it, vi } from "vitest";
import { createPhotoExtractor, PROVIDER_TIMEOUT_MS } from "./extract.ts";
import type { PhotoReadings } from "./types.ts";

const visible: PhotoReadings = {
  velocityMph: 77.3, totalSpinRpm: 1642, spinDirectionClock: "01:56",
  spinEfficiencyPercent: 93.8, gyroDegree: null, horizontalBreakInches: 18.6,
  verticalBreakInches: 13.8, releaseHeightFeet: null, rapsodoScore: null,
};
const input = { bytes: new Uint8Array([137, 80, 78, 71]), contentType: "image/png" as const };
const completion = (readings: unknown = visible, finishReason = "stop") => Response.json({
  choices: [{ finish_reason: finishReason, message: { content: JSON.stringify(readings) } }],
});
const reader = (response: Response) => createPhotoExtractor({
  apiKey: "test-secret", fetchImpl: vi.fn(async () => response) as typeof fetch,
});

afterEach(() => vi.useRealTimers());

describe("Perceptron photo extraction", () => {
  it("sends actual image bytes with a strict schema, without supplying fixture answers", async () => {
    const transport = vi.fn(async () => completion());
    const result = await createPhotoExtractor({ apiKey: "test-secret", fetchImpl: transport })(input);
    expect(result).toMatchObject({ schemaVersion: "1.0.0", model: "perceptron-mk1.5", readings: visible });
    const [url, options] = transport.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("https://api.perceptron.inc/v1/chat/completions");
    expect(options.headers).toMatchObject({ Authorization: "Bearer test-secret" });
    const body = JSON.parse(options.body as string);
    expect(body.model).toBe("perceptron-mk1.5");
    expect(body.response_format.json_schema.strict).toBe(true);
    expect(body.response_format.json_schema.schema.required).toHaveLength(9);
    expect(body.messages[0].content).toContainEqual({
      type: "image_url", image_url: { url: "data:image/png;base64,iVBORw==" },
    });
    expect(JSON.stringify(body)).not.toContain("77.3");
    expect(JSON.stringify(body)).not.toContain("1642");
    expect(transport).toHaveBeenCalledTimes(1);
  });

  it("preserves missing height and gyro instead of calculating readings", async () => {
    const result = await reader(completion())(input);
    expect(result.readings.gyroDegree).toBeNull();
    expect(result.readings.releaseHeightFeet).toBeNull();
    expect(result.warnings.join(" ")).toContain("Gyro angle");
  });

  it("accepts partial results for manual completion", async () => {
    const result = await reader(completion({ ...visible, velocityMph: null, totalSpinRpm: null }))(input);
    expect(result.readings.velocityMph).toBeNull();
    expect(result.readings.totalSpinRpm).toBeNull();
    expect(result.readings.spinDirectionClock).toBe("01:56");
  });

  it.each([
    ["velocityMph", 900], ["totalSpinRpm", -2], ["gyroDegree", 91],
    ["spinEfficiencyPercent", 101], ["spinDirectionClock", "14:30"],
    ["horizontalBreakInches", 40], ["verticalBreakInches", -40],
    ["releaseHeightFeet", 50], ["rapsodoScore", -1], ["totalSpinRpm", "1642"],
    ["velocityMph", true],
  ])("clears invalid %s instead of forwarding it", async (field, value) => {
    const result = await reader(completion({ ...visible, [field]: value }))(input);
    expect(result.readings[field as keyof PhotoReadings]).toBeNull();
    expect(result.warnings.length).toBeGreaterThan(0);
  });

  it("preserves explicit negative signs and trims valid clock text", async () => {
    const result = await reader(completion({ ...visible, gyroDegree: -18.2,
      horizontalBreakInches: -18.6, spinDirectionClock: " 06:48 " }))(input);
    expect(result.readings.gyroDegree).toBe(-18.2);
    expect(result.readings.horizontalBreakInches).toBe(-18.6);
    expect(result.readings.spinDirectionClock).toBe("06:48");
  });

  it.each([
    {}, [], { ...visible, secret: "unexpected" },
    Object.fromEntries(Object.keys(visible).map(key => [key, null])),
  ])("rejects incomplete, extra-field or completely unreadable extraction %#", async readings => {
    await expect(reader(completion(readings))(input)).rejects.toMatchObject({ code: "invalid_extraction" });
  });

  it("rejects truncated answers even if their JSON parses", async () => {
    await expect(reader(completion(visible, "length"))(input)).rejects.toMatchObject({ code: "invalid_extraction" });
  });

  it("rejects malformed content and tool calls", async () => {
    for (const message of [{ content: "not json" }, { content: JSON.stringify(visible), tool_calls: [{}] }]) {
      await expect(reader(Response.json({ choices: [{ finish_reason: "stop", message }] }))(input))
        .rejects.toMatchObject({ code: "invalid_extraction" });
    }
  });

  it("sanitizes provider failures and never retries paid requests automatically", async () => {
    const transport = vi.fn(async () => new Response("test-secret upstream stacktrace", { status: 401 }));
    await expect(createPhotoExtractor({ apiKey: "test-secret", fetchImpl: transport })(input))
      .rejects.toMatchObject({ code: "provider_unavailable" });
    expect(transport).toHaveBeenCalledTimes(1);
    const error = await reader(new Response("test-secret", { status: 500 }))(input).catch(error => error);
    expect(String(error)).not.toContain("test-secret");
  });

  it("sanitizes network exceptions", async () => {
    const transport = vi.fn(async () => { throw new Error("test-secret DNS internals"); });
    const error = await createPhotoExtractor({ apiKey: "test-secret", fetchImpl: transport })(input)
      .catch(error => error);
    expect(error.code).toBe("provider_unavailable");
    expect(String(error)).not.toContain("test-secret");
  });

  it("rejects malformed credentials before making a request", () => {
    expect(() => createPhotoExtractor({ apiKey: "bad key" })).toThrow();
    expect(() => createPhotoExtractor({ apiKey: "" })).toThrow();
  });

  it("does not call the provider if the user already cancelled", async () => {
    const controller = new AbortController();
    controller.abort();
    const transport = vi.fn(async () => completion());
    await expect(createPhotoExtractor({ apiKey: "test-secret", fetchImpl: transport })({ ...input, signal: controller.signal }))
      .rejects.toMatchObject({ name: "AbortError" });
    expect(transport).not.toHaveBeenCalled();
  });

  it("cancels an in-flight provider request", async () => {
    const controller = new AbortController();
    const transport: typeof fetch = async (_url, options) => new Promise((_resolve, reject) => {
      options?.signal?.addEventListener("abort", () => reject(options.signal?.reason), { once: true });
    });
    const result = createPhotoExtractor({ apiKey: "test-secret", fetchImpl: transport })({ ...input, signal: controller.signal });
    controller.abort();
    await expect(result).rejects.toMatchObject({ name: "AbortError" });
  });

  it("times out a stalled provider request", async () => {
    vi.useFakeTimers();
    const transport: typeof fetch = async (_url, options) => new Promise((_resolve, reject) => {
      options?.signal?.addEventListener("abort", () => reject(options.signal?.reason), { once: true });
    });
    const result = createPhotoExtractor({ apiKey: "test-secret", fetchImpl: transport })(input);
    const expectation = expect(result).rejects.toMatchObject({ code: "provider_timeout" });
    await vi.advanceTimersByTimeAsync(PROVIDER_TIMEOUT_MS);
    await expectation;
  });

  it("bounds provider response size", async () => {
    await expect(reader(new Response("x".repeat(65 * 1024)))(input))
      .rejects.toMatchObject({ code: "invalid_extraction" });
  });

  it("keeps the timeout active while waiting for the response body", async () => {
    vi.useFakeTimers();
    const body = new ReadableStream<Uint8Array>();
    const result = reader(new Response(body))(input);
    const expectation = expect(result).rejects.toMatchObject({ code: "provider_timeout" });
    await vi.advanceTimersByTimeAsync(PROVIDER_TIMEOUT_MS);
    await expectation;
  });
});
