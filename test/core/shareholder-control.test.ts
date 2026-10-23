// O controle acionário, do Formulário Cadastral da CVM (item B46).
//
// O histórico sai das linhas do FCA de todos os anos, com a data da mudança
// tirada da coluna que a companhia declara quando ela é plausível; e a
// avaliação de uma estatal ganha a ressalva sem mudar o preço justo.
import { describe, expect, it } from 'vitest';

import {
  CapmInputs,
  DateTime,
  FundamentalsSnapshot,
  ShareholderControl,
  ShareholderControlHistory,
  type ShareholderControlFiling,
  Ticker,
  ValuationCascade,
  ValuationCaveat,
  ValuationInputs,
  type ValuationResult,
} from '../../src/core';
import { day, expectDate } from './helpers';

const fca = (year: number, shareKind: string, date: DateTime | null = null): ShareholderControlFiling => ({
  reference: day(year, 1, 1),
  species: shareKind,
  speciesDate: date,
});

const ticker = Ticker.parse('ESTA3');

const year = (y: number, e: number): FundamentalsSnapshot =>
  new FundamentalsSnapshot({
    ticker,
    fiscalPeriodEnd: day(y, 12, 31),
    totalRevenue: 10000 * e,
    ebit: 1400 * e,
    ebitda: 1900 * e,
    netIncome: 700 * e,
    incomeBeforeTax: 1000 * e,
    incomeTaxExpense: -300 * e,
    interestExpense: 120,
    earningsPerShare: (0.7 * e) / 3,
    cash: 500,
    shortTermDebt: 400,
    longTermDebt: 1600,
    totalStockholderEquity: 6000 * e,
    bookValuePerShare: 2.0 * e,
    nopat: 924 * e,
    sharesOutstanding: 3000,
    sharesOutstandingAsOf: 3000,
    marketCap: 30000,
  });

function evaluate(stateOwned: boolean): ValuationResult {
  const fundamentals: FundamentalsSnapshot[] = [];
  for (let i = 15; i >= 0; i--) fundamentals.push(year(2025 - i, Math.pow(1.05, 15 - i)));
  const r = ValuationCascade.evaluate(
    new ValuationInputs({
      ticker,
      asOf: day(2026, 9, 9),
      fundamentals,
      marketPrice: 10.0,
      capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.012 }),
      declaredTerminalRiskFreeRate: 0.094,
      stateControlled: stateOwned,
    }),
  );
  expect(r.isOk, r.failureOrNull?.message).toBe(true);
  return r.unwrap();
}

describe('a espécie do FCA', () => {
  it('holding é a mesma espécie, e texto vazio não diz nada', () => {
    expect(ShareholderControl.fromFca('Estatal Holding')).toBe(ShareholderControl.state);
    expect(ShareholderControl.fromFca('Privado Holding')).toBe(ShareholderControl.private);
    expect(ShareholderControl.fromFca('Estrangeiro')).toBe(ShareholderControl.foreign);
    expect(ShareholderControl.fromFca('')).toBeNull();
  });
});

describe('o histórico', () => {
  it('a privatização vale do dia declarado pela espécie nova', () => {
    // O caso da Eletrobras: os formulários de 2022 a 2024 declaram a data da
    // fundação, e os de 2025 e 2026, o dia da privatização.
    const h = ShareholderControlHistory.fromFilings([
      fca(2020, 'Estatal Holding', day(1962, 6, 11)),
      fca(2021, 'Estatal Holding', day(1971, 1, 28)),
      fca(2022, 'Privado Holding', day(1971, 1, 28)),
      fca(2023, 'Privado Holding', day(1971, 1, 28)),
      fca(2025, 'Privado Holding', day(2022, 6, 17)),
    ]);
    expect(h).toHaveLength(2);
    expectDate(h[h.length - 1]!.since, DateTime.utc(2022, 6, 17));
    expect(ShareholderControlHistory.at(h, day(2022, 3, 31))).toBe(ShareholderControl.state);
    expect(ShareholderControlHistory.at(h, day(2022, 6, 30))).toBe(ShareholderControl.private);
  });

  it('sem data plausível, a mudança vale da referência do formulário novo', () => {
    const h = ShareholderControlHistory.fromFilings([fca(2021, 'Estatal'), fca(2022, 'Privado')]);
    expectDate(h[h.length - 1]!.since, DateTime.utc(2022, 1, 1));
  });

  it('antes do primeiro formulário não há espécie', () => {
    const h = ShareholderControlHistory.fromFilings([fca(2015, 'Estatal')]);
    expect(ShareholderControlHistory.at(h, day(2014, 12, 31))).toBeNull();
    expect(ShareholderControlHistory.at(h, day(2015, 1, 1))).toBe(ShareholderControl.state);
  });

  it('o pacote volta igual, e versão estranha é recusada', () => {
    const h = new Map([
      ['AXIA', ShareholderControlHistory.fromFilings([fca(2021, 'Estatal'), fca(2022, 'Privado', day(2022, 6, 17))])],
    ]);
    const json = ShareholderControlHistory.encode(h, { generatedAt: day(2026, 9, 14) });
    const parsed = ShareholderControlHistory.decode(json)!;
    expectDate(parsed.generatedAt, DateTime.utc(2026, 9, 14));
    expect(parsed.byIssuer.get('AXIA')!.map((p) => p.since.toIso8601String())).toEqual([
      DateTime.utc(2021, 1, 1).toIso8601String(),
      DateTime.utc(2022, 6, 17).toIso8601String(),
    ]);
    expect(ShareholderControlHistory.decode({ ...json, versao: 99 })).toBeNull();
  });
});

describe('a avaliação', () => {
  it('a estatal ganha a ressalva e o aviso, e o preço não muda', () => {
    const privatelyOwned = evaluate(false);
    const stateOwned = evaluate(true);
    expect(stateOwned.fairValue).toEqual(privatelyOwned.fairValue);
    expect(stateOwned.diagnostics!.caveats).toContain(ValuationCaveat.stateControl);
    expect(privatelyOwned.diagnostics!.caveats).not.toContain(ValuationCaveat.stateControl);
    expect(stateOwned.warnings.filter((w) => w.includes('controle estatal'))).toHaveLength(1);
    expect(privatelyOwned.warnings.filter((w) => w.includes('controle estatal'))).toEqual([]);
  });
});
