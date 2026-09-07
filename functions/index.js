/**
 * Proxy de custódia da credencial da brapi.
 *
 * Motivo de existir: `--dart-define` tira o token do controle de versão e do
 * bundle web, mas não o protege de quem tem o binário — a constante é
 * extraível com `strings`. A única proteção real é o segredo nunca sair do
 * servidor. De quebra, isto resolve o CORS no alvo web sem entregar o header
 * `Authorization` a um proxy público de terceiro, como acontecia antes.
 *
 * O cliente aponta para cá via `--dart-define=BRAPI_PROXY_URL=...` e não
 * carrega credencial alguma.
 *
 * Configuração do segredo (não vai para o repositório):
 *   firebase functions:secrets:set BRAPI_TOKEN
 *
 * Publicação:
 *   firebase deploy --only functions
 */

const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const BRAPI_TOKEN = defineSecret("BRAPI_TOKEN");

const BRAPI_BASE = "https://brapi.dev/api";

/**
 * Só estes caminhos são repassados.
 *
 * `/v2/stocks/dividends` saiu em 07/09/2026. A decisão 23 removeu provento do
 * domínio e a 25 manteve a remoção, mas o endpoint seguia liberado aqui: uma
 * superfície aberta para dado que o projeto decidiu não modelar é convite a
 * reintroduzi-lo por acidente, e consome cota da fonte sem contrapartida.
 * Reabri-lo exige decisão nova que substitua a 23.
 */
const ALLOWED_PATHS = [
  "/v2/stocks/historical",
  "/v2/stocks/statistics",
  "/v2/stocks/financial-data",
  "/v2/stocks/income-statement",
  "/v2/stocks/balance-sheet",
  "/v2/stocks/cash-flow",
  "/v2/stocks/profile",
  "/v2/stocks/quote",
  "/v2/tickers",
  "/v2/tickers/resolve",
];

/** Origens autorizadas. Ajuste para o domínio de produção antes de publicar. */
const ALLOWED_ORIGINS = [
  "http://localhost:5000",
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

    if (!ALLOWED_PATHS.some((allowed) => path.startsWith(allowed))) {
      return res.status(403).json({ error: `Caminho não permitido: ${path}` });
    }

    const query = new URLSearchParams(req.query).toString();
    const target = `${BRAPI_BASE}${path}${query ? `?${query}` : ""}`;

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
      return res.send(body);
    } catch (error) {
      // Nunca ecoar a mensagem crua: ela pode conter a URL com credencial.
      console.error("Falha ao repassar requisição:", error.message);
      return res.status(502).json({ error: "Falha ao contatar a fonte de dados." });
    }
  }
);
