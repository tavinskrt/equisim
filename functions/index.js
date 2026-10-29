/**
 * Proxy de custódia da credencial da brapi.
 *
 * Motivo de existir: o Vite embarca no bundle toda variável `VITE_*`, e um
 * token posto ali fica legível por qualquer um que abra o JavaScript do site.
 * A única proteção real é o segredo nunca sair do servidor. De quebra, isto
 * resolve o CORS no navegador sem entregar o header `Authorization` a um proxy
 * público de terceiro.
 *
 * O cliente aponta para cá por `VITE_BRAPI_PROXY_URL` e não carrega
 * credencial alguma.
 *
 * Configuração do segredo (não vai para o repositório):
 *   firebase functions:secrets:set BRAPI_TOKEN
 *
 * Publicação:
 *   firebase deploy --only functions
 */

const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const { resolveTarget } = require("./allowlist");

const BRAPI_TOKEN = defineSecret("BRAPI_TOKEN");

/** Origens autorizadas. Ajuste para o domínio de produção antes de publicar. */
const ALLOWED_ORIGINS = [
  // Emulador do Hosting, `npm run dev` e `npm run preview`, nesta ordem.
  "http://localhost:5000",
  "http://localhost:5173",
  "http://localhost:4173",
  "https://equisim-d7128.web.app",
  "https://equisim-d7128.firebaseapp.com",
];

function applyCors(req, res) {
  const origin = req.get("origin");
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    res.set("Access-Control-Allow-Origin", origin);
    res.set("Vary", "Origin");
  }
  res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  res.set("Access-Control-Max-Age", "3600");
}

exports.brapi = onRequest(
  {
    region: "southamerica-east1",
    secrets: [BRAPI_TOKEN],
    cors: false, // tratado manualmente, com lista de origens
    memory: "256MiB",
    timeoutSeconds: 60,
    // A função é pública: CORS só restringe navegador, e um script chama a
    // URL de qualquer lugar. O teto de instâncias limita quanto uma rajada
    // assim consegue gastar da conta e da cota da brapi ao mesmo tempo.
    maxInstances: 10,
  },
  async (req, res) => {
    applyCors(req, res);

    if (req.method === "OPTIONS") {
      return res.status(204).send("");
    }
    if (req.method !== "GET") {
      return res.status(405).json({ error: "Somente GET é aceito." });
    }

    // `req.path` chega sem o nome da função quando servido via rewrite.
    const path = req.path.replace(/^\/brapi/, "") || "/";

    const target = resolveTarget(path, new URLSearchParams(req.query).toString());
    if (target === null) {
      return res.status(403).json({ error: `Caminho não permitido: ${path}` });
    }

    try {
      const upstream = await fetch(target, {
        headers: {
          Authorization: `Bearer ${BRAPI_TOKEN.value()}`,
          "Content-Type": "application/json",
        },
      });

      const body = await upstream.text();

      // Cotação de pregão encerrado é imutável: vale cachear na borda.
      if (upstream.ok && path.includes("/historical")) {
        res.set("Cache-Control", "public, max-age=3600, s-maxage=21600");
      }

      res.status(upstream.status);
      res.set("Content-Type", "application/json");
      res.set("X-Content-Type-Options", "nosniff");
      return res.send(body);
    } catch (error) {
      // Nunca ecoar a mensagem crua: ela pode conter a URL com credencial.
      console.error("Falha ao repassar requisição:", error.message);
      return res.status(502).json({ error: "Falha ao contatar a fonte de dados." });
    }
  }
);
