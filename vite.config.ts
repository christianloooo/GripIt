import { defineConfig, loadEnv, type Plugin } from "vite";
import react from "@vitejs/plugin-react";

function coachingAPI(env: Record<string, string>): Plugin {
  const apiKey = env.ANTHROPIC_API_KEY || process.env.ANTHROPIC_API_KEY;
  if (env.COACH_MODEL) process.env.COACH_MODEL = env.COACH_MODEL;
  return {
    name: "gripit-native-coaching-api",
    apply: "serve",
    configureServer(server) {
      server.middlewares.use(async (req, res, next) => {
        const path = req.url?.split("?")[0];
        if (!["/api/coach", "/api/ask", "/api/health"].includes(path ?? ""))
          return next();
        // Bound before buffering as well as inside the shared exported handler.
        const chunks: Buffer[] = [];
        let size = 0;
        try {
          for await (const chunk of req) {
            size += chunk.length;
            if (size > 256 * 1024) {
              res.writeHead(413, {
                "content-type": "application/json",
                "cache-control": "no-store",
              });
              res.end(JSON.stringify({ error: "Request too large" }));
              return;
            }
            chunks.push(chunk);
          }
          const name = path!.slice("/api/".length);
          const module = await server.ssrLoadModule(`/api/${name}.ts`);
          const method = req.method ?? "GET";
          const request = new Request(`http://localhost${path}`, {
            method,
            body:
              method === "GET" || method === "HEAD"
                ? undefined
                : Buffer.concat(chunks),
          });
          const response: Response =
            name === "coach"
              ? await module.handleCoachRequest(request, apiKey)
              : name === "ask"
                ? await module.handleAskRequest(request, apiKey)
                : await module.default(request);
          response.headers.forEach((value, key) => res.setHeader(key, value));
          res.statusCode = response.status;
          res.end(await response.text());
        } catch {
          res.writeHead(500, { "content-type": "application/json" });
          res.end(JSON.stringify({ error: "Coaching service unavailable" }));
        }
      });
    },
  };
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(
    mode,
    process.env.GRIPIT_DEV_ENV_DIR || process.cwd(),
    "",
  );
  const allowedHost = process.env.__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS?.trim();
  // URLSession normalizes the hostname to lowercase. Vite's explicit host
  // comparisons are case-sensitive, so allow both spellings of this one host.
  return {
    plugins: [react(), coachingAPI(env)],
    server: { allowedHosts: allowedHost ? [allowedHost, allowedHost.toLowerCase()] : [] },
  };
});
