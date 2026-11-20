import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
export default defineConfig({
  plugins: [react()],
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    proxy: {
      "/v1": process.env.ZOOP_API_URL ?? "http://127.0.0.1:18471",
      "/health": process.env.ZOOP_API_URL ?? "http://127.0.0.1:18471",
    },
  },
  build: {
    sourcemap: false,
    rollupOptions: { output: { manualChunks: { charts: ["recharts"] } } },
  },
});
