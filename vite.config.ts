import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig(() => {
  const allowedHost = process.env.__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS?.trim();
  // URLSession normalizes the hostname to lowercase. Vite's explicit host
  // comparisons are case-sensitive, so allow both spellings of this one host.
  return {
    plugins: [react()],
    server: { allowedHosts: allowedHost ? [allowedHost, allowedHost.toLowerCase()] : [] },
  };
});
