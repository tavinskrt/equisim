/**
 * Que caminhos o proxy repassa à brapi, e para onde exatamente.
 *
 * Fica fora de `index.js` para ser testável sem o `firebase-functions`
 * instalado: este módulo não importa nada.
 */

const BRAPI_ORIGIN = "https://brapi.dev";
const BRAPI_PREFIX = "/api";

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

/**
 * O endereço da brapi para um caminho pedido ao proxy, ou `null` quando o
 * caminho não é permitido.
 *
 * A conferência é feita sobre o caminho **depois** de normalizado pelo mesmo
 * analisador de URL que o `fetch` usa. Conferir o texto cru deixava passar
 * `/v2/stocks/quote/../dividends` e `/v2/stocks/quote/%2e%2e/dividends`: o
 * prefixo batia, e o `fetch` resolvia o `..` antes de sair, entregando com o
 * token do servidor qualquer endpoint da assinatura. A comparação é por
 * segmento inteiro, para que `/v2/tickersX` não passe por `/v2/tickers`, e
 * admite no máximo um segmento a mais, de letras, dígitos, `_`, `-` e `,`.
 *
 * Escape percentual e barra invertida são recusados antes de tudo: o cliente
 * nunca os manda, e `%2F` sobrevive à normalização daqui para ser decodificado
 * do outro lado, onde não há como saber o que vira.
 *
 * @param path Caminho pedido, já sem o prefixo `/brapi` do rewrite.
 * @param query Parâmetros de consulta, repassados como vieram.
 */
function resolveTarget(path, query) {
  if (typeof path !== "string" || /[%\\]/.test(path)) return null;
  let url;
  try {
    url = new URL(`${BRAPI_ORIGIN}${BRAPI_PREFIX}${path}`);
  } catch {
    return null;
  }
  if (url.origin !== BRAPI_ORIGIN || !url.pathname.startsWith(`${BRAPI_PREFIX}/`)) return null;

  const upstreamPath = url.pathname.slice(BRAPI_PREFIX.length);
  const allowed = ALLOWED_PATHS.some(
    (prefix) =>
      upstreamPath === prefix ||
      (upstreamPath.startsWith(`${prefix}/`) && /^\/[A-Za-z0-9_,-]+$/.test(upstreamPath.slice(prefix.length))),
  );
  if (!allowed) return null;

  url.search = query;
  return url.toString();
}

module.exports = { ALLOWED_PATHS, BRAPI_ORIGIN, resolveTarget };
