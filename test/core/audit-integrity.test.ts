// O rastro que o painel de logs recebe e exporta é íntegro (item D4).
//
// «Íntegro» quer dizer quatro coisas, cada uma com o seu teste:
//
// 1. **serializável sempre** — `NaN`, infinito e objetos que o JSON não
//    representa não derrubam a exportação;
// 2. **completo** — o evento de uma avaliação reproduz o resultado que a tela
//    mostra: o diagnóstico inteiro, a volatilidade da faixa, a triangulação e
//    as ressalvas;
// 3. **toda saída emite** — sucesso, recusa, exceção e falha de preparo deixam
//    evento, e nenhuma deixa dois;
// 4. **ida e volta sem perda** — o que sai no JSON volta ao painel da outra
//    janela com os mesmos valores.
import { afterEach, describe, expect, it } from 'vitest';

import {
  AuditEvent,
  AuditJson,
  AuditRecorder,
  type BenchmarkRepository,
  CapmInputs,
  CashTiming,
  DateTime,
  err,
  type FundamentalsRepository,
  FundamentalsSnapshot,
  InsufficientData,
  type JsonMap,
  MultipleKind,
  PeerMultiple,
  PeerMultipleSet,
  PrepareValuationInputs,
  type PriceRepository,
  type Result,
  StateError,
  Ticker,
  ValuationCascade,
  ValuationInputs,
  ValuationLane,
  type ValuationResult,
} from '../../src/core';
import { day, expectClose } from './helpers';

const ticker = Ticker.parse('ABCD3');

const year = (y: number, scale: number): FundamentalsSnapshot =>
  new FundamentalsSnapshot({
    ticker,
    fiscalPeriodEnd: day(y, 12, 31),
    totalRevenue: 10000 * scale,
    ebit: 1800 * scale,
    ebitda: 2400 * scale,
    netIncome: 900 * scale,
    incomeBeforeTax: 1300 * scale,
    incomeTaxExpense: -400 * scale,
    interestExpense: 400,
    earningsPerShare: 0.9 * scale,
    cash: 200,
    shortTermDebt: 1000,
    longTermDebt: 3000,
    totalStockholderEquity: 6000 * scale,
    bookValuePerShare: 6.0 * scale,
    operatingCashFlow: 2000 * scale,
    nopat: 1188 * scale,
    sharesOutstanding: 1000,
    sharesOutstandingAsOf: 1000,
    marketCap: 12000,
  });

function series(): FundamentalsSnapshot[] {
  const out: FundamentalsSnapshot[] = [];
  let scale = 1.0;
  for (let i = 12; i >= 0; i--) {
    out.push(year(2025 - i, scale));
    scale *= 1.05;
  }
  return out;
}

const capm = new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 });

const inputs = (notes: string[] = []): ValuationInputs =>
  new ValuationInputs({
    ticker,
    asOf: day(2026, 9, 9),
    fundamentals: series(),
    marketPrice: 12.0,
    capm,
    declaredTerminalRiskFreeRate: 0.094,
    peerMultiples: new PeerMultipleSet({
      byKind: new Map([
        [MultipleKind.priceToEarnings, new PeerMultiple({ median: 9, peers: 8, group: 'g' })],
        [MultipleKind.priceToBook, new PeerMultiple({ median: 1.4, peers: 8, group: 'g' })],
        [MultipleKind.evToEbitda, new PeerMultiple({ median: 6, peers: 8, group: 'g' })],
      ]),
      asOf: day(2026, 9, 1),
    }),
    contextNotes: notes,
  });

/** Captura os eventos emitidos durante [body]. */
function captureEvents(body: () => void): AuditEvent[] {
  const out: AuditEvent[] = [];
  AuditRecorder.attach((e) => out.push(e));
  try {
    body();
  } finally {
    AuditRecorder.detach();
  }
  return out;
}

const roundTrip = (json: JsonMap): JsonMap => JSON.parse(JSON.stringify(json)) as JsonMap;

afterEach(() => AuditRecorder.detach());

describe('serializável sempre', () => {
  it('valores que o JSON não representa viram texto, e o resto passa', () => {
    const safe = AuditJson.safe(
      new Map<unknown, unknown>([
        ['nan', Number.NaN],
        ['inf', Number.POSITIVE_INFINITY],
        ['menosInf', Number.NEGATIVE_INFINITY],
        ['data', DateTime.utc(2026, 9, 24)],
        ['enum', CashTiming.endOfYear],
        ['objeto', Ticker.parse('PETR4')],
        ['lista', [1, 2.5, Number.NaN]],
        [1, 'chave numérica'],
        ['finito', 0.1234],
        ['inteiro', 7],
      ]),
    ) as JsonMap;
    expect(() => JSON.stringify(safe)).not.toThrow();
    expect(safe['nan']).toBe('NaN');
    expect(safe['inf']).toBe('Infinity');
    expect(safe['menosInf']).toBe('-Infinity');
    expect(safe['data']).toBe('2026-09-24T00:00:00.000Z');
    expect(safe['enum']).toBe('fimDeAno');
    expect(safe['objeto']).toBe('PETR4');
    expect(safe['lista']).toEqual([1, 2.5, 'NaN']);
    expect(safe['1']).toBe('chave numérica');
    expect(safe['finito']).toBe(0.1234);
    expect(safe['inteiro']).toBe(7);
  });

  it('um passo degenerado não derruba a exportação, e volta como NaN', () => {
    const events = captureEvents(() => {
      const tx = AuditRecorder.begin('/core/teste', { inputPayload: { x: Number.NaN } })!;
      tx.step({
        formulaName: 'conta degenerada',
        latex: String.raw`x = 0/0`,
        variables: { a: Number.NaN, b: Number.POSITIVE_INFINITY },
        result: Number.NaN,
      });
      tx.complete({ saida: Number.NEGATIVE_INFINITY });
    });
    expect(events).toHaveLength(1);
    const back = AuditEvent.fromJson(roundTrip(events[0]!.toJson()));
    expect(back.calculations).toHaveLength(1);
    expect(Number.isNaN(back.calculations[0]!.finalValue!)).toBe(true);
    expect(back.calculations[0]!.mappedVariables['b']).toBe('Infinity');
    expect(back.inputPayload['x']).toBe('NaN');
    expect(back.outputPayload['saida']).toBe('-Infinity');
  });

  it('o JSON de um rastro sem valor degenerado não muda um byte', () => {
    const events = captureEvents(() => ValuationCascade.evaluate(inputs()));
    expect(events).toHaveLength(1);
    const e = events[0]!;
    const raw = JSON.stringify({
      entrada: e.inputPayload,
      saida: e.outputPayload,
      calculos: e.calculations.map((c) => c.toJson()),
    });
    const j = e.toJson();
    const safe = JSON.stringify({ entrada: j['inputPayload'], saida: j['outputPayload'], calculos: j['calculations'] });
    expect(safe).toBe(raw);
  });
});

describe('completo', () => {
  it('o evento reproduz o resultado que a tela mostra', () => {
    let r: Result<ValuationResult> | null = null;
    const events = captureEvents(() => {
      r = ValuationCascade.evaluate(inputs(['CVM defasada', 'curva de 12/09']));
    });
    expect(events).toHaveLength(1);
    const v = r!.unwrap();
    const event = roundTrip(events[0]!.toJson());
    const output = event['outputPayload'] as JsonMap;

    expect(output['status']).toBe('ok');
    expect(output['fairValue']).toBe(v.fairValue.reais);
    expect(output['marketPrice']).toBe(v.marketPrice.reais);
    expectClose(output['discountRate'] as number, v.discountRate, 1e-6);
    expect(output['warnings'], 'a tela e o arquivo leem as mesmas ressalvas').toEqual(v.warnings);
    expect(v.warnings).toEqual(expect.arrayContaining(['CVM defasada', 'curva de 12/09']));
    expect('priceVolatility' in output).toBe(true);

    const d = output['diagnostics'] as JsonMap;
    expect(Object.keys(d), 'os dezenove campos do diagnóstico, e não cinco').toEqual(
      expect.arrayContaining([
        'terminalShare',
        'equityShare',
        'baseFactor',
        'growthIdentified',
        'moatApplied',
        'caveats',
        'terminalRetainedSpread',
        'growthRate',
        'terminalReturnOnCapital',
        'firmTaxRate',
        'returnOnCapital',
        'terminalDiscountRate',
        'terminalCostOfEquity',
        'costOfEquity',
        'terminalExcessShare',
        'impliedTerminalReturn',
        'terminalEquityShare',
        'growthPath',
        'retentionPath',
      ]),
    );
    expectClose(d['costOfEquity'] as number, v.diagnostics!.costOfEquity, 1e-6);
    expect((d['growthPath'] as unknown[]).length).toBe(v.diagnostics!.growthPath.length);

    const tri = v.triangulation;
    if (tri !== null) {
      const t = output['triangulation'] as JsonMap;
      expect((t['readings'] as unknown[]).length).toBe(tri.readings.length);
    }
  });

  it('a entrada diz com que insumo a cascata rodou', () => {
    const events = captureEvents(() =>
      ValuationCascade.evaluate(inputs(['nota']).withOverrides({ lane: ValuationLane.firm, cashTiming: CashTiming.endOfYear })),
    );
    expect(events).toHaveLength(1);
    const entry = events[0]!.toJson()['inputPayload'] as JsonMap;
    expect(entry['fundamentalsPeriods']).toBe(13);
    expect(entry['fundamentalsOmitted'], 'o resumo tem seis exercícios, e diz que resumiu').toBe(7);
    expect(entry['terminalRiskFreeRate']).toBe(0.094);
    expect((entry['peerMultiples'] as JsonMap)['precoLucro']).toEqual({ median: 9, peers: 8, group: 'g' });
    expect(entry['overrides']).toEqual({ lane: 'firm', cashTiming: 'fimDeAno' });
    expect(entry['contextNotes']).toEqual(['nota']);
  });
});

describe('toda saída emite, e uma vez só', () => {
  it('sucesso', () => {
    expect(captureEvents(() => ValuationCascade.evaluate(inputs())).length).toBe(1);
  });

  it('recusa antes do primeiro passo', () => {
    const events = captureEvents(() =>
      ValuationCascade.evaluate(
        new ValuationInputs({ ticker, asOf: day(2026, 9, 9), fundamentals: series(), marketPrice: 0, capm }),
      ),
    );
    expect(events).toHaveLength(1);
    expect(events[0]!.outputPayload['status']).toBe('falha');
    expect(events[0]!.endpoint).toBe('/core/valuation/ABCD3');
  });

  it('uma exceção no meio da cascata fecha a transação e continua subindo', () => {
    const events: AuditEvent[] = [];
    AuditRecorder.attach((e) => events.push(e));
    expect(() =>
      ValuationCascade.evaluate(inputs(), {
        scenarioBuilder: () => {
          throw new StateError('fonte de cenários quebrada');
        },
      }),
    ).toThrow(StateError);
    expect(events).toHaveLength(1);
    const output = events[0]!.outputPayload;
    expect(output['status']).toBe('falha');
    expect(output['motivo']).toContain('fonte de cenários quebrada');
    expect(output['excecao']).toBe('StateError');
    expect((output['pilha'] as unknown[]).length).toBeGreaterThan(0);
  });

  it('a falha de preparo deixa evento no endpoint da avaliação', async () => {
    const events: AuditEvent[] = [];
    AuditRecorder.attach((e) => events.push(e));
    const unimplemented = (member: string) => (): never => {
      throw new Error(`não implementado: ${member}`);
    };
    const noFiscalYears: FundamentalsRepository = {
      history: () => Promise.resolve(err(new InsufficientData('fonte fora'))),
      profile: unimplemented('profile'),
      universe: unimplemented('universe'),
    };
    const nothing: PriceRepository & BenchmarkRepository = {
      daily: unimplemented('daily'),
      dailyBatch: unimplemented('dailyBatch'),
      adjustedCloseRaw: unimplemented('adjustedCloseRaw'),
      ibovespa: unimplemented('ibovespa'),
    };
    const r = await PrepareValuationInputs.call({
      ticker,
      prices: nothing,
      fundamentals: noFiscalYears,
      benchmark: nothing,
      riskFreeRate: 0.14,
      asOf: day(2026, 9, 9),
    });
    expect(r.isErr).toBe(true);
    expect(events).toHaveLength(1);
    const e = events[0]!;
    expect(e.endpoint).toBe('/core/valuation/ABCD3');
    expect(e.outputPayload['etapa']).toBe('preparo');
    expect(e.outputPayload['fonte']).toBe('exercícios');
    expect(e.outputPayload['motivo']).toBe('fonte fora');
  });
});
