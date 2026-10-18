import { describe, expect, it } from "vitest";
import { ResponseCache } from "./_cache";

describe("bounded response cache", () => {
  it("shares concurrent work and caches only successful values", async () => {
    const cache = new ResponseCache<string>(2, 1000);
    let calls = 0;
    const work = async () => {
      calls++;
      await Promise.resolve();
      return "ok";
    };
    const results = await Promise.all([
      cache.get("same", work, () => true),
      cache.get("same", work, () => true),
    ]);
    expect(calls).toBe(1);
    expect(results.map((r) => r.status)).toEqual(["miss", "shared"]);
    expect((await cache.get("same", work, () => true)).status).toBe("hit");
    await cache.get(
      "failed",
      async () => "bad",
      () => false,
    );
    expect((await cache.get("failed", work, () => true)).value).toBe("ok");
    expect(calls).toBe(2);
  });

  it("expires and evicts old values without confusing changed inputs", async () => {
    let now = 0;
    const cache = new ResponseCache<string>(2, 10, () => now);
    const get = (key: string) =>
      cache.get(
        key,
        async () => key,
        () => true,
      );
    await get("72");
    await get("84");
    await get("94");
    expect((await get("72")).status).toBe("miss");
    expect((await get("94")).status).toBe("hit");
    now = 11;
    expect((await get("94")).status).toBe("miss");
  });

  it("releases failed work so a later request can recover", async () => {
    const cache = new ResponseCache<string>(2, 1000);
    await expect(
      cache.get(
        "key",
        async () => {
          throw Error("offline");
        },
        () => true,
      ),
    ).rejects.toThrow("offline");
    expect(
      (
        await cache.get(
          "key",
          async () => "recovered",
          () => true,
        )
      ).value,
    ).toBe("recovered");
  });

  it("bounds distinct in-flight requests but still shares matching work", async () => {
    const cache = new ResponseCache<string>(2, 1000, Date.now, 1);
    let complete!: (value: string) => void;
    const first = cache.get(
      "a",
      () =>
        new Promise((resolve) => {
          complete = resolve;
        }),
      () => true,
    );
    const shared = cache.get(
      "a",
      async () => "wrong",
      () => true,
    );
    await expect(
      cache.get(
        "b",
        async () => "busy",
        () => true,
      ),
    ).rejects.toThrow("busy");
    complete("done");
    expect((await first).value).toBe("done");
    expect((await shared).status).toBe("shared");
  });
});
