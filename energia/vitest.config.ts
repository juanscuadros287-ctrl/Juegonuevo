import { defineConfig } from 'vitest/config';
import yaml from '@modyfi/vite-plugin-yaml';

export default defineConfig({
  plugins: [yaml()],
  test: { include: ['packages/**/test/**/*.test.ts'] },
});
