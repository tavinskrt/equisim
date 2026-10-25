#!/usr/bin/env -S npx tsx
/**
 * Capturas de tela para a lente `tela` do conselheiro.
 *
 * Sobe o aplicativo com o servidor do Vite, abre-o num Chromium sem janela e
 * percorre as sete telas de operação em cada largura e tema, gravando
 * `docs/telas/<tema>/<nn>-<tela>@<largura>.png`. NAO e teste de regressao
 * visual: nada aqui reprova, e as imagens nao sao versionadas.
 *
 * **O mercado e sintetico.** A brapi e o Banco Central sao interceptados e
 * respondidos daqui: as demonstracoes saem dos fixtures de `test/fixtures/`, as
 * cotacoes de um passeio aleatorio com semente por ticker, e a data do
 * navegador fica fixa em [CAPTURE_DATE]. Assim duas execucoes dao as mesmas
 * imagens, sem rede e sem credencial -- e os numeros da tela nao sao os de
 * mercado, o que a lente sabe (ver `scripts/qa/advisor/rules.ts`).
 *
 * **O aplicativo roda em modo local** (`VITE_EQUISIM_LOCAL=true`): carteiras e
 * valuations ficam no IndexedDB do contexto, e nada vai ao Firebase.
 *
 * Uso:
 *   npm run ui:capturar
 *   npm run ui:capturar -- --larguras 390 --temas escuro
 *   npm run ui:capturar -- --navegador "C:\Program Files\Google\Chrome\Application\chrome.exe"
 *
 * O navegador: o de `--navegador`, ou o Chromium que o `playwright-core`
 * conhece (`npx playwright-core install chromium`), ou o Chrome instalado.
 */
import { mkdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { type Browser, type BrowserContext, chromium, type Page } from 'playwright-core';
import { createServer } from 'vite';

const ROOT = process.cwd();
const OUT = join(ROOT, 'docs', 'telas');

/** Dia do relógio do navegador: o fim das séries sintéticas. */
const CAPTURE_DATE = new Date(Date.UTC(2026, 9, 23, 15));

const WIDTHS = [320, 390, 1024] as const;
const THEMES = { claro: 'light', escuro: 'dark' } as const;
type ThemeName = keyof typeof THEMES;

/** Altura da janela antes da foto: a de um celular ou de um notebook comuns. */
const heightFor = (width: number): number => (width < 600 ? 844 : 900);

/** Teto da janela esticada: o Chromium não rasteriza muito além de 16 mil px. */
const MAX_HEIGHT = 16_000;

/**
 * A altura que a página pede: a do documento ou a do diálogo aberto, o que for
 * maior. Vai como texto porque roda no navegador, e o `tsconfig.node.json` não
 * carrega os tipos do DOM.
 */
const MEASURE_HEIGHT = `(() => {
  const doc = (document.scrollingElement ?? document.documentElement).scrollHeight;
  let dialog = 0;
  for (const d of document.querySelectorAll('[role=dialog]')) dialog = Math.max(dialog, d.scrollHeight);
  return Math.max(doc, Math.ceil(dialog / 0.85));
})()`;

interface Cli {
  widths: number[];
  themes: ThemeName[];
  browserPath: string | null;
  port: number;
}

function parseArgs(argv: readonly string[]): Cli {
  const cli: Cli = { widths: [...WIDTHS], themes: ['claro', 'escuro'], browserPath: null, port: 5179 };
  for (let i = 0; i < argv.length; i++) {
    const value = argv[i + 1];
    switch (argv[i]) {
      case '--larguras':
        cli.widths = (value ?? '').split(',').map((v) => Number.parseInt(v, 10));
        if (cli.widths.some((w) => !Number.isFinite(w) || w < 240)) throw new Error(`Larguras inválidas: ${value}`);
        i++;
        break;
      case '--temas':
        cli.themes = (value ?? '').split(',') as ThemeName[];
        if (cli.themes.some((t) => !(t in THEMES))) throw new Error(`Temas inválidos: ${value}. Use claro, escuro ou os dois.`);
        i++;
        break;
      case '--navegador':
        cli.browserPath = value ?? null;
        i++;
        break;
      case '--porta':
        cli.port = Number.parseInt(value ?? '', 10);
        i++;
        break;
      default:
        throw new Error(`Argumento desconhecido: ${argv[i]}`);
    }
  }
  return cli;
}

// ---------------------------------------------------------------------------
// Mercado sintético
// ---------------------------------------------------------------------------

const FIXTURES = join(ROOT, 'test', 'fixtures');
const fixture = (name: string): string => readFileSync(join(FIXTURES, name), 'utf8').replace(/^\uFEFF/, '');

const statements = {
  current: fixture('brapi_statistics_current_petr4.json'),
  history: fixture('brapi_statistics_history_petr4.json'),
  income: fixture('brapi_income_statement_history_petr4.json'),
  balance: fixture('brapi_balance_sheet_history_petr4.json'),
  cash: fixture('brapi_cash_flow_history_petr4.json'),
  profile: fixture('brapi_profile_petr4.json'),
};

/** O fixture da PETR4 com o ticker pedido no lugar. */
const forSymbol = (raw: string, symbol: string): string => raw.replaceAll('"PETR4"', JSON.stringify(symbol));

/** Os tickers que a busca encontra. */
const UNIVERSE = ['PETR4', 'VALE3', 'ITUB4', 'BBAS3', 'WEGE3', 'ABEV3', 'TAEE11'];

function hash(s: string): number {
  let h = 2166136261;
  for (const c of s) h = Math.imul(h ^ c.charCodeAt(0), 16777619);
  return h >>> 0;
}

/** Xorshift de 32 bits: basta para um passeio aleatório reproduzível. */
function rng(seed: number): () => number {
  let x = seed || 1;
  return () => {
    x ^= x << 13;
    x ^= x >>> 17;
    x ^= x << 5;
    return (x >>> 0) / 4294967296;
  };
}

function gauss(r: () => number): number {
  const u = Math.max(1e-9, r());
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * r());
}

function businessDays(from: Date, to: Date): Date[] {
  const out: Date[] = [];
  for (let d = new Date(from); d <= to; d = new Date(d.getTime() + 864e5)) {
    const w = d.getUTCDay();
    if (w !== 0 && w !== 6) out.push(new Date(d));
  }
  return out;
}

/** Dez anos de pregões até [CAPTURE_DATE], do mais recente ao mais antigo, como a brapi. */
function series(symbol: string): Record<string, number>[] {
  const r = rng(hash(symbol));
  const start = new Date(Date.UTC(CAPTURE_DATE.getUTCFullYear() - 10, CAPTURE_DATE.getUTCMonth(), CAPTURE_DATE.getUTCDate() + 1));
  let p = symbol === '^BVSP' ? 62000 : 8 + (hash(symbol) % 30);
  const drift = symbol === '^BVSP' ? 0.00035 : 0.0002 + (hash(symbol) % 7) * 0.0001;
  const points = businessDays(start, CAPTURE_DATE).map((d) => {
    p *= Math.exp(drift + 0.017 * gauss(r));
    const c = Math.round(p * 100) / 100;
    return { date: Math.floor(d.getTime() / 1000) + 13 * 3600, open: c, high: c, low: c, close: c, volume: 1e7, adjustedClose: c };
  });
  return points.reverse();
}

const pad = (n: number): string => String(n).padStart(2, '0');
const brDate = (d: Date): string => `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}`;
const parseBrDate = (s: string): Date => {
  const [d, m, y] = s.split('/').map(Number);
  return new Date(Date.UTC(y!, m! - 1, d));
};

/** Séries do SGS: CDI diário constante, IPCA mensal constante, índices mensais crescentes. */
function bcb(id: number, from: Date, to: Date): { data: string; valor: string }[] {
  if (id === 12) return businessDays(from, to).map((d) => ({ data: brDate(d), valor: '0.040168' }));
  const out: { data: string; valor: string }[] = [];
  let level = 130;
  for (let d = new Date(Date.UTC(from.getUTCFullYear(), from.getUTCMonth(), 1)); d <= to; d = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1))) {
    level *= 1.002;
    out.push({ data: brDate(d), valor: id === 433 ? '0.40' : level.toFixed(2) });
  }
  return out;
}

/**
 * Responde a brapi e o Banco Central daqui, e deixa passar só o servidor local
 * e as fontes do Google; o resto é abortado. Sem rede, a fonte cai na da
 * plataforma, que a lente conhece.
 */
async function installMarket(context: BrowserContext): Promise<void> {
  await context.route(/^https?:\/\/(?!localhost|127\.0\.0\.1)/, async (route) => {
    const url = new URL(route.request().url());
    const json = (body: unknown) =>
      route.fulfill({ status: 200, contentType: 'application/json', body: typeof body === 'string' ? body : JSON.stringify(body) });
    if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') return route.continue();
    if (url.hostname === 'brapi.dev') {
      const path = url.pathname;
      const symbols = url.searchParams.get('symbols') ?? '';
      if (path.endsWith('/v2/tickers')) return json({ results: UNIVERSE.map((symbol) => ({ symbol })) });
      if (path.endsWith('/v2/stocks/historical')) {
        return json({
          results: symbols.split(',').map((s) => ({
            requestedSymbol: s,
            symbol: s,
            data: { usedInterval: '1d', usedRange: '10y', historicalDataPrice: series(s) },
          })),
        });
      }
      if (path.endsWith('/v2/stocks/statistics')) {
        return json(forSymbol(url.searchParams.get('mode') === 'current' ? statements.current : statements.history, symbols));
      }
      if (path.endsWith('/v2/stocks/income-statement')) return json(forSymbol(statements.income, symbols));
      if (path.endsWith('/v2/stocks/balance-sheet')) return json(forSymbol(statements.balance, symbols));
      if (path.endsWith('/v2/stocks/cash-flow')) return json(forSymbol(statements.cash, symbols));
      if (path.endsWith('/v2/stocks/profile')) return json(forSymbol(statements.profile, symbols));
      return route.fulfill({ status: 404, body: '{}' });
    }
    if (url.hostname === 'api.bcb.gov.br') {
      const id = Number(/sgs\.(\d+)/.exec(url.pathname)?.[1]);
      const from = parseBrDate(url.searchParams.get('dataInicial') ?? '01/01/2016');
      const to = parseBrDate(url.searchParams.get('dataFinal') ?? brDate(CAPTURE_DATE));
      return json(bcb(id, from, to));
    }
    return route.abort();
  });
}

// ---------------------------------------------------------------------------
// Percurso
// ---------------------------------------------------------------------------

async function launch(cli: Cli): Promise<Browser> {
  if (cli.browserPath !== null) return chromium.launch({ executablePath: cli.browserPath });
  try {
    return await chromium.launch();
  } catch (first) {
    for (const channel of ['chrome', 'msedge']) {
      try {
        return await chromium.launch({ channel });
      } catch {
        // tenta o próximo
      }
    }
    throw new Error(
      'Nenhum Chromium encontrado. Instale o do Playwright com\n' +
        '  npx playwright-core install chromium\n' +
        'ou passe o executável com --navegador <caminho>.\n' +
        `Erro original: ${(first as Error).message.split('\n')[0]}`,
    );
  }
}

/** Uma etapa que falha não derruba as outras: a captura dela fica de fora, e o erro sai no fim. */
async function step(errors: string[], label: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
  } catch (e) {
    errors.push(`${label}: ${(e as Error).message.split('\n')[0]}`);
  }
}

async function captureAll(browser: Browser, base: string, theme: ThemeName, width: number, errors: string[]): Promise<number> {
  const dir = join(OUT, theme);
  mkdirSync(dir, { recursive: true });
  const context = await browser.newContext({ viewport: { width, height: heightFor(width) }, locale: 'pt-BR', timezoneId: 'America/Sao_Paulo' });
  await context.clock.setFixedTime(CAPTURE_DATE);
  await context.addInitScript((t) => {
    try {
      localStorage.setItem('equisim:tema', t);
    } catch {
      // sem armazenamento, vale o padrão
    }
  }, THEMES[theme]);
  await installMarket(context);

  let saved = 0;
  const tag = `${theme}@${width}`;
  // A janela é esticada até a altura do conteúdo, e a foto é da janela. O
  // `fullPage` do Playwright rola a página por baixo de uma janela de altura
  // fixa, e o que é preso a ela sai fora do lugar: o cabeçalho grudado aparece
  // no meio do conteúdo e a barra de navegação fixa cobre um cartão. Com a
  // janela alta, fixo e grudado ficam onde o CSS os põe, como num aparelho alto
  // o bastante. Um diálogo conta pela própria altura: a folha se limita a
  // 88-92dvh e rola por dentro, então a janela cresce até ele caber.
  const shot = async (page: Page, n: number, name: string) => {
    await page.waitForTimeout(600);
    const original = { width, height: heightFor(width) };
    let height = original.height;
    for (let i = 0; i < 3; i++) {
      const need = await page.evaluate<number>(MEASURE_HEIGHT);
      if (need <= height) break;
      height = Math.min(need, MAX_HEIGHT);
      await page.setViewportSize({ width, height });
      await page.waitForTimeout(400);
    }
    await page.screenshot({ path: join(dir, `${pad(n)}-${name}@${width}.png`) });
    await page.setViewportSize(original);
    saved++;
  };

  // O painel de logs abre antes do resto, para receber os eventos do percurso.
  const logs = await context.newPage();
  await logs.goto(`${base}/logs`);
  const page = await context.newPage();
  await page.bringToFront();
  await page.goto(`${base}/estudo`);

  const add = async (ticker: string, principal: boolean) => {
    await page.getByRole('button', { name: 'Adicionar ativo' }).nth(principal ? 0 : 1).click();
    await page.locator('#picker-search').fill(ticker);
    await page.getByRole('button', { name: `Adicionar ${ticker} à ${principal ? 'Principal' : 'Reserva'}` }).click({ timeout: 30_000 });
    await page.waitForTimeout(400);
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
  };
  const closeDialogs = async () => {
    for (let i = 0; i < 4 && (await page.locator('[role=dialog]').count()) > 0; i++) {
      await page.keyboard.press('Escape');
      await page.waitForTimeout(350);
    }
  };

  await step(errors, `${tag} estudo`, async () => {
    await add('PETR4', true);
    await add('VALE3', true);
    await add('ITUB4', false);
    await page.waitForTimeout(8000);
    await shot(page, 1, 'estudo');
  });
  await step(errors, `${tag} raio-x`, async () => {
    await page.getByRole('button', { name: 'Adicionar ativo' }).first().click();
    await page.locator('#picker-search').fill('VALE3');
    await page.getByRole('button', { name: 'Abrir o Raio-X de VALE3' }).click();
    await page.waitForTimeout(5000);
    await shot(page, 2, 'raio-x');
    await closeDialogs();
  });
  await step(errors, `${tag} simular`, async () => {
    await page.goto(`${base}/ativo/VALE3/simular`);
    await page.waitForTimeout(6000);
    await shot(page, 3, 'simular');
    await page.getByRole('button', { name: /Confirmar/ }).first().click();
    await page.waitForTimeout(1500);
  });
  await step(errors, `${tag} valuations`, async () => {
    await page.goto(`${base}/valuations`);
    await page.waitForTimeout(2500);
    await shot(page, 4, 'valuations');
  });
  await step(errors, `${tag} meta`, async () => {
    await page.goto(`${base}/meta`);
    await page.waitForTimeout(5000);
    await shot(page, 5, 'meta');
  });
  await step(errors, `${tag} backtest`, async () => {
    await page.goto(`${base}/backtest`);
    await page.waitForTimeout(12_000);
    await shot(page, 6, 'backtest');
  });
  await step(errors, `${tag} logs`, async () => {
    await logs.bringToFront();
    await logs.waitForTimeout(500);
    await shot(logs, 7, 'logs');
  });
  await context.close();
  return saved;
}

async function main(): Promise<void> {
  const cli = parseArgs(process.argv.slice(2));
  // O modo local e o painel de logs, pelo ambiente que o Vite lê.
  process.env['VITE_EQUISIM_LOCAL'] = 'true';
  process.env['VITE_EQUISIM_AUDIT'] = 'true';
  const server = await createServer({ server: { port: cli.port, strictPort: true }, logLevel: 'error', clearScreen: false });
  await server.listen();
  const base = `http://localhost:${cli.port}`;
  const browser = await launch(cli);
  const errors: string[] = [];
  let total = 0;
  try {
    for (const theme of cli.themes) {
      for (const width of cli.widths) {
        const n = await captureAll(browser, base, theme, width, errors);
        total += n;
        process.stdout.write(`  ${theme} ${width}px: ${n} capturas\n`);
      }
    }
  } finally {
    await browser.close();
    await server.close();
  }
  process.stdout.write(`${total} capturas em docs/telas/\n`);
  if (errors.length > 0) {
    process.stderr.write(`\n${errors.length} etapa(s) sem captura:\n${errors.map((e) => `  ${e}`).join('\n')}\n`);
  }
}

main().catch((e: unknown) => {
  process.stderr.write(`${e instanceof Error ? e.message : String(e)}\n`);
  process.exitCode = 2;
});
