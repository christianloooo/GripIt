export type CacheStatus = "hit" | "miss" | "shared";

/** Ephemeral, process-local cache. Failed/rejected results are never retained. */
export class ResponseCache<T> {
  private values = new Map<string, { value: T; expires: number }>();
  private pending = new Map<string, Promise<T>>();
  constructor(
    private limit = 256,
    private ttlMs = 600_000,
    private now = Date.now,
    private maxPending = 32,
  ) {}

  async get(
    key: string,
    work: () => Promise<T>,
    cacheable: (value: T) => boolean,
  ): Promise<{ value: T; status: CacheStatus }> {
    const cached = this.values.get(key);
    if (cached && cached.expires > this.now()) {
      this.values.delete(key);
      this.values.set(key, cached);
      return { value: cached.value, status: "hit" };
    }
    this.values.delete(key);
    const pending = this.pending.get(key);
    if (pending) return { value: await pending, status: "shared" };
    if (this.pending.size >= this.maxPending) throw new Error("busy");
    // Start synchronously, then register before yielding to another caller.
    const task = work();
    this.pending.set(key, task);
    try {
      const value = await task;
      if (cacheable(value)) {
        this.values.set(key, { value, expires: this.now() + this.ttlMs });
        while (this.values.size > this.limit) {
          this.values.delete(this.values.keys().next().value!);
        }
      }
      return { value, status: "miss" };
    } finally {
      this.pending.delete(key);
    }
  }
}
