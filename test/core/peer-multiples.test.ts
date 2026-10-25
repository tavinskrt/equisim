import { describe, expect, it } from 'vitest';

import {
  FundamentalsSnapshot,
  type JsonObject,
  type MultipleReading,
  MultipleKind,
  MultipleRefusal,
  PeerMultiple,
  PeerMultipleCodec,
  PeerMultipleSet,
  PeerTriangulation,
  PeerValuation,
  Ticker,
} from '../../src/core';
import { day, expectClose, expectDate } from './helpers';

/** Item B5 — a segunda leitura, por múltiplos de pares. */

const ticker = Ticker.parse('PETR4');
const today = day(2026, 9, 14);

const pairs = (
  o: { pl?: number; priceToBookMedian?: number; evEbitda?: number; n?: number; group?: string } = {},
): PeerMultipleSet => {
  const n = o.n ?? 12;
  const group = o.group ?? 'petroleo-gas-e-biocombustiveis';
  const byKind = new Map<MultipleKind, PeerMultiple>();
  if (o.pl !== undefined) byKind.set(MultipleKind.priceToEarnings, new PeerMultiple({ median: o.pl, peers: n, group }));
  if (o.priceToBookMedian !== undefined) {
    byKind.set(MultipleKind.priceToBook, new PeerMultiple({ median: o.priceToBookMedian, peers: n, group }));
  }
  if (o.evEbitda !== undefined) byKind.set(MultipleKind.evToEbitda, new PeerMultiple({ median: o.evEbitda, peers: n, group }));
  return new PeerMultipleSet({ asOf: today, byKind });
};

const fiscalYear = (
  o: { profit?: number | null; equity?: number | null; ebitda?: number | null; cash?: number; debt?: number } = {},
): FundamentalsSnapshot => {
  const profit = 'profit' in o ? o.profit! : 1000;
  const equity = 'equity' in o ? o.equity! : 8000;
  const ebitda = 'ebitda' in o ? o.ebitda! : 2400;
  const cash = o.cash ?? 500;
  const debt = o.debt ?? 3000;
  return new FundamentalsSnapshot({
    ticker,
    fiscalPeriodEnd: day(2025, 12, 31),
    totalRevenue: 12000,
    ebit: 1800,
    ebitda,
    netIncome: profit,
    incomeBeforeTax: 1400,
    incomeTaxExpense: -400,
    interestExpense: 300,
    earningsPerShare: profit === null ? null : profit / 1000,
    cash,
    shortTermDebt: debt * 0.25,
    longTermDebt: debt * 0.75,
    totalStockholderEquity: equity,
    bookValuePerShare: equity === null ? null : equity / 1000,
    operatingCashFlow: 2000,
    sharesOutstanding: 1000,
    sharesOutstandingAsOf: 1000,
    marketCap: 10000,
  });
};

const of = (rs: readonly MultipleReading[], kind: MultipleKind): MultipleReading => rs.find((r) => r.kind === kind)!;

describe('Cada múltiplo devolve o preço que ele implica', () => {
  it('P/L é o múltiplo vezes o lucro, pelo divisor da ponte', () => {
    const r = of(PeerValuation.readings({ latest: fiscalYear(), shares: 1000, peers: pairs({ pl: 9.0 }) }), MultipleKind.priceToEarnings);
    expect(r.applied).toBe(true);
    expectClose(r.fairValuePerShare!, (9.0 * 1000) / 1000, 1e-12);
    expect(r.peer!.group).toBe('petroleo-gas-e-biocombustiveis');
  });

  it('o divisor é o da ponte, e não a contagem da fonte', () => {
    // **A conferência que impede a comparação de medir outra coisa.** A
    // contagem da fonte é 1.000; se a ponte arbitrou 1.500, o múltiplo tem
    // de dividir por 1.500 — ou a divergência contra o DCF mediria a ponte
    // (decisão 83).
    const a = PeerValuation.readings({ latest: fiscalYear(), shares: 1000, peers: pairs({ pl: 9.0 }) })[0]!;
    const b = PeerValuation.readings({ latest: fiscalYear(), shares: 1500, peers: pairs({ pl: 9.0 }) })[0]!;
    expectClose(b.fairValuePerShare! / a.fairValuePerShare!, 1000 / 1500, 1e-12);
  });

  it('EV/EBITDA passa pela mesma ponte de dívida líquida do DCF', () => {
    const r = of(PeerValuation.readings({ latest: fiscalYear(), shares: 1000, peers: pairs({ evEbitda: 6.0 }) }), MultipleKind.evToEbitda);
    // 6 × 2.400 = 14.400 de firma; menos 2.500 de dívida líquida = 11.900.
    expectClose(r.fairValuePerShare!, 11.9, 1e-12);
  });

  it('caixa líquido soma, e é legítimo', () => {
    const r = of(
      PeerValuation.readings({ latest: fiscalYear({ cash: 6000, debt: 1000 }), shares: 1000, peers: pairs({ evEbitda: 6.0 }) }),
      MultipleKind.evToEbitda,
    );
    // 14.400 − (1.000 − 6.000) = 19.400.
    expectClose(r.fairValuePerShare!, 19.4, 1e-12);
  });
});

describe('Cada recusa diz por que o múltiplo não se aplica', () => {
  it('prejuízo tira o P/L, e não o inverte', () => {
    const r = of(
      PeerValuation.readings({
        latest: fiscalYear({ profit: -500 }),
        shares: 1000,
        peers: pairs({ pl: 9.0, priceToBookMedian: 1.2 }),
      }),
      MultipleKind.priceToEarnings,
    );
    expect(r.applied).toBe(false);
    expect(r.refusal).toBe(MultipleRefusal.nonPositiveBase);
  });

  it('patrimônio negativo tira o P/VP', () => {
    const r = of(
      PeerValuation.readings({ latest: fiscalYear({ equity: -200 }), shares: 1000, peers: pairs({ priceToBookMedian: 1.2 }) }),
      MultipleKind.priceToBook,
    );
    expect(r.refusal).toBe(MultipleRefusal.nonPositiveBase);
  });

  it('instituição financeira não usa EV/EBITDA', () => {
    // Depósito e captação são insumo do negócio, e não financiamento
    // (decisão 102): a ponte de dívida líquida não descreve banco.
    const r = of(
      PeerValuation.readings({
        latest: fiscalYear(),
        shares: 1000,
        peers: pairs({ evEbitda: 6.0 }),
        sectorKey: 'financeiro',
        industry: 'Intermediários Financeiros',
      }),
      MultipleKind.evToEbitda,
    );
    expect(r.refusal).toBe(MultipleRefusal.financialInstitution);

    // E o setor econômico sozinho **não** basta: na taxonomia oficial da B3
    // ele reúne banco, seguradora e administradora, e quem separa é o
    // subsetor (decisão 87). Sem ele, o múltiplo entra.
    const withoutSubsector = of(
      PeerValuation.readings({ latest: fiscalYear(), shares: 1000, peers: pairs({ evEbitda: 6.0 }), sectorKey: 'financeiro' }),
      MultipleKind.evToEbitda,
    );
    expect(withoutSubsector.applied).toBe(true);
  });

  it('grupo pequeno demais não produz mediana usável', () => {
    const r = PeerValuation.readings({
      latest: fiscalYear(),
      shares: 1000,
      peers: pairs({ pl: 9.0, n: PeerValuation.minimumPeers - 1 }),
    })[0]!;
    expect(r.refusal).toBe(MultipleRefusal.insufficientPeers);
  });

  it('a ponte que deixa o acionista negativo é recusada, e não invertida', () => {
    const r = of(
      PeerValuation.readings({
        latest: fiscalYear({ ebitda: 100, debt: 9000, cash: 0 }),
        shares: 1000,
        peers: pairs({ evEbitda: 6.0 }),
      }),
      MultipleKind.evToEbitda,
    );
    expect(r.refusal).toBe(MultipleRefusal.nonPositiveBridge);
    expect(r.fairValuePerShare).toBeNull();
  });
});

describe('O consolidado é mediana, e a divergência é declarada', () => {
  it('mediana das aplicadas, e o fora da curva não arrasta', () => {
    const rs = PeerValuation.readings({
      latest: fiscalYear(),
      shares: 1000,
      peers: pairs({ pl: 9.0, priceToBookMedian: 1.2, evEbitda: 60.0 }),
    });
    // 9,00 / 9,60 / 141,90 — a mediana é 9,60, e a média seria 53,50.
    expectClose(PeerValuation.consolidated(rs)!, 9.6, 1e-9);
  });

  it('a divergência é múltiplos ÷ DCF − 1', () => {
    const rs = PeerValuation.readings({ latest: fiscalYear(), shares: 1000, peers: pairs({ pl: 9.0 }) });
    expectClose(PeerValuation.divergence({ readings: rs, dcfFairValue: 6.0 })!, 9.0 / 6.0 - 1, 1e-12);
  });

  it('DCF não positivo não produz divergência inventada', () => {
    const rs = PeerValuation.readings({ latest: fiscalYear(), shares: 1000, peers: pairs({ pl: 9.0 }) });
    expect(PeerValuation.divergence({ readings: rs, dcfFairValue: 0 })).toBeNull();
  });

  it('sem leitura aplicável, não há consolidado nem divergência', () => {
    const rs = PeerValuation.readings({
      latest: fiscalYear({ profit: -1, equity: -1, ebitda: -1 }),
      shares: 1000,
      peers: pairs({ pl: 9.0, priceToBookMedian: 1.2, evEbitda: 6.0 }),
    });
    expect(PeerValuation.consolidated(rs)).toBeNull();
    expect(PeerValuation.divergence({ readings: rs, dcfFairValue: 6.0 })).toBeNull();
  });

  it('o limite de divergência separa concordar de discordar', () => {
    const withInput = (dcf: number): PeerTriangulation =>
      PeerTriangulation.build({ latest: fiscalYear(), shares: 1000, peers: pairs({ pl: 9.0 }), dcfFairValue: dcf })!;
    // 9,00 contra 6,20 é +45%; contra 5,80 é +55%.
    expect(withInput(6.2).diverges).toBe(false);
    expect(withInput(5.8).diverges).toBe(true);
  });

  it('sem pacote de pares não há triangulação', () => {
    expect(PeerTriangulation.build({ latest: fiscalYear(), shares: 1000, peers: null, dcfFairValue: 6.0 })).toBeNull();
  });
});

describe('O pacote versionado vai e volta', () => {
  it('o codec lê o que a ferramenta grava', () => {
    const json: JsonObject = {
      geradoEm: today.toIso8601String(),
      porTicker: {
        PETR4: {
          precoLucro: { mediana: 9.0, pares: 12, grupo: 'petroleo' },
          precoPatrimonio: { mediana: 1.2, pares: 14, grupo: 'petroleo' },
        },
      },
    };
    const parsed = PeerMultipleCodec.decode(json);
    expect([...parsed.keys()]).toEqual(['PETR4']);
    const s = parsed.get('PETR4')!;
    expectDate(s.asOf, today);
    expect(s.byKind.get(MultipleKind.priceToEarnings)!.median).toBe(9.0);
    expect(s.byKind.get(MultipleKind.priceToEarnings)!.peers).toBe(12);
    expect(s.byKind.has(MultipleKind.evToEbitda)).toBe(false);
  });

  it('pacote ilegível desliga a triangulação em vez de explodir', () => {
    expect(PeerMultipleCodec.decode({}).size).toBe(0);
    expect(PeerMultipleCodec.decode({ porTicker: 7 }).size).toBe(0);
    expect(PeerMultipleCodec.decode({ geradoEm: 'nem data', porTicker: { PETR4: {} } }).size).toBe(0);
  });

  it('mediana não positiva no pacote é descartada, e não usada', () => {
    const parsed = PeerMultipleCodec.decode({
      geradoEm: today.toIso8601String(),
      porTicker: {
        PETR4: {
          precoLucro: { mediana: -3.0, pares: 12, grupo: 'x' },
          precoPatrimonio: { mediana: 1.2, pares: 12, grupo: 'x' },
        },
      },
    });
    expect(parsed.get('PETR4')!.byKind.has(MultipleKind.priceToEarnings)).toBe(false);
    expect(parsed.get('PETR4')!.byKind.has(MultipleKind.priceToBook)).toBe(true);
  });
});
