import { fileURLToPath, URL } from 'node:url';

import { defineConfig } from 'vitest/config';

// O núcleo grava datas no fuso local fixado em UTC (ver
// src/core/lang/date-time.ts); fixar o fuso do processo garante que a
// serialização dos testes seja a mesma em qualquer máquina.
process.env.TZ = 'UTC';

export default defineConfig({
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  test: {
    include: ['test/**/*.test.ts', 'test/**/*.test.tsx'],
    environment: 'node',
    testTimeout: 120_000,
    hookTimeout: 120_000,
  },
});
