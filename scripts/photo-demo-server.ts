// Local development only. Claude's backend owns authenticated, durable usage.
import { createServer, type ServerResponse } from "node:http";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createPhotoExtractor } from "../services/photo-reading/extract.ts";
import { PhotoExtractionError } from "../services/photo-reading/errors.ts";
import type { PhotoExtraction, PhotoExtractor } from "../services/photo-reading/types.ts";

const MAX_IMAGE_BYTES = 4 * 1024 * 1024;
const CACHE_TTL_MS = 10 * 60 * 1000;
const MAX_CACHE_ENTRIES = 32;
type Entry = { digest: string; expiresAt: number; result?: PhotoExtraction };

function reply(response: ServerResponse, status: number, body: unknown) {
  response.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store" });
  response.end(JSON.stringify(body));
}
function fail(response: ServerResponse, status: number, code: string, message: string) {
  reply(response, status, { error: { code, message } });
}

export function createPhotoDemoServer(extract: PhotoExtractor) {
  const cache = new Map<string, Entry>();
  const server = createServer(async (request, response) => {
    // Reject browser-origin calls: this helper has no account auth or CORS.
    if (request.headers.origin) {
      fail(response, 403, "invalid_request", "Use the native app with this local development service.");
      request.resume();
      return;
    }
    if (request.url === "/health" && request.method === "GET") {
      reply(response, 200, { ok: true, mode: "local-photo-development" });
      return;
    }
    if (request.url !== "/api/photos/read" || request.method !== "POST") {
      fail(response, 404, "not_found", "Route not found.");
      request.resume();
      return;
    }
    const contentType = request.headers["content-type"];
    if (contentType !== "image/png" && contentType !== "image/jpeg") {
      fail(response, 415, "unsupported_media_type", "Choose a JPEG or PNG photo.");
      request.resume();
      return;
    }
    const key = request.headers["idempotency-key"];
    if (typeof key !== "string" || !/^[a-zA-Z0-9_-]{1,128}$/.test(key)) {
      fail(response, 400, "invalid_request", "A valid photo request ID is required.");
      request.resume();
      return;
    }
    const controller = new AbortController();
    request.once("aborted", () => controller.abort());
    response.once("close", () => { if (!response.writableFinished) controller.abort(); });
    let ownedEntry: Entry | undefined;
    try {
      const chunks: Buffer[] = [];
      let length = 0;
      for await (const chunk of request) {
        length += chunk.length;
        if (length > MAX_IMAGE_BYTES) {
          fail(response, 413, "payload_too_large", "Choose a photo smaller than 4 MiB.");
          return;
        }
        chunks.push(chunk);
      }
      const bytes = Buffer.concat(chunks);
      const valid = contentType === "image/png"
        ? bytes.length > 8 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
        : bytes.length > 4 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
      if (!valid) {
        fail(response, 400, "invalid_request", "This file does not match its image format.");
        return;
      }
      const digest = createHash("sha256").update(contentType).update(bytes).digest("hex");
      for (const [id, entry] of cache) {
        if (entry.result && entry.expiresAt <= Date.now()) cache.delete(id);
      }
      const existing = cache.get(key);
      if (existing) {
        if (existing.digest !== digest) fail(response, 409, "conflict", "Use a new request ID for a different photo.");
        else if (!existing.result) fail(response, 409, "operation_in_progress", "This photo is still being read.");
        else reply(response, 200, { ...existing.result, requestId: key });
        return;
      }
      if (cache.size >= MAX_CACHE_ENTRIES) {
        const completed = [...cache].find(([, entry]) => entry.result);
        if (completed) cache.delete(completed[0]);
        else {
          fail(response, 503, "provider_unavailable", "Photo reading is busy. Try again shortly.");
          return;
        }
      }
      ownedEntry = { digest, expiresAt: Date.now() + CACHE_TTL_MS };
      cache.set(key, ownedEntry);
      const result = await extract({ bytes, contentType, signal: controller.signal });
      ownedEntry.result = result;
      ownedEntry.expiresAt = Date.now() + CACHE_TTL_MS;
      if (!response.destroyed) reply(response, 200, { ...result, requestId: key });
    } catch (error) {
      if (ownedEntry && cache.get(key) === ownedEntry) cache.delete(key);
      if (response.destroyed || controller.signal.aborted) return;
      if (error instanceof PhotoExtractionError) {
        const status = error.code === "provider_timeout" ? 504 : error.code === "invalid_extraction" ? 502 : 503;
        fail(response, status, error.code, error.message);
      } else fail(response, 500, "internal_error", "Could not read this photo. Try again or enter it yourself.");
    }
  });
  server.requestTimeout = 45_000;
  server.headersTimeout = 5_000;
  return server;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (existsSync(".env")) process.loadEnvFile(".env");
    // KEY2 is the verified local test credential; new deployments use the canonical name.
    const apiKey = process.env.PERCEPTRON_API_KEY2 ?? process.env.PERCEPTRON_API_KEY ?? "";
    const host = process.env.GRIPIT_PHOTO_HOST ?? "127.0.0.1";
    const port = Number(process.env.GRIPIT_PHOTO_PORT ?? "5173");
    if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("Invalid port");
    const server = createPhotoDemoServer(createPhotoExtractor({ apiKey }));
    server.on("error", () => { process.stderr.write("Photo development server could not start. Check the port.\n"); process.exitCode = 1; });
    server.listen(port, host, () => process.stdout.write(`Local photo development service listening on ${host}:${port}.\n`));
    for (const signal of ["SIGINT", "SIGTERM"] as const) process.on(signal, () => {
      server.close();
      server.closeAllConnections();
    });
  } catch {
    process.stderr.write("Photo development server is not configured. Check the server key and port in .env.\n");
    process.exitCode = 1;
  }
}
