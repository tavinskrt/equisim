import { describe, expect, it } from 'vitest';

import {
  type DateRange,
  DateTime,
  err,
  InsufficientData,
  ok,
  Portfolio,
  PortfolioKind,
  type PriceRepository,
  type PriceSeries,
  type Ticker,
} from '../../src/core';
import { comparePortfolios, correlationFromSeries, requestedWindow } from '../../src/app/backtest';
import { CsvExport } from '../../src/app/csv-export';
import { assetOf, comparisonOf, curve, outcomeOf, seriesOf } from './fixtures';

const today = DateTime.local(2025, 6, 30);

function portfolio(kind: PortfolioKind, symbols: readonly string[]): Portfolio {
  if (symbols.length === 0) return new Portfolio({ id: kind.key, name: kind.key, kind, entries: new Map() });
  return Portfolio.equalWeighted({ id: kind.key, name: kind.key, kind, assets: symbols.map((s) => assetOf(s)) }).unwrap();
}

/** Cotações de mentira: a série de cada ativo, recortada na janela pedida. */
function pricesOf(series: readonly PriceSeries[], fail = false): PriceRepository {
  const byTicker = new Map(series.map((s) => [s.ticker, s]));
  const batch = async (tickers: readonly Ticker[], range: DateRange) => {
    if (fail) return err(new InsufficientData('Sem cotações de PETR4 na janela.', { subject: 'PETR4' }));
    const out = new Map<Ticker, PriceSeries>();
    for (const t of tickers) {
      const s = byTicker.get(t);
      if (s !== undefined) out.set(t, s);
    }
    void range;
    return ok(out);
  };
  return {
    daily: async () => err(new InsufficientData('não usado')),
    dailyBatch: batch,
    adjustedCloseRaw: async () => err(new InsufficientData('não usado')),
  };
}

const closes = (n: number, start: number, end: number) => curve(start, end, n);

describe('O backtest comparativo', () => {
  it('as duas carteiras correm na mesma janela, a do ativo mais novo, e ele é nomeado', async () => {
    const start = requestedWindow(today, 2).start;
    const late = DateTime.local(2024, 3, 1);
    const result = (await comparePortfolios({
      principal: portfolio(PortfolioKind.principal, ['PETR4', 'VALE3']),
      reserve: portfolio(PortfolioKind.reserve, ['SAPR11']),
      settings: { windowYears: 2 },
      prices: pricesOf([
        seriesOf('PETR4', start, closes(380, 30, 40)),
        seriesOf('VALE3', start, closes(380, 60, 70)),
        seriesOf('SAPR11', late, closes(300, 20, 25)),
      ]),
      today,
      riskFreeRateFor: async () => 0.1,
    }))!;
    expect(result.windowWasShortened).toBe(true);
    expect(result.limitingTicker!.value).toBe('SAPR11');
    expect(result.window.start.equals(late)).toBe(true);
    expect(result.principal!.effectivePeriod.start.isBefore(late)).toBe(false);
    expect(result.principal).not.toBeNull();
    expect(result.reserve).not.toBeNull();
    expect(result.twrGap).not.toBeNull();
  });

  it('a janela pedida começa à meia-noite de hoje menos N anos', () => {
    const w = requestedWindow(DateTime.local(2025, 6, 30, 15, 42), 5);
    expect(w.start.equals(DateTime.local(2020, 6, 30))).toBe(true);
  });

  it('sem ativo não há o que simular; sem meta, sim — o plano de aportes não compra nada aqui', async () => {
    const start = requestedWindow(today, 1).start;
    const args = {
      principal: portfolio(PortfolioKind.principal, ['PETR4']),
      reserve: portfolio(PortfolioKind.reserve, []),
      settings: { windowYears: 1 },
      prices: pricesOf([seriesOf('PETR4', start, closes(250, 30, 40))]),
      today,
      riskFreeRateFor: async () => 0.1,
    };
    expect(await comparePortfolios({ ...args, principal: portfolio(PortfolioKind.principal, []) })).toBeNull();
    expect((await comparePortfolios(args))!.principal).not.toBeNull();
  });

  it('compra uma ação de cada ativo no primeiro pregão da janela, e nada depois (decisão 161)', async () => {
    const start = requestedWindow(today, 1).start;
    const petr = seriesOf('PETR4', start, closes(250, 30, 40));
    const vale = seriesOf('VALE3', start, closes(250, 60, 55));
    const result = (await comparePortfolios({
      principal: portfolio(PortfolioKind.principal, ['PETR4', 'VALE3']),
      reserve: portfolio(PortfolioKind.reserve, []),
      settings: { windowYears: 1 },
      prices: pricesOf([petr, vale]),
      today,
      riskFreeRateFor: async () => 0.1,
    }))!;
    const o = result.principal!;
    const cents = (v: number) => Math.round(v * 100);
    // Tarifa da B3, 0,030% meio para cima, por ordem.
    const fee = (pc: number) => Math.floor((pc * 300 + 500000) / 1000000);
    const p0 = cents(petr.points[0]!.close);
    const v0 = cents(vale.points[0]!.close);
    for (const a of o.perAsset.values()) expect(a.shares).toBe(1);
    expect(o.totalContributed.cents).toBe(p0 + fee(p0) + v0 + fee(v0));
    expect(o.transactionCosts.cents).toBe(fee(p0) + fee(v0));
    expect(o.residualCash.cents).toBe(0);
    // O patrimônio do último pregão é a soma dos dois fechamentos: uma ação de cada, sem compra no meio.
    const last = (s: typeof petr) => cents(s.points[s.points.length - 1]!.close);
    expect(o.finalValue.cents).toBe(last(petr) + last(vale));
    // Sem fluxo depois do primeiro dia, a base 100 é o patrimônio sobre o do primeiro dia.
    expect(o.base100[o.base100.length - 1]!).toBeCloseTo((100 * o.wealth[o.wealth.length - 1]!) / o.wealth[0]!, 9);
    // E o XIRR, com um fluxo só na entrada, repete o CAGR — por isso saiu da tela.
    expect(o.metrics.moneyWeightedReturn!).toBeCloseTo(o.metrics.cagr, 3);
  });

  it('a falha das cotações vira texto de tela nas duas carteiras', async () => {
    const result = (await comparePortfolios({
      principal: portfolio(PortfolioKind.principal, ['PETR4']),
      reserve: portfolio(PortfolioKind.reserve, ['ITUB4']),
      settings: { windowYears: 1 },
      prices: pricesOf([], true),
      today,
      riskFreeRateFor: async () => 0.1,
    }))!;
    expect(result.principalFailure).toBe('Dados insuficientes · PETR4 — Sem cotações de PETR4 na janela.');
    expect(result.reserveFailure).toBe(result.principalFailure);
    expect(result.principal).toBeNull();
    expect(result.reserve).toBeNull();
  });

  it('a dispersão desenha cada ativo uma vez, exige um mês de pregões e traz as carteiras', async () => {
    const start = requestedWindow(today, 1).start;
    const result = (await comparePortfolios({
      principal: portfolio(PortfolioKind.principal, ['PETR4', 'VALE3']),
      reserve: portfolio(PortfolioKind.reserve, ['ITUB4']),
      settings: { windowYears: 1 },
      prices: pricesOf([
        seriesOf('PETR4', start, closes(250, 30, 40)),
        seriesOf('VALE3', start, closes(250, 60, 55)),
        seriesOf('ITUB4', start, closes(250, 25, 30)),
      ]),
      today,
      riskFreeRateFor: async () => 0.1,
    }))!;
    const labels = result.riskReturn.map((p) => `${p.kind}:${p.label}`);
    expect(labels).toEqual([
      'principalAsset:PETR4',
      'principalAsset:VALE3',
      'reserveAsset:ITUB4',
      'principal:Principal',
      'reserve:Reserva',
    ]);
    const petr = result.riskReturn[0]!;
    expect(petr.ret, 'em pontos percentuais').toBeGreaterThan(1);
  });
});

describe('A correlação', () => {
  it('sobre o calendário comum, simétrica e com diagonal 1', () => {
    const start = DateTime.local(2024, 1, 1);
    const a = seriesOf('PETR4', start, closes(60, 30, 40));
    const b = seriesOf('VALE3', start, closes(60, 60, 50));
    const window = requestedWindow(DateTime.local(2024, 12, 31), 1);
    const m = correlationFromSeries([a.ticker, b.ticker], new Map([[a.ticker, a], [b.ticker, b]]), window)!;
    expect(m.tickers.map((t) => t.value)).toEqual(['PETR4', 'VALE3']);
    expect(m.matrix[0]![0]).toBeCloseTo(1, 12);
    expect(m.matrix[0]![1]).toBeCloseTo(m.matrix[1]![0]!, 12);
  });

  it('menos de 30 pregões em comum não sustenta correlação', () => {
    const start = DateTime.local(2024, 1, 1);
    const a = seriesOf('PETR4', start, closes(20, 30, 40));
    const b = seriesOf('VALE3', start, closes(20, 60, 50));
    const window = requestedWindow(DateTime.local(2024, 12, 31), 1);
    expect(correlationFromSeries([a.ticker, b.ticker], new Map([[a.ticker, a], [b.ticker, b]]), window)).toBeNull();
  });
});

describe('O CSV', () => {
  const result = comparisonOf({
    principal: outcomeOf('PETR4', curve(10, 12)),
    reserve: outcomeOf('ITUB4', curve(10, 11)),
  });

  it('abre no Excel brasileiro: ponto e vírgula e vírgula decimal', () => {
    const metrics = CsvExport.metrics(result).split('\n');
    expect(metrics[0]).toBe('metrica;principal;reserva');
    expect(metrics.find((l) => l.startsWith('capital_investido'))).toBe('capital_investido;10,00;10,00');
    expect(metrics.some((l) => l.includes('xirr') || l.includes('caixa'))).toBe(false);
  });

  it('a quantidade de ações sai inteira', () => {
    const lines = CsvExport.perAsset(result.principal!).split('\n');
    const row = lines[1]!.split(';');
    expect(lines[0]).toBe('ticker;retorno;acoes;capital_investido;valor_final');
    expect(row[0]).toBe('PETR4');
    expect(row[2]).toBe('1');
  });

  it('o documento traz cabeçalho, as duas carteiras por ativo e a série', () => {
    const doc = CsvExport.document({ studyName: 'Teste', result, generatedAt: DateTime.local(2025, 1, 2) });
    expect(doc.startsWith('# Equisim — Teste\n# Período: 01/01/2024 a 31/12/2024\n# Gerado em 02/01/2025\n\n## Métricas\n')).toBe(true);
    expect(doc).toContain('## Desempenho por ativo (Principal)');
    expect(doc).toContain('## Desempenho por ativo (Reserva)');
    expect(doc).toContain('## Série temporal\ndata;principal_base100;principal_patrimonio;reserva_base100;reserva_patrimonio\n');
  });
});
