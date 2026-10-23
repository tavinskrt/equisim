import { fileURLToPath, URL } from 'node:url';

import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// Configuração do Vite: aplicativo de página única, com o painel de auditoria
// em /logs servido pela mesma página (o Firebase Hosting reescreve toda rota
// para index.html, ver firebase.json).
export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  worker: {
    format: 'es',
  },
  build: {
    target: 'es2023',
    // Os bundles com hash vão para /static: /assets é dos pacotes de dados
    // versionados (public/assets), que não têm hash e pedem outro cache.
    assetsDir: 'static',
    sourcemap: true,
    chunkSizeWarningLimit: 1500,
  },
});
