// A cópia de `ValuationInputs` preserva todo campo (item B27).
//
// Cada cópia repetia a lista de campos à mão, e três campos novos se perderam
// em todas: `withProjectionYears` — que a concessão que acaba dentro da
// projeção usa em produção — deixava a concessionária sem a segunda leitura por
// múltiplos. **Ao acrescentar um campo a `ValuationInputs`, acrescente-o aqui**:
// o teste preenche todos com valores fora do padrão e confere cada um.
import { expect, it } from 'vitest';

import {
  CapmInputs,
  CashTiming,
  CurveVertex,
  FundamentalsSnapshot,
  Money,
  MultipleKind,
  OfficialShareCount,
  PeerMultiple,
  PeerMultipleSet,
  PricePoint,
  PriceSeries,
  ReinvestmentPolicy,
  ScenarioTranslation,
  ShareIssue,
  Ticker,
  ValuationInputs,
  ValuationLane,
  YieldCurve,
} from '../../src/core';
import { day, expectClose } from './helpers';

const t = Ticker.parse('ABCD3');

const snap = new FundamentalsSnapshot({ ticker: t, fiscalPeriodEnd: day(2025, 12, 31), netIncome: 100 });
const curve = YieldCurve.of(day(2026, 9, 1), [
  new CurveVertex(1, 0.14),
  new CurveVertex(5, 0.135),
  new CurveVertex(10, 0.13),
])!;
const prices = new PriceSeries({
  ticker: t,
  points: [new PricePoint({ date: day(2026, 9, 1), close: 10, volume: 100 })],
});
const pairs = new PeerMultipleSet({
  byKind: new Map([[MultipleKind.priceToEarnings, new PeerMultiple({ median: 9, peers: 5, group: 'g' })]]),
  asOf: day(2026, 9, 1),
});
const official = new OfficialShareCount({ total: 1000, asOf: day(2026, 9, 1) });
const capm = new CapmInputs({ riskFreeRate: 0.14, beta: 1.2, marketPremium: 0.06 });
const issuances = [new ShareIssue({ date: day(2026, 3, 1), amount: Money.fromReais(1e6), shares: 100000 })];

/** Todo campo preenchido, e nenhum com o valor padrão. */
const complete = new ValuationInputs({
  ticker: t,
  asOf: day(2026, 9, 9),
  fundamentals: [snap],
  marketPrice: 12,
  capm,
  marginOfSafety: 0.2,
  projectionYears: 12,
  perpetualGrowthCap: 0.07,
  sectorKey: 'energia',
  industry: 'transmissão',
  inflation: 0.045,
  declaredTerminalRiskFreeRate: 0.095,
  riskFreeCurve: curve,
  officialShares: official,
  prices,
  isDistressed: true,
  stateControlled: true,
  terminalReturnOverride: 0.13,
  laneOverride: ValuationLane.shareholder,
  growthOverride: 0.06,
  baseFactorOverride: 1.1,
  unleveredBeta: 0.8,
  reinvestmentOverride: ReinvestmentPolicy.realGrowth,
  cashTimingOverride: CashTiming.endOfYear,
  concessionEnd: day(2030, 1, 1),
  dividendsInBeta: 7,
  creditReferenceRiskFree: 0.15,
  declaredSharesPerUnit: 5,
  terminalBetaWeightOverride: 0.5,
  terminalLeverageOverride: 0.4,
  betaWindowYears: 3.5,
  peerMultiples: pairs,
  minorityEquityValue: 321,
  scenarioTranslation: ScenarioTranslation.fixedStructure,
  contextNotes: ['nota'],
  shareIssues: issuances,
});

/** Os campos, por nome — para comparar e para dizer qual se perdeu. */
const fields = (i: ValuationInputs): Record<string, unknown> => ({
  ticker: i.ticker,
  asOf: i.asOf,
  fundamentals: i.fundamentals,
  marketPrice: i.marketPrice,
  capm: i.capm,
  marginOfSafety: i.marginOfSafety,
  projectionYears: i.projectionYears,
  perpetualGrowthCap: i.perpetualGrowthCap,
  sectorKey: i.sectorKey,
  industry: i.industry,
  inflation: i.inflation,
  declaredTerminalRiskFreeRate: i.declaredTerminalRiskFreeRate,
  riskFreeCurve: i.riskFreeCurve,
  officialShares: i.officialShares,
  prices: i.prices,
  isDistressed: i.isDistressed,
  stateControlled: i.stateControlled,
  terminalReturnOverride: i.terminalReturnOverride,
  laneOverride: i.laneOverride,
  growthOverride: i.growthOverride,
  baseFactorOverride: i.baseFactorOverride,
  unleveredBeta: i.unleveredBeta,
  reinvestmentOverride: i.reinvestmentOverride,
  cashTimingOverride: i.cashTimingOverride,
  concessionEnd: i.concessionEnd,
  dividendsInBeta: i.dividendsInBeta,
  creditReferenceRiskFree: i.creditReferenceRiskFree,
  declaredSharesPerUnit: i.declaredSharesPerUnit,
  terminalBetaWeightOverride: i.terminalBetaWeightOverride,
  terminalLeverageOverride: i.terminalLeverageOverride,
  betaWindowYears: i.betaWindowYears,
  peerMultiples: i.peerMultiples,
  minorityEquityValue: i.minorityEquityValue,
  scenarioTranslation: i.scenarioTranslation,
  contextNotes: i.contextNotes,
  shareIssues: i.shareIssues,
});

function preserves(copy: ValuationInputs, except: ReadonlySet<string> = new Set()): void {
  const a = fields(complete);
  const b = fields(copy);
  for (const k of Object.keys(a)) {
    if (except.has(k)) continue;
    expect(b[k], `a cópia perdeu \`${k}\``).toEqual(a[k]);
  }
}

it('nenhum campo do teste está no valor padrão', () => {
  // Se um campo ficasse no padrão, a cópia que o perdesse passaria igual.
  const pattern = new ValuationInputs({ ticker: t, asOf: day(2026, 9, 9), fundamentals: [], marketPrice: 12, capm });
  const a = fields(complete);
  const p = fields(pattern);
  // O inventário cobre todo campo da classe: um campo novo fora dele falha aqui.
  expect(Object.keys(a).sort()).toEqual(Object.keys(complete).sort());
  for (const k of Object.keys(a)) {
    if (['ticker', 'asOf', 'marketPrice', 'capm'].includes(k)) continue;
    expect(a[k], `\`${k}\` está no padrão`).not.toEqual(p[k]);
  }
});

it('withProjectionYears preserva todo campo — a concessão em produção', () => {
  const c = complete.withProjectionYears(4);
  expect(c.projectionYears).toBe(4);
  preserves(c, new Set(['projectionYears']));
});

it('withFundamentals troca só a série', () => {
  const newList = [snap, snap];
  const c = complete.withFundamentals(newList);
  expect(c.fundamentals).toBe(newList);
  preserves(c, new Set(['fundamentals']));
});

it('withoutPrices tira só a série de cotações', () => {
  const c = complete.withoutPrices();
  expect(c.prices).toBeNull();
  preserves(c, new Set(['prices']));
});

it('withPeerMultiples troca só os pares', () => {
  const c = complete.withPeerMultiples(null);
  expect(c.peerMultiples).toBeNull();
  preserves(c, new Set(['peerMultiples']));
});

it('withContextNotes troca só as ressalvas', () => {
  const c = complete.withContextNotes(['a', 'b']);
  expect(c.contextNotes).toEqual(['a', 'b']);
  preserves(c, new Set(['contextNotes']));
});

it('withOverrides troca só as seis imposições', () => {
  const c = complete.withOverrides({ lane: ValuationLane.firm });
  expect(c.laneOverride).toBe(ValuationLane.firm);
  expect(c.terminalReturnOverride).toBeNull();
  expect(c.cashTimingOverride).toBeNull();
  preserves(
    c,
    new Set([
      'laneOverride',
      'terminalReturnOverride',
      'growthOverride',
      'baseFactorOverride',
      'reinvestmentOverride',
      'cashTimingOverride',
    ]),
  );
});

it('withRiskFreeShift desloca as taxas e preserva o resto', () => {
  const c = complete.withRiskFreeShift(0.01);
  expectClose(c.capm.riskFreeRate, 0.15, 1e-12);
  expectClose(c.declaredTerminalRiskFreeRate!, 0.105, 1e-12);
  expectClose(c.riskFreeCurve!.vertices[0]!.rate, 0.15, 1e-12);
  preserves(c, new Set(['capm', 'declaredTerminalRiskFreeRate', 'riskFreeCurve']));
});
