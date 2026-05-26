import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';

// The Azure Resource Manager endpoint does not expose CORS for arbitrary
// origins, so in dev we proxy every `/api/arm/*` call straight through to
// `https://management.azure.com/*` while preserving the user's bearer token.
// In production the same path is served by the Static Web Apps Function in
// `web/api/arm/index.ts`. The frontend code only ever calls `/api/arm/...`.
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
  // We use top-level `await pca.initialize()` in `auth/msalConfig.ts`. That
  // syntax is only valid on targets that support ES2022 modules.
  build: {
    target: 'es2022',
  },
  esbuild: {
    target: 'es2022',
  },
  optimizeDeps: {
    esbuildOptions: { target: 'es2022' },
  },
  server: {
    port: 5173,
    proxy: {
      '/api/arm': {
        target: 'https://management.azure.com',
        changeOrigin: true,
        secure: true,
        rewrite: (p) => p.replace(/^\/api\/arm/, ''),
      },
    },
  },
});
