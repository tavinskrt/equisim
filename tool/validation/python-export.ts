import {
  BetaCalculator,
  DateRange,
  DateTime,
  MarketAnchors,
  type PriceSeries,
  Returns,
  RiskMetrics,
  Ticker,
  tradingDaysPerYear,
} from '../../src/core';
import { errln, outln } from '../lib/files';
import { type ValidationContext, writeReport } from './context';

const iso = (date: DateTime) =>
  `${String(date.year).padStart(4, '0')}-${String(date.month).padStart(2, '0')}-${String(date.day).padStart(2, '0')}`;

/**
 * Exporta séries e métricas para conferência independente em Python.
 *
 * **Por que isto existe.** O núcleo não tem ecossistema científico maduro —
 * não há NumPy nem SciPy. Toda a estatística deste trabalho foi implementada
 * à mão. Afirmar que está certa sem conferência externa seria pedir confiança;
 * exportar as séries e recalcular tudo com bibliotecas consagradas transforma
 * a limitação em evidência de corretude.
 *
 * Os arquivos gerados alimentam `cross_validation.py`, que recomputa
 * volatilidade, beta, correlação, Sharpe, XIRR e o DCF, e reporta a diferença.
 */
export const PythonExport = {
  /**
   * Separador de campo dos CSV gerados.
   *
   * Vírgula, não ponto e vírgula: os arquivos são lidos por `pandas` com o
   * padrão dele, e os números são gravados com ponto decimal.
   */
  separator: ',',

  /**
   * Gera todos os arquivos de conferência no diretório de saída.
   *
   * - [ctx]: contexto com a camada de dados.
   * - [symbols]: tickers da amostra.
   * - [outputDir]: destino dos CSV. **Arquivos existentes são
   *   sobrescritos.**
   * - [windowYears]: janela histórica exportada. Padrão 5 anos.
   *
   * A janela termina em `DateTime.now()`, então **duas execuções em dias
   * diferentes produzem arquivos diferentes**. É deliberado — a conferência
   * vale sobre dados correntes —, mas significa que reproduzir um relatório
   * antigo exige o cache daquela data, não apenas o mesmo comando.
   *
   * Ativos sem dados utilizáveis são omitidos dos arquivos em vez de
   * interromper a exportação.
   */
  async run(ctx: ValidationContext, args: { symbols: readonly string[]; outputDir: string; windowYears?: number }): Promise<void> {
    const today = DateTime.now();
    const window = new DateRange(DateTime.local(today.year - (args.windowYears ?? 5), today.month, today.day), today);

    const tickers = args.symbols.map((s) => Ticker.tryParse(s)).filter((t): t is Ticker => t !== null);

    outln('  buscando séries...');
    const priceResult = await ctx.prices.dailyBatch(tickers, window);
    if (priceResult.isErr) {
      errln(`  falha: ${priceResult.failureOrNull!.message}`);
      return;
    }
    const priceMap = priceResult.unwrap();

    const benchmarkResult = await ctx.benchmark.ibovespa(window);

    // 1. Preços de fechamento, um ativo por coluna.
    exportPrices(priceMap, benchmarkResult.valueOrNull, args.outputDir);

    // 2. Métricas calculadas pelo motor, para o Python conferir.
    await exportMetrics(ctx, priceMap, benchmarkResult.valueOrNull, window, args.outputDir);
  },
};

const byTicker = (a: Ticker, b: Ticker) => a.compareTo(b);

function exportPrices(prices: Map<Ticker, PriceSeries>, benchmark: PriceSeries | null, outputDir: string): void {
  const sep = PythonExport.separator;
  const tickers = [...prices.keys()].sort(byTicker);
  const calendar = new Map<string, DateTime>();
  for (const series of prices.values()) for (const d of series.dates) calendar.set(d.key, d);
  const dates = [...calendar.values()].sort((a, b) => a.compareTo(b));

  const lines = [['date', ...tickers.map((t) => t.value), ...(benchmark === null ? [] : ['IBOV'])].join(sep)];
  for (const date of dates) {
    const row = [iso(date)];
    for (const ticker of tickers) row.push(prices.get(ticker)!.closeOn(date)?.toFixed(6) ?? '');
    if (benchmark !== null) row.push(benchmark.closeOn(date)?.toFixed(6) ?? '');
    lines.push(row.join(sep));
  }

  writeReport(`${outputDir}/precos.csv`, `${lines.join('\n')}\n`);
}

async function exportMetrics(
  ctx: ValidationContext,
  prices: Map<Ticker, PriceSeries>,
  benchmark: PriceSeries | null,
  window: DateRange,
  outputDir: string,
): Promise<void> {
  const sep = PythonExport.separator;
  const riskFreeResult = await ctx.macro.riskFreeDaily(window);
  const riskFree = riskFreeResult.isOk ? riskFreeResult.unwrap().annualized() : MarketAnchors.fallback2026.riskFreeCagr;

  const lines = [
    [
      'ticker',
      'retorno_total',
      'cagr',
      'volatilidade_anual',
      'max_drawdown',
      'sharpe',
      'sortino',
      'beta',
      'correlacao_ibov',
      'observacoes',
    ].join(sep),
  ];

  for (const ticker of [...prices.keys()].sort(byTicker)) {
    // Índice de preço em base 1,0 no primeiro pregão da janela: é sobre ele
    // que retorno, risco e beta são apurados, na mesma convenção que o
    // aplicativo usa desde a remoção dos proventos.
    const points = prices.get(ticker)!.points.filter((point) => window.contains(point.date));
    if (points.length < 2 || points[0]!.close <= 0) continue;

    const dates = points.map((point) => point.date);
    const index = points.map((point) => point.close / points[0]!.close);
    const totalReturn = index[index.length - 1]! / index[0]! - 1.0;

    const years = new DateRange(dates[0]!, dates[dates.length - 1]!).years;
    const cagr = Returns.annualize(totalReturn, years);
    const risk = RiskMetrics.fromIndex({ twrIndex: index, cagr, riskFreeRate: riskFree });

    let beta = '';
    let correlation = '';
    let observations = '';
    if (benchmark !== null) {
      const aligned = BetaCalculator.alignReturns({
        assetDates: dates,
        assetIndex: index,
        marketDates: benchmark.dates,
        marketIndex: benchmark.points.map((p) => p.close),
      });
      const estimate = BetaCalculator.estimate({ returns: aligned });
      if (estimate.isOk) {
        beta = estimate.unwrap().beta.toFixed(8);
        correlation = estimate.unwrap().correlation.toFixed(8);
        observations = `${estimate.unwrap().observations}`;
      }
    }

    lines.push(
      [
        ticker.value,
        totalReturn.toFixed(8),
        cagr.toFixed(8),
        risk.volatility.toFixed(8),
        risk.maxDrawdown.toFixed(8),
        risk.sharpe.toFixed(8),
        risk.sortino.toFixed(8),
        beta,
        correlation,
        observations,
      ].join(sep),
    );
  }

  writeReport(`${outputDir}/metricas_equisim.csv`, `${lines.join('\n')}\n`);

  // Parâmetros usados, para o Python reproduzir exatamente.
  const parameters = [
    ['parametro', 'valor'],
    ['taxa_livre_risco_anual', riskFree.toFixed(8)],
    ['pregoes_por_ano', `${tradingDaysPerYear}`],
    ['janela_inicio', iso(window.start)],
    ['janela_fim', iso(window.end)],
    ['desvio_padrao', 'amostral (n-1)'],
  ].map((r) => r.join(sep));

  writeReport(`${outputDir}/parametros.csv`, `${parameters.join('\n')}\n`);
}
