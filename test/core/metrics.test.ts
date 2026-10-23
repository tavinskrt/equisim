import { describe, expect, it } from 'vitest';

import {
  BetaCalculator,
  CashFlow,
  InsufficientData,
  InvalidInput,
  Money,
  type PairedReturns,
  PairedReturnsBuilder,
  Returns,
  RiskMetrics,
  WealthPath,
} from '../../src/core';
import { day, expectClose } from './helpers';

/**
 * Par de retornos montado como a produção monta: um período por vez, pelo
 * acumulador — o desalinhamento não é exprimível.
 */
function pair(asset: readonly number[], market: readonly number[]): PairedReturns {
  const b = new PairedReturnsBuilder();
  for (let i = 0; i < asset.length; i++) b.add({ asset: asset[i]!, market: market[i]! });
  return b.build();
}

const path = (values: number[], externalFlows: number[]): WealthPath => WealthPath.of({ values, externalFlows }).unwrap();
const flow = (y: number, m: number, d: number, reais: number): CashFlow =>
  new CashFlow({ date: day(y, m, d), amount: Money.fromReais(reais) });

describe('TWR — retorno ponderado pelo tempo', () => {
  it('neutraliza o aporte: o salto de caixa não vira retorno', () => {
    // Dia 0: R$ 100 aportados.
    // Dia 1: sobe para R$ 110 → +10%.
    // Dia 2: aporta R$ 100 e fecha em R$ 231 → (231−100)/110 − 1 = +19,0909%.
    // TWR = 1,10 × 1,190909… − 1 = 31% exatos.
    expectClose(Returns.timeWeighted(path([100, 110, 231], [100, 0, 100])), 0.31, 1e-12);
  });

  it('sem aportes, TWR coincide com a variação simples', () => {
    expectClose(Returns.timeWeighted(path([100, 120, 150], [100, 0, 0])), 0.5, 1e-12);
  });

  it('índice base 100 acompanha o TWR', () => {
    const index = Returns.timeWeightedIndex(path([100, 110, 231], [100, 0, 100]));
    expect(index[0]).toBe(100.0);
    expectClose(index[index.length - 1]!, 131.0, 1e-10);
  });

  it('um aporte gigante não distorce o retorno medido', () => {
    // Carteira parada em R$ 100 recebe R$ 10.000 e continua parada:
    // o retorno tem de ser zero, não +9.900%.
    expectClose(Returns.timeWeighted(path([100, 10100, 10100], [100, 10000, 0])), 0.0, 1e-12);
  });
});

describe('XIRR — retorno ponderado pelo dinheiro', () => {
  it('caso de um ano exato devolve a taxa nominal', () => {
    const result = Returns.extendedIrr([flow(2024, 1, 1, -1000), flow(2024, 12, 31, 1100)]);
    expect(result.isOk).toBe(true);
    expectClose(result.unwrap(), 0.1, 1e-6);
  });

  it('distingue-se do TWR quando o aporte é bem cronometrado', () => {
    // Aportes iguais, mas o segundo entra logo antes de uma alta.
    const result = Returns.extendedIrr([flow(2024, 1, 1, -1000), flow(2024, 7, 1, -1000), flow(2025, 1, 1, 2400)]);
    expect(result.isOk).toBe(true);
    expect(result.unwrap()).toBeGreaterThan(0.0);
  });

  it('exige fluxos de sinais opostos', () => {
    const result = Returns.extendedIrr([flow(2024, 1, 1, -100), flow(2024, 6, 1, -100)]);
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull).toBeInstanceOf(InvalidInput);
  });
});

describe('RiskMetrics', () => {
  it('curva estritamente crescente não tem drawdown', () => {
    expect(RiskMetrics.maxDrawdownOf([100, 110, 120, 130])).toBe(0.0);
  });

  it('drawdown mede pico a vale, não início a fim', () => {
    // Sobe a 200, cai a 100 (−50%), recupera a 150.
    expectClose(RiskMetrics.maxDrawdownOf([100, 200, 100, 150]), -0.5, 1e-12);
  });

  it('volatilidade usa desvio amostral e anualiza por raiz de 252', () => {
    // Desvio amostral de ±1% com média zero ≈ 0,010954; × √252 ≈ 0,1739.
    expectClose(RiskMetrics.annualizedVolatility([0.01, -0.01, 0.01, -0.01, 0.01, -0.01]), 0.1739, 1e-3);
  });

  it('série constante tem volatilidade e Sharpe nulos', () => {
    const metrics = RiskMetrics.fromIndex({ twrIndex: [100, 100, 100, 100], cagr: 0.0, riskFreeRate: 0.0 });
    expect(metrics.volatility).toBe(0.0);
    expect(metrics.sharpe).toBe(0.0);
    expect(metrics.maxDrawdown).toBe(0.0);
  });

  it('Sortino ignora a volatilidade de alta', () => {
    expect(RiskMetrics.annualizedDownsideDeviation([0.02, 0.03, 0.01, 0.04])).toBe(0.0);
  });

  it('Sharpe desconta a taxa livre de risco observada', () => {
    const index = [100, 101, 102, 103, 104, 105];
    const metrics = RiskMetrics.fromIndex({
      twrIndex: index,
      cagr: 0.2,
      riskFreeRate: 0.094, // CDI observado, não constante arbitrária
    });
    expect(metrics.sharpe).toBeGreaterThan(0);
    const withoutRiskFree = RiskMetrics.fromIndex({ twrIndex: index, cagr: 0.2, riskFreeRate: 0.0 });
    expect(withoutRiskFree.sharpe).toBeGreaterThan(metrics.sharpe);
  });
});

describe('Beta', () => {
  const market = Array.from({ length: 60 }, (_, i) => ((i % 5) - 2) * 0.01);

  it('ativo idêntico ao mercado tem beta 1 e correlação 1', () => {
    const result = BetaCalculator.estimate({ returns: pair(market, market) });
    expect(result.isOk).toBe(true);
    expectClose(result.unwrap().beta, 1.0, 1e-12);
    expectClose(result.unwrap().correlation, 1.0, 1e-12);
  });

  it('ativo com o dobro da amplitude tem beta 2', () => {
    const result = BetaCalculator.estimate({ returns: pair(market.map((r) => r * 2), market) });
    expectClose(result.unwrap().beta, 2.0, 1e-12);
  });

  it('exige observações suficientes', () => {
    const result = BetaCalculator.estimate({ returns: pair([0.01, 0.02], [0.01, 0.02]) });
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull).toBeInstanceOf(InsufficientData);
  });

  it('trajetória de patrimônio desalinhada também não é construtível', () => {
    // O `ArgumentError` que `Returns.timeWeighted` lançava — único `throw`
    // de validação num pacote que devolve `Result` — deixou de existir.
    const p = WealthPath.of({ values: [100, 110, 120], externalFlows: [100, 0] });
    expect(p.isErr).toBe(true);
    expect(p.failureOrNull).toBeInstanceOf(InvalidInput);
  });

  it('pareia séries com pregões desencontrados', () => {
    const aligned = BetaCalculator.alignReturns({
      assetDates: [day(2024, 1, 2), day(2024, 1, 3), day(2024, 1, 4)],
      assetIndex: [100, 110, 121],
      marketDates: [day(2024, 1, 2), day(2024, 1, 4)], // mercado não negociou dia 3
      marketIndex: [100, 121],
    });
    expect(aligned.asset.length).toBe(1);
    expect(aligned.market.length).toBe(1);
    expectClose(aligned.asset[0]!, 0.21, 1e-12);
  });
});
