// O efeito da tarifa da B3 sobre a simulação da carteira (item C4).
//
// A simulação do aplicativo passou a cobrar a tarifa de negociação e
// liquidação da B3 em cada compra (`TransactionCosts.b3`, 0,030%). Aqui se
// mede quanto isso move o que a tela mostra: patrimônio final, XIRR e o custo
// somado, em carteiras sorteadas do universo congelado do gabarito — semente
// fixa, a mesma entrada a cada execução.
//
// **O que não entra.** O spread de compra e venda: a simulação compra ao
// fechamento, e o meio spread de quem manda ordem a mercado foi medido nas
// coortes (`tool/custos_spread.py`), onde ele é o que pesa. Uma sensibilidade
// com 0,5% por compra — a ordem do meio spread do tercil médio de liquidez —
// fica ao lado, para dizer quanto ele pesaria aqui.
//
// Uso:
//   npm run tool -- cascade-golden        # a entrada congelada, se faltar
//   npm run tool -- simulation-costs
import {
  Asset,
  type BacktestOutcome,
  compareNum,
  compareStr,
  ContributionPlan,
  DateRange,
  DateTime,
  intDiv,
  min,
  Money,
  Portfolio,
  PortfolioBacktest,
  PortfolioKind,
  type PriceSeries,
  Sector,
  SeededRandom,
  type Ticker,
  TransactionCosts,
} from '../src/core';
import { jsonPretty, outln, writeText } from './lib/files';
import { shuffle } from './lib/shuffle';
import { Frozen } from './validation/frozen';

const portfolios = 50;
const assetsPerPortfolio = 8;
const seed = 20260922;

interface ScenarioRow {
  patrimonioFinal: number;
  xirr: number | null;
  custos: number;
}

export async function main(_args: string[]): Promise<void> {
  const c = await Frozen.build();
  const window = new DateRange(DateTime.local(2019, 1, 2), DateTime.local(2026, 8, 31));

  const series = new Map<Ticker, PriceSeries>();
  for (const t of c.universe) {
    const r = await c.ctx.prices.daily(t, window);
    const s = r.valueOrNull;
    // Só quem tem a janela inteira: série encurtada encurtaria a simulação de
    // todos os ativos da carteira sorteada.
    if (s === null || s.isEmpty) continue;
    if (s.firstDate.isAfter(DateTime.local(2019, 1, 31))) continue;
    series.set(t, s);
  }
  outln('== Custo de transação na simulação (item C4) ==');
  outln(`  ativos com a janela inteira: ${series.size}`);

  const rnd = new SeededRandom(seed);
  const available = [...series.keys()].sort((a, b) => compareStr(a.value, b.value));
  const plan = new ContributionPlan({ initial: Money.fromReais(10000), monthly: Money.fromReais(1000), contributionDay: 5 });
  const scenarios = new Map<string, TransactionCosts>([
    ['semCusto', TransactionCosts.none],
    ['tarifaB3', TransactionCosts.b3],
    ['tarifaEMeioSpread', new TransactionCosts({ feePartsPerMillion: 5300 })],
  ]);

  const rows: Record<string, unknown>[] = [];
  for (let i = 0; i < portfolios; i++) {
    const choice = shuffle([...available], rnd);
    const assets = choice.slice(0, assetsPerPortfolio);
    const portfolio = Portfolio.equalWeighted({
      id: `c${i}`,
      name: `c${i}`,
      kind: PortfolioKind.principal,
      assets: assets.map((t) => new Asset({ ticker: t, name: t.value, sector: Sector.unknown })),
    }).unwrap();
    const byScenario = new Map<string, BacktestOutcome>();
    for (const [key, costs] of scenarios) {
      const r = PortfolioBacktest.run({
        portfolio,
        prices: new Map(assets.map((t) => [t, series.get(t)!])),
        plan,
        range: window,
        costs,
      });
      if (r.isOk) byScenario.set(key, r.unwrap());
    }
    if (byScenario.size !== scenarios.size) continue;
    const base = byScenario.get('semCusto')!;
    const row: Record<string, unknown> = { ativos: assets.map((t) => t.value), aportado: base.totalContributed.reais };
    for (const [key, outcome] of byScenario) {
      row[key] = {
        patrimonioFinal: outcome.finalValue.reais,
        xirr: outcome.metrics.moneyWeightedReturn,
        custos: outcome.transactionCosts.reais,
      } satisfies ScenarioRow;
    }
    rows.push(row);
  }

  const median = (xs: readonly number[]): number => {
    const s = [...xs].sort(compareNum);
    return s.length === 0 ? Number.NaN : s[intDiv(s.length, 2)]!;
  };

  const summary: Record<string, unknown> = { carteiras: rows.length };
  for (const k of ['tarifaB3', 'tarifaEMeioSpread']) {
    const wealthLoss: number[] = [];
    const xirrLoss: number[] = [];
    const costOverContributed: number[] = [];
    for (const l of rows) {
      const b = l['semCusto'] as ScenarioRow;
      const x = l[k] as ScenarioRow;
      wealthLoss.push(x.patrimonioFinal / b.patrimonioFinal - 1);
      if (b.xirr !== null && x.xirr !== null) xirrLoss.push(x.xirr - b.xirr);
      costOverContributed.push(x.custos / (l['aportado'] as number));
    }
    summary[k] = {
      variacaoDoPatrimonioFinalMediana: median(wealthLoss),
      variacaoDoXirrMediana: median(xirrLoss),
      piorVariacaoDoXirr: xirrLoss.length === 0 ? null : xirrLoss.reduce(min),
      custoSobreAportadoMediano: median(costOverContributed),
    };
  }
  writeText(
    'docs/validacao/custos_simulacao.json',
    jsonPretty({
      semente: seed,
      janela: `${window.start.toIso8601String().slice(0, 10)} a ${window.end.toIso8601String().slice(0, 10)}`,
      plano: 'R$ 10.000 inicial e R$ 1.000 por mês',
      resumo: summary,
      carteiras: rows,
    }),
  );
  outln(jsonPretty(summary, '  '));
  await c.ctx.dispose();
}
