import { describe, expect, it } from 'vitest';

import { DateTime, FieldSource, FundamentalsMerge, FundamentalsProvenance, FundamentalsSnapshot, Ticker } from '../../src/core';
import { day, expectClose, expectDate } from './helpers';

const t = Ticker.parse('TEST3');

type Fields = Partial<ConstructorParameters<typeof FundamentalsSnapshot>[0]>;
const snap = (fiscalPeriodEnd: DateTime, fields: Fields = {}): FundamentalsSnapshot =>
  new FundamentalsSnapshot({ ticker: t, fiscalPeriodEnd, ...fields });

const cvm = (): FundamentalsSnapshot =>
  snap(day(2024, 12, 31), {
    receiptDate: day(2025, 2, 19),
    totalRevenue: 1000,
    ebit: 250,
    netIncome: 140,
    totalAssets: 5000,
    totalStockholderEquity: 2000,
    treasuryShares: 1e6,
    // A CVM não publica mercado.
  });

const market = (): FundamentalsSnapshot =>
  snap(day(2024, 12, 31), {
    totalRevenue: 999, // divergente de propósito
    ebit: 240,
    netIncome: 138,
    ebitda: 300, // só o mercado tem
    marketCap: 9e9,
    sharesOutstanding: 1e9,
    enterpriseToEbitda: 7.5,
  });

const cvmWithoutEquity = (): FundamentalsSnapshot => snap(day(2024, 12, 31), { netIncome: 140 });
const market2 = (): FundamentalsSnapshot =>
  snap(day(2024, 12, 31), { bookValuePerShare: 6.18, sharesOutstandingAsOf: 234178210 });

describe('Mescla', () => {
  it('a CVM vence no que ela publica', () => {
    const m = FundamentalsMerge.merge({ cvm: cvm(), market: market() })!;
    expect(m.snapshot.totalRevenue).toBe(1000);
    expect(m.snapshot.ebit).toBe(250);
    expect(m.snapshot.netIncome).toBe(140);
    expect(m.provenance.of('netIncome')).toBe(FieldSource.cvm);
    expect(m.provenance.of('totalRevenue')).toBe(FieldSource.cvm);
  });

  it('o mercado preenche o que a CVM não tem', () => {
    const m = FundamentalsMerge.merge({ cvm: cvm(), market: market() })!;
    expect(m.snapshot.ebitda).toBe(300);
    expect(m.provenance.of('ebitda')).toBe(FieldSource.market);
  });

  it('exercício de outra data não empresta fluxo — decisão 78', () => {
    // Doze meses até junho de 2025 contra o dezembro de 2024 do mercado.
    const june = snap(DateTime.utc(2025, 6, 30), { receiptDate: DateTime.utc(2025, 8, 10), ebit: 260, netIncome: 150 });
    const december = snap(DateTime.utc(2024, 12, 31), {
      receiptDate: DateTime.utc(2025, 2, 19),
      ebitda: 300,
      interestExpense: -40,
      nopat: 170,
      earningsPerShare: 1.38,
      sharesOutstandingAsOf: 1e8,
      bookValuePerShare: 19.5,
      marketCap: 9e9,
      sharesOutstanding: 1e9,
      enterpriseToEbitda: 7.5,
    });
    const m = FundamentalsMerge.merge({ cvm: june, market: december })!;
    const s = m.snapshot;
    expect(s.interestExpense, 'juros de outra janela no custo da dívida').toBeNull();
    expect(s.nopat, 'o NOPAT sai do EBIT desta janela').toBeNull();
    expect(s.ebitda).toBeNull();
    expect(s.earningsPerShare, 'LPA de outro lucro no árbitro lucro ÷ LPA').toBeNull();
    expect(
      s.sharesOutstandingAsOf,
      'o par por ação do último encerramento é estoque, e é a base de patrimônio da cascata',
    ).toBe(1e8);
    expect(s.bookValuePerShare).toBe(19.5);
    expect(s.marketCap, 'o valor de mercado é de hoje').toBe(9e9);
    expect(s.sharesOutstanding).toBe(1e9);
    expect(s.enterpriseToEbitda).toBe(7.5);
    expect(s.ebit).toBe(260);
    expect(m.provenance.of('interestExpense')).toBe(FieldSource.missing);
    expect(m.provenance.of('marketCap')).toBe(FieldSource.market);
  });

  describe('A base de patrimônio é o PL da CVM — decisão 81', () => {
    it('o VPA é derivado, e o produto devolve o PL da demonstração', () => {
      const c = snap(DateTime.utc(2025, 12, 31), { totalStockholderEquity: 48.25e9 });
      // HAPV3: a base de mercado dava R$ 373 bi.
      const mk = snap(DateTime.utc(2025, 12, 31), { bookValuePerShare: 49.7, sharesOutstandingAsOf: 7.507e9 });
      const m = FundamentalsMerge.merge({ cvm: c, market: mk })!;
      expectClose(m.snapshot.equityBookValue!, 48.25e9, 1e-3);
      expect(m.snapshot.sharesOutstandingAsOf, 'a contagem continua sendo a do mercado — decisão 70').toBe(7.507e9);
      expect(m.provenance.of('bookValuePerShare')).toBe(FieldSource.derived);
    });

    it('no ponto de junho, o PL é o de junho', () => {
      const june = snap(DateTime.utc(2025, 6, 30), { totalStockholderEquity: 2100 });
      const december = snap(DateTime.utc(2024, 12, 31), { bookValuePerShare: 20, sharesOutstandingAsOf: 100 });
      const m = FundamentalsMerge.merge({ cvm: june, market: december })!;
      expectClose(m.snapshot.equityBookValue!, 2100, 1e-9, 'e não os 2.000 de dezembro, que a decisão 78 declarava');
    });

    it('PL negativo continua sem base, como o VPA negativo do mercado', () => {
      const c = snap(DateTime.utc(2025, 12, 31), { totalStockholderEquity: -500 });
      const mk = snap(DateTime.utc(2025, 12, 31), { bookValuePerShare: 3, sharesOutstandingAsOf: 100 });
      const m = FundamentalsMerge.merge({ cvm: c, market: mk })!;
      expect(m.snapshot.equityBookValue).toBeNull();
      expect(m.snapshot.bookValuePerShare).toBe(-5);
    });

    it('sem PL na CVM, o VPA do mercado segue', () => {
      const m = FundamentalsMerge.merge({ cvm: cvmWithoutEquity(), market: market2() })!;
      expect(m.snapshot.bookValuePerShare).toBe(6.18);
      expect(m.provenance.of('bookValuePerShare')).toBe(FieldSource.market);
    });
  });

  it('fevereiro bissexto é a mesma janela', () => {
    expect(FundamentalsMerge.sameWindow(DateTime.utc(2024, 2, 29), DateTime.utc(2024, 2, 28))).toBe(true);
    expect(FundamentalsMerge.sameWindow(DateTime.utc(2024, 6, 30), DateTime.utc(2023, 12, 31))).toBe(false);
  });

  it('a contagem do exercício NUNCA vem da CVM — decisão 70', () => {
    // A escala do campo da CVM varia por declarante: 60,9% em unidades,
    // 34,5% em milhares. Importar o absoluto levou a MILS3 a +14.037%.
    // A ferramenta de ingestão já deixou de preenchê-lo; a regra fica na
    // mescla para que outra montagem não o reintroduza.
    const cvmWithCount = snap(day(2024, 12, 31), {
      sharesOutstandingAsOf: 234178, // em milhares, e errado
      bookValuePerShare: 9999,
    });
    const mk = snap(day(2024, 12, 31), { sharesOutstandingAsOf: 234178210, bookValuePerShare: 6.18 });
    const m = FundamentalsMerge.merge({ cvm: cvmWithCount, market: mk })!;
    expect(m.snapshot.sharesOutstandingAsOf).toBe(234178210);
    expect(m.snapshot.bookValuePerShare).toBe(6.18);
    expect(m.provenance.of('sharesOutstandingAsOf')).toBe(FieldSource.market);
  });

  it('valor de mercado e contagem corrente NUNCA vêm da CVM', () => {
    // Mesmo que a CVM trouxesse — e ela não traz —, estes descrevem o hoje
    // do papel, e não o exercício.
    const cvmWithMarket = snap(day(2024, 12, 31), { marketCap: 1.0, sharesOutstanding: 2.0, enterpriseToEbitda: 3.0 });
    const m = FundamentalsMerge.merge({ cvm: cvmWithMarket, market: market() })!;
    expect(m.snapshot.marketCap).toBe(9e9);
    expect(m.snapshot.sharesOutstanding).toBe(1e9);
    expect(m.snapshot.enterpriseToEbitda).toBe(7.5);
    // Só os que o exemplar de mercado preenche; os demais de
    // `marketOnly` têm teste próprio acima.
    for (const c of ['marketCap', 'sharesOutstanding', 'enterpriseToEbitda']) {
      expect(m.provenance.of(c), c).toBe(FieldSource.market);
    }
  });

  it('a data de recebimento é da CVM', () => {
    const m = FundamentalsMerge.merge({ cvm: cvm(), market: market() })!;
    expectDate(m.snapshot.receiptDate, day(2025, 2, 19));
    expect(m.provenance.of('receiptDate')).toBe(FieldSource.cvm);
  });

  it('campos que só a CVM tem chegam ao resultado', () => {
    const m = FundamentalsMerge.merge({ cvm: cvm(), market: market() })!;
    expect(m.snapshot.totalAssets).toBe(5000);
    expect(m.snapshot.treasuryShares).toBe(1e6);
    expect(m.provenance.of('totalAssets')).toBe(FieldSource.cvm);
  });

  it('fonte única não perde nada, e a procedência diz qual', () => {
    const cvmOnly = FundamentalsMerge.merge({ cvm: cvm() })!;
    expect(cvmOnly.snapshot.netIncome).toBe(140);
    expect(cvmOnly.provenance.of('netIncome')).toBe(FieldSource.cvm);
    expect(cvmOnly.provenance.of('marketCap')).toBe(FieldSource.missing);

    const marketOnlyMerge = FundamentalsMerge.merge({ market: market() })!;
    expect(marketOnlyMerge.snapshot.marketCap).toBe(9e9);
    expect(marketOnlyMerge.provenance.of('marketCap')).toBe(FieldSource.market);
    expect(marketOnlyMerge.provenance.of('totalAssets')).toBe(FieldSource.missing);
  });

  it('sem nenhuma das duas, devolve nulo', () => {
    expect(FundamentalsMerge.merge({})).toBeNull();
  });

  it('campo ausente nas duas fica ausente, e não zero', () => {
    const m = FundamentalsMerge.merge({ cvm: cvm(), market: market() })!;
    expect(m.snapshot.freeCashFlow).toBeNull();
    expect(m.provenance.of('freeCashFlow')).toBe(FieldSource.missing);
  });
});

describe('Procedência', () => {
  it('conta por fonte', () => {
    const c = FundamentalsMerge.merge({ cvm: cvm(), market: market() })!.provenance.count;
    expect(c.get(FieldSource.cvm)).toBeGreaterThan(0);
    expect(c.get(FieldSource.market)).toBeGreaterThan(0);
  });

  it('o mapa é imutável: cópia na construção, e sem escrita no tipo', () => {
    const source = new Map([['x', FieldSource.cvm]]);
    const p = new FundamentalsProvenance(source);
    source.set('y', FieldSource.market);
    expect(p.byField.has('y')).toBe(false);
    const mutate = (): void => {
      // @ts-expect-error — `ReadonlyMap` não expõe `set`: a escrita não compila.
      p.byField.set('y', FieldSource.market);
    };
    expect(typeof mutate).toBe('function');
  });
});
