import { randomUUID } from "node:crypto";

const MAX_BODY = 256 * 1024;
class InvalidRequest extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export async function jsonEndpoint<T>(
  request: Request,
  valid: (body: unknown) => body is T,
  run: (body: T) => Promise<unknown>,
): Promise<Response> {
  const started = performance.now();
  const id = randomUUID();
  let status = 200;
  let result: unknown;
  try {
    if (request.method !== "POST")
      throw new InvalidRequest(405, "Method not allowed");
    if (Number(request.headers.get("content-length")) > MAX_BODY) {
      throw new InvalidRequest(413, "Request too large");
    }
    const reader = request.body?.getReader();
    if (!reader) throw new InvalidRequest(400, "JSON body required");
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_BODY) {
        await reader.cancel();
        throw new InvalidRequest(413, "Request too large");
      }
      chunks.push(value);
    }
    let body: unknown;
    try {
      body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    } catch {
      throw new InvalidRequest(400, "Invalid JSON body");
    }
    if (!valid(body)) throw new InvalidRequest(400, "Invalid coaching context");
    result = await run(body);
  } catch (error) {
    status = error instanceof InvalidRequest ? error.status : 500;
    result = {
      error:
        error instanceof InvalidRequest
          ? error.message
          : "Coaching request failed",
    };
  }
  const ms = Math.round(performance.now() - started);
  console.info(
    JSON.stringify({
      event: "api-request",
      id,
      path: new URL(request.url).pathname,
      status,
      ms,
    }),
  );
  return Response.json(result, {
    status,
    headers: {
      "cache-control": "no-store",
      "x-request-id": id,
      "server-timing": `total;dur=${ms}`,
      ...(status === 405 ? { allow: "POST" } : {}),
    },
  });
}
