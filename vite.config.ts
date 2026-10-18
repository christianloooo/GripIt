import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";

/**
 * Serves the coaching proxy during `npm run dev` so the same `/api/coach`
 * path works locally and in production. The key is read from the dev server's
 * own environment and never reaches the browser.
 */
function coachDevEndpointPlugin(): Plugin {
  return {
    name: "gripit-coach-dev-endpoint",
    apply: "serve",
    configureServer(server) {
      server.middlewares.use("/api/coach", (req, res, next) => {
        if (req.method !== "POST") return next();
        const chunks: Buffer[] = [];
        req.on("data", (chunk: Buffer) => chunks.push(chunk));
        req.on("end", async () => {
          res.setHeader("content-type", "application/json");
          try {
            const { rewriteCoaching } = await server.ssrLoadModule(
              "/api/coach.ts",
            );
            const assessment = JSON.parse(Buffer.concat(chunks).toString());
            const result = await rewriteCoaching(
              assessment,
              process.env.ANTHROPIC_API_KEY,
            );
            res.statusCode = 200;
            res.end(JSON.stringify(result));
          } catch (error) {
            res.statusCode = 400;
            res.end(
              JSON.stringify({
                error: error instanceof Error ? error.message : "Bad request",
              }),
            );
          }
        });
      });
    },
  };
}

export default defineConfig({ plugins: [react(), coachDevEndpointPlugin()] });
