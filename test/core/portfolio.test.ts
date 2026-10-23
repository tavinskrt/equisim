import { describe, expect, it } from 'vitest';

import {
  Asset,
  ExpectedReturn,
  InvalidInput,
  Money,
  Portfolio,
  PortfolioKind,
  Sector,
  SectorConcentration,
  Ticker,
  ValuationModel,
  ValuationResult,
  Weights,
} from '../../src/core';
import { day, expectClose } from './helpers';

const assetOf = (symbol: string, sectorKey: string): Asset =>
  new Asset({
    ticker: Ticker.parse(symbol),
    name: symbol,
    sector: sectorKey === '' ? Sector.unknown : Sector.fromKey(sectorKey, { label: sectorKey }),
  });

const equalWeighted = (assets: Asset[]) =>
  Portfolio.equalWeighted({ id: 'p', name: 'Principal', kind: PortfolioKind.principal, assets });

describe('Portfolio', () => {
  it('equiponderada distribui 100% sem sobra', () => {
    const portfolio = equalWeighted([
      assetOf('PETR4', 'energia'),
      assetOf('VALE3', 'materiais'),
      assetOf('ITUB4', 'financeiro'),
    ]).unwrap();

    expect(portfolio.hasValidWeights).toBe(true);
    expectClose(Weights.sum(portfolio.weights), 1.0, 1e-15);
  });

  it('respeita o teto de 15 ativos', () => {
    const assets = Array.from({ length: 16 }, (_, i) => assetOf(`AAAA${i}`, 'financeiro'));
    const result = equalWeighted(assets);
    expect(result.isErr).toBe(true);
    expect(result.failureOrNull).toBeInstanceOf(InvalidInput);
    expect(result.failureOrNull!.message).toContain('15');
  });

  it('aceita exatamente 15 ativos', () => {
    const assets = Array.from({ length: 15 }, (_, i) => assetOf(`AAAA${i}`, 'financeiro'));
    expect(equalWeighted(assets).isOk).toBe(true);
  });

  it('rejeita ativos duplicados', () => {
    const result = equalWeighted([assetOf('PETR4', 'energia'), assetOf('PETR4', 'energia')]);
    expect(result.isErr).toBe(true);
  });

  it('adicionar e remover reequipondera mantendo 100%', () => {
    let portfolio = equalWeighted([assetOf('PETR4', 'energia'), assetOf('VALE3', 'materiais')]).unwrap();

    portfolio = portfolio.add(assetOf('ITUB4', 'financeiro')).unwrap();
    expect(portfolio.length).toBe(3);
    expect(Weights.sumsToOne(portfolio.weights)).toBe(true);

    portfolio = portfolio.remove(Ticker.parse('PETR4')).unwrap();
    expect(portfolio.length).toBe(2);
    expect(Weights.sumsToOne(portfolio.weights)).toBe(true);
  });

  it('não adiciona ativo já presente', () => {
    const portfolio = equalWeighted([assetOf('PETR4', 'energia')]).unwrap();
    expect(portfolio.add(assetOf('PETR4', 'energia')).isErr).toBe(true);
  });
});

describe('Concentração setorial', () => {
  it('alerta a partir de dois ativos no mesmo setor', () => {
    const portfolio = equalWeighted([
      assetOf('ITUB4', 'financeiro'),
      assetOf('BBAS3', 'financeiro'),
      assetOf('PETR4', 'energia'),
    ]).unwrap();

    const report = SectorConcentration.analyze(portfolio);
    expect(report.hasAlert).toBe(true);
    expect(report.concentrated).toHaveLength(1);
    expect(report.concentrated[0]!.sector.key).toBe('financeiro');
    expect(report.concentrated[0]!.count).toBe(2);
    expectClose(report.concentrated[0]!.weight, 2 / 3, 1e-9);
  });

  it('sem concentração não há alerta', () => {
    const portfolio = equalWeighted([
      assetOf('ITUB4', 'financeiro'),
      assetOf('PETR4', 'energia'),
      assetOf('VALE3', 'materiais'),
    ]).unwrap();
    expect(SectorConcentration.analyze(portfolio).hasAlert).toBe(false);
  });

  it('ativo sem classificação setorial não conta para a concentração', () => {
    const portfolio = equalWeighted([assetOf('XXXX3', ''), assetOf('YYYY3', '')]).unwrap();
    expect(SectorConcentration.analyze(portfolio).hasAlert).toBe(false);
  });
});

describe('Retorno esperado — unidade comparável com a meta', () => {
  it('anualiza upside pelo horizonte de convergência', () => {
    // +21% de upside em 24 meses ⇒ 10% ao ano.
    const annual = ExpectedReturn.annualizedFromUpside(0.21, { horizonMonths: 24 });
    expectClose(annual, 0.1, 1e-9);
  });

  it('horizonte de 12 meses preserva o upside', () => {
    const annual = ExpectedReturn.annualizedFromUpside(0.4, { horizonMonths: 12 });
    expectClose(annual, 0.4, 1e-12);
  });

  it('retorno esperado é a convergência de preço, e nada além dela', () => {
    // Sem provento no modelo, o anual não pode divergir da convergência: um
    // segundo termo aqui seria retorno que nenhuma outra tela apura.
    const annual = ExpectedReturn.annualizedFromUpside(0.2, { horizonMonths: 12 });
    expectClose(annual, 0.2, 1e-12);
  });

  it('carteira reporta cobertura parcial', () => {
    const portfolio = equalWeighted([assetOf('PETR4', 'energia'), assetOf('VALE3', 'materiais')]).unwrap();

    const valuations = new Map([
      [
        Ticker.parse('PETR4'),
        new ValuationResult({
          ticker: Ticker.parse('PETR4'),
          asOf: day(2026, 8, 19),
          model: ValuationModel.dcfFcff,
          fairValue: Money.fromReais(60),
          marketPrice: Money.fromReais(50),
          discountRate: 0.12,
        }),
      ],
    ]);

    const coverage = ExpectedReturn.coverage({ portfolio, valuations });
    expectClose(coverage, 0.5, 1e-9);
  });
});

describe('Retorno esperado transversal — projeção para otimização', () => {
  const upsidesOf = (m: Record<string, number>): Map<Ticker, number> =>
    new Map(Object.entries(m).map(([k, v]) => [Ticker.parse(k), v]));
  const keOf = (m: Record<string, number>): Map<Ticker, number> => upsidesOf(m);

  const cdi = 0.1415;
  const premium = 0.055;

  it('o ativo mediano da seção recebe a âncora, e nada além dela', () => {
    const r = ExpectedReturn.crossSection({
      upsides: upsidesOf({ AAAA3: 0.0 }),
      spotRiskFree: cdi,
      reference: [-0.6, -0.3, 0.0, 0.3, 0.6],
    });
    expectClose(r.get(Ticker.parse('AAAA3'))!.z, 0.0, 1e-12);
    expectClose(r.get(Ticker.parse('AAAA3'))!.expected, cdi, 1e-12);
    expect(r.get(Ticker.parse('AAAA3'))!.anchoredOnCostOfEquity).toBe(false);
  });

  it('seção colapsada num ponto não produz NaN', () => {
    // `z = (u − mediana) / escala` divide por zero se a escala for zero, e
    // `0/0` é NaN — que atravessa `clamp` e chega à tela. Não acontece
    // porque `Inference.scaledMad` devolve **nulo**, e não zero, quando a
    // dispersão some. O teste existe para que isso continue verdade.
    const ke = 0.1956;
    const r = ExpectedReturn.crossSection({
      upsides: upsidesOf({ AAAA3: 0.2 }),
      spotRiskFree: cdi,
      costOfEquity: keOf({ AAAA3: ke }),
      reference: [0.2, 0.2, 0.2, 0.2, 0.2],
    });
    const x = r.get(Ticker.parse('AAAA3'))!;
    expect(x.z).toBe(0.0);
    expect(Number.isNaN(x.z)).toBe(false);
    expect(Number.isFinite(x.expected)).toBe(true);
    expectClose(x.expected, ke, 1e-12);
  });

  it('seção de um ponto só também não produz NaN', () => {
    const r = ExpectedReturn.crossSection({ upsides: upsidesOf({ AAAA3: 0.2 }), spotRiskFree: cdi });
    expect(Number.isFinite(r.get(Ticker.parse('AAAA3'))!.expected)).toBe(true);
  });

  it('A ÂNCORA É O CUSTO DO CAPITAL PRÓPRIO, e não o CDI', () => {
    // Ancorar no CDI dava ao ativo mediano da seção um retorno esperado
    // **sem prêmio de risco algum**: uma carteira de ações centrada na seção
    // esperava exatamente a renda fixa. Medido em 11/09/2026 sobre os 127
    // avaliados: o mediano ia de 14,09% — o próprio CDI — para 20,45%, e a
    // carteira igualmente ponderada subia 5,97 p.p. Decisão 58.
    const ke = 0.1956;
    const r = ExpectedReturn.crossSection({
      upsides: upsidesOf({ AAAA3: 0.0 }),
      spotRiskFree: cdi,
      costOfEquity: keOf({ AAAA3: ke }),
      reference: [-0.6, -0.3, 0.0, 0.3, 0.6],
    });
    const x = r.get(Ticker.parse('AAAA3'))!;
    expectClose(x.z, 0.0, 1e-12);
    expectClose(x.expected, ke, 1e-12);
    expect(x.anchoredOnCostOfEquity).toBe(true);
    expectClose(x.expected - cdi, ke - cdi, 1e-12, 'a diferença entre as duas âncoras é o prêmio de risco inteiro');
  });

  it('Ke igual ao CDI ainda é âncora de Ke, e não recuo', () => {
    // A bandeira sai de **haver** `Ke`, e não de comparar as duas âncoras:
    // beta zero produz `Ke == CDI`, e compará-los declararia recuo onde não
    // houve. Comparação de `double` por igualdade, ainda por cima.
    const r = ExpectedReturn.crossSection({
      upsides: upsidesOf({ AAAA3: 0.0 }),
      spotRiskFree: cdi,
      costOfEquity: keOf({ AAAA3: cdi }),
      reference: [-0.6, -0.3, 0.0, 0.3, 0.6],
    });
    expect(r.get(Ticker.parse('AAAA3'))!.anchoredOnCostOfEquity).toBe(true);
  });

  it('cada ativo é ancorado no próprio Ke', () => {
    // Dois ativos no mesmo ponto da seção e com betas diferentes não têm o
    // mesmo retorno esperado — é o que a âncora única apagava.
    const r = ExpectedReturn.crossSection({
      upsides: upsidesOf({ AAAA3: 0.0, BBBB3: 0.0 }),
      spotRiskFree: cdi,
      costOfEquity: keOf({ AAAA3: 0.17, BBBB3: 0.25 }),
      reference: [-0.6, -0.3, 0.0, 0.3, 0.6],
    });
    expectClose(r.get(Ticker.parse('AAAA3'))!.expected, 0.17, 1e-12);
    expectClose(r.get(Ticker.parse('BBBB3'))!.expected, 0.25, 1e-12);
  });

  it('sem Ke utilizável, recua para o CDI e declara', () => {
    const r = ExpectedReturn.crossSection({
      upsides: upsidesOf({ AAAA3: 0.0, BBBB3: 0.0, CCCC3: 0.0 }),
      spotRiskFree: cdi,
      costOfEquity: keOf({
        AAAA3: Number.NaN,
        BBBB3: -0.05,
        // CCCC3 não aparece no mapa.
      }),
      reference: [-0.6, -0.3, 0.0, 0.3, 0.6],
    });
    for (const t of ['AAAA3', 'BBBB3', 'CCCC3']) {
      const x = r.get(Ticker.parse(t))!;
      expectClose(x.expected, cdi, 1e-12, t);
      expect(x.anchoredOnCostOfEquity, t).toBe(false);
    }
  });

  it('preserva a ordenação do potencial', () => {
    const r = ExpectedReturn.crossSection({
      upsides: upsidesOf({ AAAA3: -0.8, BBBB3: -0.4, CCCC3: 0.0, DDDD3: 0.5 }),
      spotRiskFree: cdi,
    });
    const sortedEntries = ['AAAA3', 'BBBB3', 'CCCC3', 'DDDD3'].map((t) => r.get(Ticker.parse(t))!.expected);
    for (let i = 1; i < sortedEntries.length; i++) {
      expect(sortedEntries[i]).toBeGreaterThan(sortedEntries[i - 1]!);
    }
  });

  it('não propaga retorno negativo, que é o ponto do estimador', () => {
    // Pela anualização, −95% de potencial em 36 meses dá −63,2% ao ano — e um
    // otimizador de média-variância alimentado com isso não aloca no ativo,
    // ele foge dele. A ordenação é o que a avaliação sustenta; o nível, não.
    expect(ExpectedReturn.annualizedFromUpside(-0.95)).toBeLessThan(-0.6);

    const r = ExpectedReturn.crossSection({
      upsides: upsidesOf({ RUIM3: -0.95 }),
      spotRiskFree: cdi,
      reference: [-0.95, -0.8, -0.65, -0.4, -0.15, 0.4, 4.8],
    });
    const bad = r.get(Ticker.parse('RUIM3'))!;
    expect(bad.expected).toBeGreaterThan(0);
    expect(bad.floored).toBe(false);
    expect(bad.expected).toBeLessThan(cdi);
  });

  it('a cauda é confinada, e o teto é o do escore', () => {
    // Distribuição dos 120 avaliados: a cauda direita vai a +477,3%. Sem
    // teto, um ativo sozinho definiria o retorno esperado da carteira.
    const r = ExpectedReturn.crossSection({
      upsides: upsidesOf({ CAUD3: 4.773 }),
      spotRiskFree: cdi,
      reference: [-0.95, -0.8, -0.65, -0.4, -0.15, 0.4, 4.773],
    });
    const tail = r.get(Ticker.parse('CAUD3'))!;
    expectClose(tail.z, ExpectedReturn.defaultZCap, 1e-12);
    expectClose(tail.expected, cdi + ExpectedReturn.defaultZCap * premium, 1e-12);
  });

  it('seção sem escala estimável devolve a âncora a todos', () => {
    // Dois ativos, ou uma seção colapsada num ponto: não há distância a
    // medir, e inventar prêmio onde a seção não o sustenta seria pior que
    // devolver o CDI.
    const r = ExpectedReturn.crossSection({ upsides: upsidesOf({ AAAA3: -0.5, BBBB3: 0.9 }), spotRiskFree: cdi });
    for (const v of r.values()) {
      expect(v.z).toBe(0.0);
      expectClose(v.expected, cdi, 1e-12);
    }
  });
});

describe('ValuationResult', () => {
  it('upside e margem de segurança', () => {
    const valuation = new ValuationResult({
      ticker: Ticker.parse('PETR4'),
      asOf: day(2026, 8, 19),
      model: ValuationModel.dcfFcff,
      fairValue: Money.fromReais(100),
      marketPrice: Money.fromReais(80),
      discountRate: 0.12,
      marginOfSafety: 0.2,
    });
    expectClose(valuation.upside, 0.25, 1e-9);
    expectClose(valuation.safetyPrice.reais, 80.0, 1e-9);
    expect(valuation.isUndervalued).toBe(true);
  });

  it('withWarnings acrescenta a ressalva e não muda número nenhum', () => {
    const base = new ValuationResult({
      ticker: Ticker.parse('PETR4'),
      asOf: day(2026, 8, 19),
      model: ValuationModel.dcfFcff,
      fairValue: Money.fromReais(100),
      marketPrice: Money.fromReais(80),
      discountRate: 0.12,
      marginOfSafety: 0.2,
      warnings: ['da cascata'],
    });
    const withInput = base.withWarnings(['sem a CVM']);
    expect(withInput.warnings).toEqual(['da cascata', 'sem a CVM']);
    expect(withInput.fairValue.equals(base.fairValue)).toBe(true);
    expect(withInput.discountRate).toBe(base.discountRate);
    expect(withInput.marginOfSafety).toBe(base.marginOfSafety);
    expect(base.withWarnings([])).toBe(base);
    // A lista não modificável do Dart é o `Object.freeze` daqui: a escrita
    // lança em vez de passar em silêncio.
    expect(() => (withInput.warnings as string[]).push('x')).toThrow(TypeError);
  });
});
