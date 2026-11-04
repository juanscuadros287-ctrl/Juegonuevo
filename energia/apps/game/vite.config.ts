import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import yaml from '@modyfi/vite-plugin-yaml';

// Los assets generados (grilla de recursos y países) se sirven desde packages/data/generated.
export default defineConfig({
  plugins: [react(), yaml()],
  publicDir: '../../packages/data/generated',
  base: './',
  clearScreen: false,
  server: { port: 5173, strictPort: true },
  worker: { format: 'es', plugins: () => [yaml()] },
  build: { target: 'safari16', chunkSizeWarningLimit: 2000 },
});
