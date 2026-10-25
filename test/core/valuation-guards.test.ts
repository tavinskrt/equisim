/**
 * Testes das portas e guardas introduzidas pela decisão 25.
 *
 * Cada caso reproduz a **forma** de um ativo real da calibragem, com os
 * números que motivaram a regra. É o que impede que um limiar volte a ser
 * ajustado sem que o motivo original seja reencontrado.
 */
import { afterEach, describe, expect, it } from 'vitest';

import {
  type AuditEvent,
  AuditRecorder,
  CapitalSeries,
  CapmInputs,
  FundamentalsSnapshot,
  GrowthGuards,
  Inference,
  Ticker,
  ValuationCascade,
  ValuationInputs,
  ValuationLane,
  ValuationParameters,
  CyclicalSectors,
  EligibilityGate,
  IneligibilityReason,
  PriceSeries,
  PricePoint,
  Duration,
  ValuationModel,
  ValuationResult,
  DcfAssumptions,
  DcfCalculator,
  CashTiming,
  type DcfOutcome,
  type YearExcess,
  MoatBlock,
  ExpectedReturn,
  MarketAnchors,
  OfficialShareCount,
  QuotedSharesSource,
  ValuationDiagnostics,
  ValuationCaveat,
  Money,
  CostOfCapital,
  toStringAsFixed,
  PointInTimeView,
  ConcessionSectors,
  type Result,
  str,
  PrepareValuationInputs,
  ScenarioBand,
  ScenarioTranslation,
  ReinvestmentPolicy,
} from '../../src/core';
import { day, expectClose, expectNotClose } from './helpers';

/** Potência de expoente inteiro, usada pelos testes de persistência. */
const pow = (base: number, exponent: number): number => {
  let r = 1.0;
  for (let i = 0; i < exponent; i++) r *= base;
  return r;
};

const ticker = Ticker.parse('TEST3');

const fiscalYear = (
  year: number,
  o: {
    bookValuePerShare?: number;
    shares?: number;
    profit?: number;
    nopat?: number;
    shortDebt?: number;
    longDebt?: number;
    cash?: number;
  } = {},
): FundamentalsSnapshot =>
  new FundamentalsSnapshot({
    ticker,
    fiscalPeriodEnd: day(year, 12, 31),
    bookValuePerShare: o.bookValuePerShare ?? null,
    sharesOutstandingAsOf: o.shares ?? null,
    sharesOutstanding: o.shares ?? null,
    netIncome: o.profit ?? null,
    nopat: o.nopat ?? null,
    shortTermDebt: o.shortDebt ?? 0,
    longTermDebt: o.longDebt ?? 0,
    cash: o.cash ?? 0,
  });

/** O único elemento de [list] que satisfaz [test] — o `singleWhere` do Dart. */
const single = <T>(list: readonly T[], test: (x: T) => boolean = () => true): T => {
  const found = list.filter(test);
  expect(found).toHaveLength(1);
  return found[0]!;
};

/** Os eventos de uma avaliação com o coletor ligado. */
const captureEvents = (run: () => void): AuditEvent[] => {
  const captured: AuditEvent[] = [];
  AuditRecorder.attach((e) => captured.push(e));
  try {
    run();
  } finally {
    AuditRecorder.detach();
  }
  return captured;
};


describe('Inference — primitivas conferidas contra tabela', () => {
  it('quantil da t de Student bate com a tabela publicada', () => {
    expectClose(Inference.studentT(0.975, 14), 2.1448, 5e-4);
    expectClose(Inference.studentT(0.975, 6), 2.4469, 5e-4);
    expectClose(Inference.studentT(0.95, 10), 1.8125, 5e-4);
    expectClose(Inference.studentT(0.995, 30), 2.75, 5e-4);
  });

  it('R² crítico depende de n, e é isso que condena o limiar fixo', () => {
    // Com n = 8 o corte correto é 0,50; com n = 16, 0,25. Um limiar único é
    // simultaneamente laxo numa ponta e estrito na outra.
    expectClose(Inference.criticalR2(8, 0.05), 0.499, 1e-3);
    expectClose(Inference.criticalR2(16, 0.05), 0.247, 1e-3);
    expect(Inference.criticalR2(8, 0.05)).toBeGreaterThan(Inference.criticalR2(16, 0.05));
  });

  it('MAD escalado resiste a contaminação que derruba o desvio-padrão', () => {
    // Mediana 3, MAD 1 → 1,4826. O ponto em 100 não move a escala robusta.
    expectClose(Inference.scaledMad([1, 2, 3, 4, 100]), 1.4826, 1e-4);
  });
});

describe('Base de capital', () => {
  it('patrimônio usa a contagem de ações do exercício, não a corrente', () => {
    // Forma do BBAS3: bonificação dobra as ações em 2024. Com a contagem
    // corrente aplicada a todos os anos, a série cairia pela metade num
    // degrau que é troca de denominador, não de lucro.
    const before = fiscalYear(2023, { bookValuePerShare: 56.9, shares: 2865417000, profit: 33.1e9 });
    const after = fiscalYear(2024, { bookValuePerShare: 32.1, shares: 5730834000, profit: 29.2e9 });
    expectClose(before.equityBookValue! / 1e9, 163.1, 0.5);
    expectClose(after.equityBookValue! / 1e9, 184.0, 0.5);
    expect(after.equityBookValue!, 'o patrimônio cresceu; foi o valor por ação que se dividiu').toBeGreaterThan(
      before.equityBookValue!,
    );
  });

  it('capital investido soma dívida e subtrai caixa', () => {
    const e = fiscalYear(2025, {
      bookValuePerShare: 10,
      shares: 1000,
      nopat: 900,
      shortDebt: 2000,
      longDebt: 3000,
      cash: 1500,
    });
    expectClose(e.investedCapital, 10 * 1000 + 5000 - 1500, 1e-9);
  });

  it('limpeza é por vizinhança: crescimento real de ordens de magnitude sobrevive', () => {
    // Forma da PRIO3, que multiplicou a base por trinta em oito anos — 1,53x
    // ao ano. Um corte contra a mediana global apagaria os exercícios
    // recentes, os únicos que descrevem a empresa de hoje.
    let bookValuePerShare = 1.0;
    const points: FundamentalsSnapshot[] = [];
    for (let year = 2018; year <= 2025; year++) {
      points.push(fiscalYear(year, { bookValuePerShare, shares: 1000, profit: bookValuePerShare * 100 }));
      bookValuePerShare *= 1.526;
    }
    const series = CapitalSeries.build(points, ValuationLane.shareholder);
    expect(series.length, 'nenhum exercício legítimo foi cortado').toBe(8);
  });

  it('limpeza remove falha pontual da fonte', () => {
    // Forma da ABEV3 em 2012: bookValue de 0,062 contra 2,81 no ano seguinte.
    const series = CapitalSeries.build(
      [
        fiscalYear(2020, { bookValuePerShare: 10, shares: 1000, profit: 100 }),
        fiscalYear(2021, { bookValuePerShare: 0.05, shares: 1000, profit: 100 }),
        fiscalYear(2022, { bookValuePerShare: 11, shares: 1000, profit: 100 }),
        fiscalYear(2023, { bookValuePerShare: 12, shares: 1000, profit: 100 }),
      ],
      ValuationLane.shareholder,
    );
    expect(series.length).toBe(3);
    expect(series.points.some((p) => p.year === 2021)).toBe(false);
  });
});

describe('Conciliação da contagem de ações', () => {
  // Os números são os do MILS3 no exercício de 2025, medidos no cache de
  // produção em 07/09/2026. A contagem corrente vinha 4.868x menor que a do
  // exercício, e a ponte de equity devolvia R$ 37.708,72 contra R$ 15,79 de
  // mercado na validação fora da amostra.
  const inThousands = (eps: number | null = null): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(2025, 12, 31),
      netIncome: 301263000,
      earningsPerShare: eps,
      sharesOutstanding: 48172,
      sharesOutstandingAsOf: 234178210,
      bookValuePerShare: 6.7376337,
    });

  it('o lucro por ação publicado arbitra a favor da contagem do exercício', () => {
    // N implícito = 301.263.000 / 1,2865 = 234,2 mi, que é a do exercício.
    expect(inThousands(1.2865).reconciledShares).toBe(234178210);
  });

  it('sem árbitro, prevalece a contagem que reconstrói o patrimônio', () => {
    expect(inThousands().reconciledShares).toBe(234178210);
  });

  it('o árbitro pode confirmar a contagem corrente, e então ela vence', () => {
    // Mesmo par de candidatas, mas agora o LPA aponta para a corrente:
    // 301.263.000 / 6254,0 = 48.172.
    expect(inThousands(6254.0).reconciledShares).toBe(48172);
  });

  it('divergência das duas contagens é sinalizada', () => {
    expect(inThousands().sharesDisagree).toBe(true);
  });

  it('contagens concordantes não geram sinal nem escolha', () => {
    const f = new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(2025, 12, 31),
      sharesOutstanding: 100000000,
      sharesOutstandingAsOf: 98000000,
    });
    expect(f.sharesDisagree).toBe(false);
    expect(f.reconciledShares).toBe(98000000);
  });

  it('uma contagem só é usada como está', () => {
    const f = new FundamentalsSnapshot({ ticker, fiscalPeriodEnd: day(2025, 12, 31), sharesOutstanding: 48172 });
    expect(f.reconciledShares).toBe(48172);
    expect(f.sharesDisagree).toBe(false);
  });

  it('LPA nulo ou zerado não é árbitro', () => {
    expect(inThousands(0).reconciledShares).toBe(234178210);
  });
});

describe('Guarda 2 — capital externo', () => {
  it('expansão por lucro retido é orgânica', () => {
    // Patrimônio cresce exatamente pelo lucro: nada veio de fora.
    let pl = 1000.0;
    const points: FundamentalsSnapshot[] = [];
    for (let year = 2016; year <= 2025; year++) {
      points.push(fiscalYear(year, { bookValuePerShare: pl / 1000, shares: 1000, profit: 100 }));
      pl += 100;
    }
    const series = CapitalSeries.build(points, ValuationLane.shareholder);
    const phi = GrowthGuards.externalCapitalRatio(series);
    expect(phi).not.toBeNull();
    expect(phi!).toBeLessThan(0.05);
  });

  it('salto de patrimônio acima do lucro acusa capital externo', () => {
    // Forma da RENT3 na incorporação: o patrimônio salta muito além do que a
    // empresa lucrou no ano.
    const points: FundamentalsSnapshot[] = [];
    let pl = 1000.0;
    for (let year = 2016; year <= 2025; year++) {
      if (year === 2022) pl += 8000;
      points.push(fiscalYear(year, { bookValuePerShare: pl / 1000, shares: 1000, profit: 100 }));
      pl += 100;
    }
    const series = CapitalSeries.build(points, ValuationLane.shareholder);
    const phi = GrowthGuards.externalCapitalRatio(series);
    expect(phi).not.toBeNull();
    expect(phi!).toBeGreaterThan(ValuationParameters.maxExternalCapital);
  });
});

describe('Precedência da Guarda 2 — Φ declara, não barra', () => {
  // Forma da SUZB3 e da QUAL3: base de capital que salta por incorporação —
  // Φ muito acima de 1,0 — e um exercício corrente de rentabilidade em pico.
  // Sob a precedência anterior, Φ travava a normalização e o pico virava
  // patamar perene: a SUZB3 saía a +259,1% e a QUAL3 a +477,3% de potencial.
  const mergerWithSpike = (cycleRoe: number, currentRoe: number): FundamentalsSnapshot[] => {
    const points: FundamentalsSnapshot[] = [];
    let pl = 1000.0;
    for (let year = 2012; year <= 2025; year++) {
      // O retorno do ano é medido sobre a base de **abertura**, que é a
      // convenção de `CapitalSeries.returns`.
      const profit = year === 2025 ? currentRoe * pl : cycleRoe * pl;
      pl += profit;
      // A incorporação: em 2020 a base salta seis vezes o lucro do ano.
      if (year === 2020) pl += 6000;
      points.push(
        new FundamentalsSnapshot({
          ticker,
          fiscalPeriodEnd: day(year, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          netIncome: year === 2012 ? null : profit,
          marketCap: 20000,
        }),
      );
    }
    return points;
  };

  const entries = (
    history: FundamentalsSnapshot[],
    o: { sector?: string | null; subsector?: string | null } = {},
  ): ValuationInputs =>
    new ValuationInputs({
      ticker,
      asOf: day(2026, 6, 30),
      fundamentals: history,
      marketPrice: 20.0,
      capm: new CapmInputs({ riskFreeRate: 0.105, beta: 1.0, marketPremium: 0.055 }),
      sectorKey: o.sector ?? null,
      industry: o.subsector ?? null,
    });

  /** Fator de normalização registrado no log de avaliação. */
  const recordedFactor = (inputs: ValuationInputs): number => {
    const captured = captureEvents(() => ValuationCascade.evaluate(inputs));
    const base = single(captured).calculations.find(
      (c) => c.formulaName === 'Base do fluxo: normalização pelo ciclo',
    )!;
    return base.finalValue!;
  };

  afterEach(() => AuditRecorder.detach());

  it('Φ acima do limiar não impede a normalização do retorno', () => {
    const history = mergerWithSpike(0.1, 0.3);
    const series = CapitalSeries.build(history, ValuationLane.shareholder);

    // A base é mesmo inorgânica, e por larga margem.
    const phi = GrowthGuards.externalCapitalRatio(series);
    expect(phi).not.toBeNull();
    expect(phi!).toBeGreaterThan(ValuationParameters.maxExternalCapital);

    // E o exercício corrente destoa do ciclo.
    expect(GrowthGuards.deviatesFromCycle(series)).toBe(true);

    // Logo o retorno é normalizado, sobre a base de capital corrente: o
    // fator é a razão entre o ciclo e o exercício de pico.
    expectClose(
      recordedFactor(entries(history)),
      0.1 / 0.3,
      1e-3,
      'ROIC e ROE são grandezas intensivas: mudança de tamanho por evento societário não torna o pico um patamar perene',
    );
  });

  it('sem desvio do ciclo, Φ alto sozinho não normaliza nada', () => {
    // A Guarda 3 continua sendo quem decide **se** normaliza. Φ nunca
    // normalizou nada, e continua não normalizando.
    const history = mergerWithSpike(0.1, 0.1);
    expectClose(recordedFactor(entries(history)), 1.0, 1e-9);
  });

  it('em commodity, a tendência não segura a base', () => {
    // Forma da SUZB3: retorno corrente muito acima do ciclo, subindo ano a
    // ano, de modo que a Guarda 1 lê a perna de alta como tendência
    // estrutural. Fora de setor cíclico a base fica; em papel e celulose,
    // não.
    const points: FundamentalsSnapshot[] = [];
    let pl = 1000.0;
    for (let year = 2012; year <= 2025; year++) {
      // Retorno subindo de 8% a 34%: tendência significante e dominante.
      const roe = 0.08 + (year - 2012) * 0.02;
      const profit = roe * pl;
      pl += profit;
      points.push(
        new FundamentalsSnapshot({
          ticker,
          fiscalPeriodEnd: day(year, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          netIncome: year === 2012 ? null : profit,
          marketCap: 20000,
        }),
      );
    }
    const series = CapitalSeries.build(points, ValuationLane.shareholder);
    const t = GrowthGuards.trend(series);
    expect(t?.dominates, 'a fixture precisa mesmo acionar a Guarda 1').toBe(true);
    expect(GrowthGuards.deviatesFromCycle(series)).toBe(true);

    expectClose(
      recordedFactor(entries(points, { sector: 'tecnologia' })),
      1.0,
      1e-9,
      'fora de commodity a tendência continua segurando a base',
    );
    expect(
      recordedFactor(entries(points, { sector: 'materiais-basicos', subsector: 'Papel e Celulose' })),
      'em commodity a reversão ao ciclo tem precedência',
    ).toBeLessThan(1.0);
  });

  /**
   * Base que salta por emissão no penúltimo exercício, com o lucro
   * **preservado**: o retorno corrente desaba sem que a empresa tenha
   * encolhido, que é a única forma de estourar o fator sem cair no filtro de
   * saúde. O salto é de 7x porque acima de 8x a limpeza por vizinhança
   * descartaria o próprio exercício.
   */
  const issuanceWithPreservedProfit = (): FundamentalsSnapshot[] => {
    const points: FundamentalsSnapshot[] = [];
    let pl = 1000.0;
    let frozenProfit = 0.0;
    for (let year = 2012; year <= 2025; year++) {
      const profit = year >= 2024 ? frozenProfit : 0.1 * pl;
      if (year === 2023) frozenProfit = 0.1 * pl;
      pl += profit;
      if (year === 2024) pl *= 7;
      points.push(
        new FundamentalsSnapshot({
          ticker,
          fiscalPeriodEnd: day(year, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          netIncome: year === 2012 ? null : profit,
          marketCap: 20000,
        }),
      );
    }
    return points;
  };

  /**
   * Forma da QUAL3: lucro desabando no triênio e retorno corrente **abaixo**
   * do ciclo, de modo que a normalização puxaria a base para cima.
   */
  const structuralDeterioration = (): FundamentalsSnapshot[] => {
    const points: FundamentalsSnapshot[] = [];
    let pl = 1000.0;
    for (let year = 2012; year <= 2025; year++) {
      // 15% de retorno até 2022, 1,5% depois: queda de 90% no triênio.
      const roe = year >= 2023 ? 0.015 : 0.15;
      const profit = roe * pl;
      pl += profit;
      points.push(
        new FundamentalsSnapshot({
          ticker,
          fiscalPeriodEnd: day(year, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          netIncome: year === 2012 ? null : profit,
          marketCap: 20000,
        }),
      );
    }
    return points;
  };

  it('o fator de normalização é saturado em [0,33; 3,00]', () => {
    const points = issuanceWithPreservedProfit();
    const series = CapitalSeries.build(points, ValuationLane.shareholder);
    const raw = series.cycleReturn({ window: ValuationParameters.cycleWindow })! / series.latestReturn!;
    expect(raw, 'a fixture precisa mesmo estourar a banda').toBeGreaterThan(ValuationParameters.baseFactorCeiling);
    expect(
      GrowthGuards.recentOperationalDecline(points)!,
      'e precisa passar na saúde, senão quem trava é a outra regra',
    ).toBeLessThan(ValuationParameters.maxOperationalDecline);

    expectClose(recordedFactor(entries(points)), ValuationParameters.baseFactorCeiling, 1e-9);
  });

  it('a saturação é declarada nos avisos', () => {
    const r = ValuationCascade.evaluate(entries(issuanceWithPreservedProfit()));
    expect(r.isOk).toBe(true);
    expect(
      r.unwrap().warnings.some((w) => w.includes('saturado em')),
      'um preço justo confinado por política precisa dizer que foi',
    ).toBe(true);
  });

  it('deterioração estrutural proíbe normalizar a base para cima', () => {
    const points = structuralDeterioration();
    const series = CapitalSeries.build(points, ValuationLane.shareholder);

    // A fixture é mesmo o caso: destoa do ciclo, e para cima.
    expect(GrowthGuards.deviatesFromCycle(series)).toBe(true);
    const raw = series.cycleReturn({ window: ValuationParameters.cycleWindow })! / series.latestReturn!;
    expect(raw).toBeGreaterThan(1.0);
    expect(GrowthGuards.recentOperationalDecline(points)!).toBeGreaterThan(ValuationParameters.maxOperationalDecline);

    expectClose(
      recordedFactor(entries(points)),
      1.0,
      1e-9,
      'trazer a base de uma empresa que mudou de patamar de volta à mediana de oito anos lhe atribui um retorno que não repetirá',
    );

    const r = ValuationCascade.evaluate(entries(points));
    expect(r.isOk).toBe(true);
    expect(r.unwrap().warnings.some((w) => w.includes('não foi normalizada para cima'))).toBe(true);
  });

  it('commodity em vale de ciclo é isenta da trava de saúde', () => {
    // VALE3 e GGBR4: queda de ~87% entre o pico de 2022 e o vale de 2025, com
    // o retorno corrente abaixo do ciclo. Fora de commodity a base fica
    // travada em 1,00; em materiais básicos a convergência opera.
    const points = structuralDeterioration();
    expect(GrowthGuards.recentOperationalDecline(points)!).toBeGreaterThan(ValuationParameters.maxOperationalDecline);

    expectClose(
      recordedFactor(entries(points, { sector: 'saude' })),
      1.0,
      1e-9,
      'fora de commodity a trava continua valendo integralmente',
    );
    expect(
      recordedFactor(entries(points, { sector: 'materiais-basicos', subsector: 'Siderurgia' })),
      'em commodity a queda entre pico e vale é preço do insumo, e a reversão ao ciclo precisa operar nos dois sentidos',
    ).toBeGreaterThan(1.0);
  });

  it('o aviso do cíclico isento não diz que o moat está barrado', () => {
    // Item B39: desde a decisão 36 o moat não consulta a saúde operacional,
    // e o aviso continuava dizendo que a vantagem residual «segue barrada
    // por ela» — na VALE3, ao lado de um veredito que a concedia.
    const r = ValuationCascade.evaluate(
      entries(structuralDeterioration(), { sector: 'materiais-basicos', subsector: 'Siderurgia' }),
    );
    expect(r.isOk, r.failureOrNull?.message).toBe(true);
    const warning = r.unwrap().warnings.filter((w) => w.includes('no triênio'));
    expect(warning.length, 'a fixture precisa acionar a isenção').toBeGreaterThan(0);
    for (const w of warning) {
      expect(w).not.toContain('barrada');
      expect(w).toContain('decisão 36');
    }
  });

  it('a trava de saúde vale só na Porta 2a, e o moat não a consulta', () => {
    // Desde a decisão 36 a pergunta do moat não é mais "esta empresa merece
    // uma exceção", e sim "quanto do excedente dela persiste". Deterioração
    // entra pela série que estima a persistência, e não por um limiar em
    // cima dela. A trava de saúde continua inteira na Porta 2a, que é onde a
    // QUAL3 era de fato resolvida.
    const v = GrowthGuards.residualMoat({
      cycleReturn: 0.3,
      terminalDiscountRate: 0.12,
      externalCapitalRatio: 0.1,
      periods: 14,
      excessReturns: Array.from({ length: 5 }, (_, i) => ({ year: 2021 + i, excess: 0.18 / pow(2, i) })),
      projectionYears: 10,
    });
    expect(v.isProven).toBe(true);
    expect(v.blocks, 'nenhum bloco de saúde operacional sobrou no moat').toHaveLength(0);
  });

  it('a isenção em commodity continua limitada pela saturação', () => {
    // O que limita a normalização em setor cíclico é a banda, e ela vale
    // igual: isentar da trava de saúde não abre o teto de 3,00x.
    const points = issuanceWithPreservedProfit();
    expectClose(
      recordedFactor(entries(points, { sector: 'materiais-basicos', subsector: 'Papel e Celulose' })),
      ValuationParameters.baseFactorCeiling,
      1e-9,
    );
  });

  it('a isenção é declarada nos avisos', () => {
    const r = ValuationCascade.evaluate(
      entries(structuralDeterioration(), { sector: 'materiais-basicos', subsector: 'Siderurgia' }),
    );
    expect(r.isOk).toBe(true);
    expect(
      r.unwrap().warnings.some((w) => w.includes('setor de commodity')),
      'uma isenção silenciosa é pior que a trava que ela remove',
    ).toBe(true);
  });

  it('o piso continua valendo para quem reprovou na saúde', () => {
    // Deterioração no lucro **com** o exercício corrente acima do ciclo: a
    // trava é só de teto, e normalizar para baixo é a direção conservadora.
    const points: FundamentalsSnapshot[] = [];
    let pl = 1000.0;
    for (let year = 2012; year <= 2025; year++) {
      // Retorno cai de 20% para 2% e o exercício corrente volta a 30%: o
      // lucro do triênio despencou, mas o ano é de pico contra o ciclo.
      const roe = year === 2025 ? 0.3 : year >= 2023 ? 0.02 : 0.2;
      const profit = roe * pl;
      pl += profit;
      points.push(
        new FundamentalsSnapshot({
          ticker,
          fiscalPeriodEnd: day(year, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          netIncome: year === 2012 ? null : profit,
          marketCap: 20000,
        }),
      );
    }
    const series = CapitalSeries.build(points, ValuationLane.shareholder);
    const raw = series.cycleReturn({ window: ValuationParameters.cycleWindow })! / series.latestReturn!;
    expect(raw, 'a fixture precisa normalizar para baixo').toBeLessThan(1.0);

    expect(recordedFactor(entries(points))).toBeLessThan(1.0);
  });

  it('a base inorgânica é declarada nos avisos, não silenciada', () => {
    const history = mergerWithSpike(0.1, 0.3);
    const result = ValuationCascade.evaluate(entries(history));
    expect(result.isOk).toBe(true);
    expect(
      result.unwrap().warnings.some((w) => w.includes('grandeza intensiva')),
      'trocar bloqueio por permissão silenciosa seria pior que o defeito que se está corrigindo',
    ).toBe(true);
  });
});

describe('Porta 1 — instituição financeira, pelo setor', () => {
  /**
   * Empresa com NOPAT positivo em todos os exercícios: pela Porta 3, ela
   * **iria** para a via da firma. É o que torna o teste capaz de isolar a
   * decisão da Porta 1 — sem isso, a via do acionista seria escolhida pela
   * porta seguinte e o teste não provaria nada.
   */
  const withFirmFlow = (debt: number): FundamentalsSnapshot[] => {
    const points: FundamentalsSnapshot[] = [];
    let pl = 1000.0;
    for (let year = 2012; year <= 2025; year++) {
      const profit = 0.12 * pl;
      pl += profit;
      points.push(
        new FundamentalsSnapshot({
          ticker,
          fiscalPeriodEnd: day(year, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          netIncome: year === 2012 ? null : profit,
          nopat: profit,
          ebit: profit * 1.4,
          longTermDebt: debt,
          marketCap: 20000,
        }),
      );
    }
    return points;
  };

  const evaluate = (o: { sector: string | null; debt: number; subsector?: string }): ValuationResult | null => {
    const r = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 6, 30),
        fundamentals: withFirmFlow(o.debt),
        marketPrice: 20.0,
        capm: new CapmInputs({ riskFreeRate: 0.105, beta: 1.0, marketPremium: 0.055 }),
        sectorKey: o.sector,
        industry: o.subsector ?? null,
      }),
    );
    return r.isOk ? r.unwrap() : null;
  };

  it('pela classificação oficial da B3, banco entra; shopping não — A5', () => {
    const bank = evaluate({ sector: 'financeiro', subsector: 'Intermediários Financeiros / Bancos', debt: 0 })!;
    expect(bank.model).toBe(ValuationModel.dcfEarnings);
    expect(bank.warnings.some((w) => w.includes('Instituição financeira'))).toBe(true);
    const shopping = evaluate({
      sector: 'financeiro',
      subsector: 'Exploração de Imóveis / Exploração de Imóveis',
      debt: 0,
    })!;
    expect(shopping.model).toBe(ValuationModel.dcfFcff);
    expect(shopping.warnings.some((w) => w.includes('Instituição financeira'))).toBe(false);
  });

  it('setor financeiro manda para a via do acionista', () => {
    const v = evaluate({ sector: 'servicos-financeiros', debt: 0 });
    expect(v).not.toBeNull();
    expect(v!.model).toBe(ValuationModel.dcfEarnings);
    expect(
      v!.warnings.some((w) => w.includes('Instituição financeira')),
      'a porta que decidiu precisa aparecer no resultado',
    ).toBe(true);
  });

  it('passivo oneroso NÃO tira a financeira da Porta 1', () => {
    // Captação é a matéria-prima do negócio bancário: exigir dívida nula
    // barrava justamente quem a porta existe para pegar. Cinco dos 28 ativos
    // do setor caíam por ela para a via da firma, e na B3SA3 as debêntures
    // viravam dívida líquida subtraída do valor da firma.
    //
    // A justificativa original da exigência — a RENT3 chegando como
    // `Finance` — é de outra taxonomia: a porta compara contra a do perfil,
    // onde a RENT3 vem como `consumo-ciclico`.
    const v = evaluate({ sector: 'servicos-financeiros', debt: 500 });
    expect(v).not.toBeNull();
    expect(v!.model).toBe(ValuationModel.dcfEarnings);
    expect(v!.warnings.some((w) => w.includes('Instituição financeira'))).toBe(true);
  });

  it('fora do setor financeiro, dívida nula não aciona a Porta 1', () => {
    const v = evaluate({ sector: 'bens-industriais', debt: 0 });
    expect(v).not.toBeNull();
    expect(v!.model).toBe(ValuationModel.dcfFcff);
    expect(v!.warnings.some((w) => w.includes('Instituição financeira'))).toBe(false);
  });

  it('sem setor informado, o roteamento cai na Porta 3', () => {
    // Degradação segura declarada na decisão 25: perfil que não carrega não
    // pode ligar uma exceção de via.
    const v = evaluate({ sector: null, debt: 0 });
    expect(v).not.toBeNull();
    expect(v!.model).toBe(ValuationModel.dcfFcff);
  });
});

describe('Precedência do ciclo em commodity — Guarda 3 sobre Guarda 1', () => {
  it('a taxonomia separa petróleo de energia elétrica', () => {
    // A chave `energia` reúne exploração de petróleo, que é commodity pura, e
    // 28 elétricas, que são concessão regulada. Tratar a chave inteira como
    // cíclica inverteria a natureza das segundas.
    const cyclical = (sector: string | null, sub: string | null): boolean =>
      CyclicalSectors.hasCyclePrecedence({ sectorKey: sector, industry: sub });

    expect(cyclical('energia', 'Exploração e Produção de Petróleo')).toBe(true);
    expect(cyclical('energia', 'Exploração, Refino e Distribuição')).toBe(true);
    expect(cyclical('energia', 'Petróleo e Gás Integrado')).toBe(true);
    expect(cyclical('energia', 'Energia Elétrica')).toBe(false);
    expect(cyclical('energia', 'Gás'), 'distribuição de gás é concessão, não exploração').toBe(false);
    expect(cyclical('saneamento', 'Água e Saneamento')).toBe(false);
    expect(cyclical('servicos-financeiros', 'Bancos')).toBe(false);
  });

  it('materiais básicos é cíclico por inteiro', () => {
    for (const sub of [
      'Papel e Celulose',
      'Siderurgia',
      'Minerais Metálicos',
      'Petroquímicos',
      'Fertilizantes e Defensivos',
    ]) {
      expect(CyclicalSectors.hasCyclePrecedence({ sectorKey: 'materiais-basicos', industry: sub }), sub).toBe(true);
    }
  });

  it('a variante de pontuação da fonte não muda a classificação', () => {
    // A fonte publica os dois: com vírgula e com ponto.
    expect(
      CyclicalSectors.hasCyclePrecedence({ sectorKey: 'energia', industry: 'Exploração, Refino e Distribuição' }),
    ).toBe(CyclicalSectors.hasCyclePrecedence({ sectorKey: 'energia', industry: 'Exploração. Refino e Distribuição' }));
  });

  it('sem setor nem subsetor, não há precedência', () => {
    expect(CyclicalSectors.hasCyclePrecedence(), 'ausência de classificação não pode ligar uma exceção').toBe(false);
  });
});

describe('Saída 2 — identificação do crescimento', () => {
  const withGrowthSeries = (g: number, noise = 0): FundamentalsSnapshot[] => {
    let pl = 1000.0;
    const points: FundamentalsSnapshot[] = [];
    for (let year = 2014; year <= 2025; year++) {
      const deviation = noise === 0 ? 1.0 : year % 2 === 0 ? 1 + noise : 1 - noise;
      points.push(fiscalYear(year, { bookValuePerShare: (pl * deviation) / 1000, shares: 1000, profit: pl * 0.15 }));
      pl *= 1 + g;
    }
    return points;
  };

  it('série limpa devolve o crescimento pela mediana das variações', () => {
    const series = CapitalSeries.build(withGrowthSeries(0.08), ValuationLane.shareholder);
    const d = GrowthGuards.dispersion(series);
    expect(d).not.toBeNull();
    expect(d!.isIdentified).toBe(true);
    expectClose(d!.medianGrowth, 0.08, 1e-6);
  });

  it('estimador impreciso é barrado antes do teste de discordância', () => {
    // Forma da PRIO3: os dois estimadores concordam (D pequeno) porque ambos
    // são ruins. Sem o piso de precisão, o ativo mais imprecisamente medido
    // da amostra receberia o maior crescimento.
    const series = CapitalSeries.build(withGrowthSeries(0.25, 0.45), ValuationLane.shareholder);
    const d = GrowthGuards.dispersion(series);
    expect(d).not.toBeNull();
    expect(d!.stdError).toBeGreaterThan(ValuationParameters.maxGrowthStdError);
    expect(d!.isIdentified).toBe(false);
    expect(d!.failure).toContain('impreciso');
  });

  it('financiabilidade discrimina por retorno, não por setor', () => {
    // Retorno alto torna a inflação barata de financiar; retorno baixo, não.
    // É a forma de BBSE3 contra VIVT3.
    expect(
      GrowthGuards.anchorIsFundable({ inflation: 0.05, cycleReturn: 0.675, observedRetention: 0.113 }),
      'com retorno de 67,5%, crescer à inflação custa 7,4% de retenção contra 11,3% observados',
    ).toBe(true);
    expect(
      GrowthGuards.anchorIsFundable({ inflation: 0.05, cycleReturn: 0.078, observedRetention: 0.06 }),
      'com retorno de 7,8%, exigiria reter 64% contra 6% observados',
    ).toBe(false);
  });
});

describe('Porta 0 — elegibilidade', () => {
  const healthy = (from: number, to: number): FundamentalsSnapshot[] => {
    const out: FundamentalsSnapshot[] = [];
    for (let year = from; year <= to; year++) {
      out.push(fiscalYear(year, { bookValuePerShare: 10, shares: 1000, profit: 100 }));
    }
    return out;
  };

  it('histórico curto reprova', () => {
    const v = EligibilityGate.assess({ snapshots: healthy(2021, 2025) });
    expect(v.isEligible).toBe(false);
    expect(v.reasons).toContain(IneligibilityReason.shortHistory);
  });

  it('patrimônio negativo em dois exercícios consecutivos reprova', () => {
    const v = EligibilityGate.assess({
      snapshots: [
        ...healthy(2016, 2023),
        fiscalYear(2024, { bookValuePerShare: -1, shares: 1000, profit: -50 }),
        fiscalYear(2025, { bookValuePerShare: -2, shares: 1000, profit: -50 }),
      ],
    });
    expect(v.isEligible).toBe(false);
    expect(v.reasons).toContain(IneligibilityReason.insolvent);
  });

  it('um exercício isolado de patrimônio negativo não reprova', () => {
    const v = EligibilityGate.assess({
      snapshots: [
        ...healthy(2016, 2023),
        fiscalYear(2024, { bookValuePerShare: -1, shares: 1000, profit: -50 }),
        fiscalYear(2025, { bookValuePerShare: 9, shares: 1000, profit: 80 }),
      ],
    });
    expect(v.reasons).not.toContain(IneligibilityReason.insolvent);
  });

  it('recuperação judicial reprova, e vem de fora', () => {
    const v = EligibilityGate.assess({ snapshots: healthy(2016, 2025), isDistressed: true });
    expect(v.isEligible).toBe(false);
    expect(v.reasons).toContain(IneligibilityReason.distressed);
  });

  it('série sem volume omite o teste de liquidez em vez de reprovar', () => {
    const v = EligibilityGate.assess({
      snapshots: healthy(2016, 2025),
      prices: new PriceSeries({
        ticker,
        points: Array.from(
          { length: 100 },
          (_, i) => new PricePoint({ date: day(2026, 1, 1).add(new Duration({ days: i })), close: 10 }),
        ),
      }),
    });
    expect(v.averageDailyTradedValue).toBeNull();
    expect(v.reasons).not.toContain(IneligibilityReason.illiquid);
  });

  it('volume financeiro abaixo do corte reprova', () => {
    const v = EligibilityGate.assess({
      snapshots: healthy(2016, 2025),
      prices: new PriceSeries({
        ticker,
        points: Array.from(
          { length: 100 },
          (_, i) => new PricePoint({ date: day(2026, 1, 1).add(new Duration({ days: i })), close: 10, volume: 1000 }),
        ),
      }),
    });
    expectClose(v.averageDailyTradedValue, 10000, 1e-6);
    expect(v.reasons).toContain(IneligibilityReason.illiquid);
  });
});

describe('Estrutura a termo do desconto', () => {
  const a = new DcfAssumptions({
    projectionYears: 10,
    growthRate: 0.1,
    perpetualGrowth: 0.05,
    discountRate: 0.16,
    terminalDiscountRate: 0.12,
    returnOnCapital: 0.2,
  });

  it('a taxa parte da corrente e chega à de equilíbrio', () => {
    expectClose(a.discountRateAt(1), 0.16, 1e-12);
    expectClose(a.discountRateAt(10), 0.12, 1e-12);
  });

  it('o decaimento é linear no passo da janela', () => {
    // No ano 6 percorreram-se 5/9 da janela.
    expectClose(a.discountRateAt(6), 0.16 - (0.04 * 5) / 9, 1e-12);
  });

  it('o retorno converge para o custo de capital do próprio ano', () => {
    expectClose(a.returnOnCapitalAt(1), 0.2, 1e-12);
    expectClose(a.returnOnCapitalAt(10), a.discountRateAt(10), 1e-12);
  });

  it('o último ano explícito encontra a retenção do estado estacionário', () => {
    // b_N = g_inf / r_inf é exatamente a retenção que o terminal supõe:
    // a projeção deixa de saltar para a perpetuidade.
    expectClose(a.retentionAt(10), 0.05 / 0.12, 1e-12);
  });

  it('o fator de desconto acumula as taxas, não eleva uma só a t', () => {
    const o = DcfCalculator.shareholder({
      baseProfit: 100,
      assumptions: new DcfAssumptions({
        projectionYears: 2,
        growthRate: 0.0,
        perpetualGrowth: 0.0,
        discountRate: 0.2,
        terminalDiscountRate: 0.1,
      }),
    }).unwrap();
    // Ano 1 a 20%, ano 2 a 10%: fatores 1,20 e 1,20 x 1,10 = 1,32. O
    // levantamento de meio de ano usa a taxa **do próprio ano**, e é o que
    // separa "o caixa chega no meio do ano" de "a curva mudou".
    expectClose(o.discountedFlows[0], (100 * Math.sqrt(1.2)) / 1.2, 1e-9);
    expectClose(o.discountedFlows[1], (100 * Math.sqrt(1.1)) / 1.32, 1e-9);
  });

  it('a convenção de meio de ano levanta o valor por raiz de (1+r)', () => {
    // O levantamento incide sobre a avaliação **inteira** — período
    // explícito e perpetuidade —, e por isso é razão exata quando a taxa é
    // plana. Com taxa única de 13%, vale 6,30%.
    const withTiming = (timing: CashTiming): DcfOutcome =>
      DcfCalculator.shareholder({
        baseProfit: 100,
        assumptions: new DcfAssumptions({
          projectionYears: 10,
          growthRate: 0.04,
          perpetualGrowth: 0.04,
          discountRate: 0.13,
          terminalDiscountRate: 0.13,
          cashTiming: timing,
        }),
      }).unwrap();

    const end = withTiming(CashTiming.endOfYear);
    const mid = withTiming(CashTiming.midYear);
    expectClose(mid.fairValuePerShare / end.fairValuePerShare, Math.sqrt(1.13), 1e-12);
    expectClose(Math.sqrt(1.13) - 1, 0.063, 1e-4);

    // A composição do valor **não** muda: o levantamento é o mesmo fator nos
    // dois pedaços, e o peso do terminal fica onde estava.
    expectClose(mid.terminalShare, end.terminalShare, 1e-12);
  });

  it('sob taxa que varia, o levantamento não é fator único', () => {
    // Cada ano é levantado pela taxa daquele ano, de modo que a razão entre
    // as duas convenções fica **entre** as raízes dos extremos. Se fosse
    // fator único, o meio de ano seria mera reescala e não precisaria
    // atravessar a projeção.
    const withTiming = (timing: CashTiming): DcfOutcome =>
      DcfCalculator.shareholder({
        baseProfit: 100,
        assumptions: new DcfAssumptions({
          projectionYears: 10,
          growthRate: 0.04,
          perpetualGrowth: 0.04,
          discountRate: 0.18,
          terminalDiscountRate: 0.09,
          cashTiming: timing,
        }),
      }).unwrap();

    const ratio =
      withTiming(CashTiming.midYear).fairValuePerShare / withTiming(CashTiming.endOfYear).fairValuePerShare;
    expect(ratio).toBeGreaterThan(Math.sqrt(1.09));
    expect(ratio).toBeLessThan(Math.sqrt(1.18));
  });

  it('sem taxa terminal declarada, o desconto é plano', () => {
    const flat = new DcfAssumptions({ projectionYears: 10, growthRate: 0.1, perpetualGrowth: 0.05, discountRate: 0.16 });
    expect(flat.terminalDiscountRate).toBe(0.16);
    expectClose(flat.discountRateAt(7), 0.16, 1e-12);
  });
});

describe('Alíquota estrutural no fluxo da firma', () => {
  // [imposto] é o **ônus**, em módulo. A fonte grava a despesa com sinal
  // negativo — `lucro líquido = lucro antes + incomeTaxExpense` —, e o
  // fixture reproduz essa convenção para que o teste exercite a conta real.
  const withTax = (year: number, profitBefore: number, tax: number, yearEbit?: number): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(year, 12, 31),
      ebit: yearEbit ?? 1000,
      ebitda: (yearEbit ?? 1000) + 300,
      netIncome: profitBefore - tax,
      incomeBeforeTax: profitBefore,
      incomeTaxExpense: -tax,
      nopat: (yearEbit ?? 1000) * 0.66,
      totalStockholderEquity: 5000,
      bookValuePerShare: 5.0,
      propertyPlantEquipment: 6000,
      totalCurrentAssets: 2000,
      currentLiabilities: 1000,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
    });

  const withTaxRate = (rate: number, years = 10): FundamentalsSnapshot[] => {
    const out: FundamentalsSnapshot[] = [];
    for (let i = years - 1; i >= 0; i--) out.push(withTax(2025 - i, 1000, 1000 * rate));
    return out;
  };

  it('a estrutural é a mediana dos exercícios, não a do último', () => {
    // Nove exercícios a 20% e um a 45%: a mediana ignora o atípico, que é o
    // ponto de usar mediana e não o último exercício.
    const series: FundamentalsSnapshot[] = [];
    for (let i = 9; i >= 1; i--) series.push(withTax(2025 - i, 1000, 200));
    series.push(withTax(2025, 1000, 450));
    expectClose(CapitalSeries.structuralTaxRate(series, { statutoryRate: 0.34 }), 0.2, 1e-12);
  });

  it('é confinada no teto da estatutária', () => {
    // Pagar mais que a marginal em perpetuidade é transitório, e a fonte já
    // aplicou a estatutária: ir além penalizaria duas vezes.
    expectClose(CapitalSeries.structuralTaxRate(withTaxRate(0.45), { statutoryRate: 0.34 }), 0.34, 1e-12);
  });

  it('série curta demais devolve nulo, e o chamador recua', () => {
    expect(CapitalSeries.structuralTaxRate(withTaxRate(0.15, 4), { statutoryRate: 0.34 })).toBeNull();
    expectClose(CapitalSeries.structuralTaxRate(withTaxRate(0.15, 5), { statutoryRate: 0.34 }), 0.15, 1e-12);
  });

  it('crédito tributário vira alíquota nula, não imposto a pagar', () => {
    // A versão anterior aplicava `.abs()` antes da divisão, e o exercício em
    // que a empresa **recuperou** imposto saía com alíquota positiva — o
    // `clamp`, que existe para conter a distorção, nunca chegava a agir.
    // Ônus negativo é crédito: a fonte o grava com `incomeTaxExpense`
    // positivo, e o fixture inverte, então isto produz +200 no campo.
    const credit = withTax(2025, 1000, -200);
    expect(credit.incomeTaxExpense).toBe(200);
    expect(credit.effectiveTaxRate).toBe(0.0);
    // E o NOPAT desse exercício é o EBIT cheio, não EBIT x 0,80.
    expectClose(credit.nopatAtRate(credit.effectiveTaxRate), 1000.0, 1e-9);
  });

  it('nopatAtRate recalcula sobre o EBIT, e recua sem alíquota', () => {
    const s = withTax(2025, 1000, 150);
    expectClose(s.nopatAtRate(0.15), 1000 * 0.85, 1e-9);
    // Sem alíquota informada vale o publicado pela fonte, que é EBIT x 0,66.
    expectClose(s.nopatAtRate(null), 660.0, 1e-9);
  });

  it('a série de capital carrega a alíquota, e o ROIC sobe com ela', () => {
    const series = withTaxRate(0.15);
    const statutory = CapitalSeries.build(series, ValuationLane.firm);
    const structural = CapitalSeries.build(series, ValuationLane.firm, { firmTaxRate: 0.15 });
    const rStatutory = statutory.latestReturn!;
    const rStructural = structural.latestReturn!;
    expect(rStructural).toBeGreaterThan(rStatutory);
    // NOPAT passa de EBIT x 0,66 para EBIT x 0,85 sobre a mesma base.
    expectClose(rStructural / rStatutory, 0.85 / 0.66, 1e-9);
  });

  it('o ROIC e o fluxo-base mudam juntos, e o freio fica coerente', () => {
    // É o ponto que a decisão 31 já havia medido em 17% na AZZA3: casar o
    // `g` de uma série com o `ROIC` de outra cobra reinvestimento de um
    // retorno que não é o do fluxo descontado. Mudar só o fluxo repetiria o
    // defeito, agora pela via do imposto.
    const series = withTaxRate(0.15);
    const s = CapitalSeries.build(series, ValuationLane.firm, { firmTaxRate: 0.15 });
    const last = series[series.length - 1]!;
    const base = last.nopatAtRate(0.15)!;
    const capital = last.investedCapital!;
    expectClose(
      s.latestReturn,
      base / capital,
      1e-9,
      'o retorno da série tem de ser o do fluxo-base sobre a mesma base de capital',
    );
  });

  it('a via do acionista não é tocada', () => {
    const series = withTaxRate(0.15);
    const withoutRate = CapitalSeries.build(series, ValuationLane.shareholder);
    const withRate = CapitalSeries.build(series, ValuationLane.shareholder, { firmTaxRate: 0.15 });
    expect(
      withRate.latestReturn,
      'o lucro líquido já vem tributado; aplicar alíquota de novo tributaria duas vezes',
    ).toBe(withoutRate.latestReturn);
  });
});

describe('Vantagem competitiva residual — decaimento medido', () => {
  // Excedente exatamente geométrico: `e_t = e_0 · phi^t`. Sobre ele o AR(1)
  // devolve a inclinação exata, o que torna o teste uma verificação da conta
  // e não uma comparação com número decorado.
  const geometric = (e0: number, phi: number, points: number): YearExcess[] =>
    Array.from({ length: points }, (_, i) => ({ year: 2010 + i, excess: e0 * pow(phi, i) }));

  /** Série com os anos informados, para exercitar buraco de calendário. */
  const inYears = (years: number[], e0: number, phi: number): YearExcess[] =>
    years.map((year, i) => ({ year, excess: e0 * pow(phi, i) }));

  const moat = (
    o: {
      returnRate?: number | null;
      discount?: number;
      phi?: number | null;
      fiscalYears?: number;
      excesses?: YearExcess[];
      years?: number;
    } = {},
  ): number | null =>
    GrowthGuards.residualMoat({
      cycleReturn: 'returnRate' in o ? (o.returnRate ?? null) : 0.3,
      terminalDiscountRate: o.discount ?? 0.12,
      externalCapitalRatio: 'phi' in o ? (o.phi ?? null) : 0.1,
      periods: o.fiscalYears ?? 14,
      excessReturns: o.excesses ?? geometric(0.18, 0.5, 9),
      projectionYears: o.years ?? 10,
    }).terminalReturn;

  it('o AR(1) recupera a persistência crua de uma série geométrica', () => {
    const p = GrowthGuards.excessPersistence(geometric(0.18, 0.5, 9))!;
    expectClose(p.rawPhi, 0.5, 1e-12);
    expect(p.pairs).toBe(8);
    // Sem correção de viés: o que a série mostra é o que entra. A tentativa
    // de corrigir Kendall pôs dez de vinte e quatro ativos no teto, e o
    // teto passou a decidir no lugar do dado — ver `excessPersistence`.
    expectClose(p.phi, 0.5, 1e-12);
  });

  it('a persistência é confinada no teto', () => {
    // Série quase perene: a correção levaria phi acima de 1, que seria
    // excedente que nunca decai — exatamente o que o terminal neutro nega.
    const p = GrowthGuards.excessPersistence(geometric(0.18, 0.98, 12))!;
    expectClose(p.rawPhi, 0.98, 1e-12);
    expect(p.phi).toBe(ValuationParameters.moatMaxPersistence);
    expect(
      p.phi,
      'o teto só morde no extremo, e quando morde tem de aparecer na diferença entre o cru e o aplicado',
    ).toBeLessThan(p.rawPhi);
  });

  it('excedente que oscila não é vantagem que decai', () => {
    // Sinais alternados: o AR(1) devolve inclinação negativa, e o
    // confinamento a leva a zero. Sem persistência não há o que preservar.
    const alternatingSeries = Array.from({ length: 7 }, (_, i) => ({
      year: 2010 + i,
      excess: i % 2 === 0 ? 0.1 : -0.1,
    }));
    const p = GrowthGuards.excessPersistence(alternatingSeries)!;
    expect(p.rawPhi).toBeLessThan(0);
    expect(p.phi).toBe(0.0);
    expect(moat({ excesses: alternatingSeries })).toBeNull();
  });

  it('série curta demais não estima persistência, e isso barra', () => {
    expect(GrowthGuards.excessPersistence(geometric(0.1, 0.5, 3))).toBeNull();
    const v = GrowthGuards.residualMoat({
      cycleReturn: 0.3,
      terminalDiscountRate: 0.12,
      externalCapitalRatio: 0.1,
      periods: 14,
      excessReturns: geometric(0.1, 0.5, 3),
      projectionYears: 10,
    });
    expect(v.isProven).toBe(false);
    expect(v.blocks).toContain(MoatBlock.persistenceNotEstimable);
  });

  it('buraco de calendário não vira par: 2023 não regride sobre 2019', () => {
    // `CapitalSeries.returns` pula exercício sem base ou sem lucro, então a
    // lista pode ter salto de ano. Parear anos não adjacentes leria quatro
    // anos de decaimento como um, e enviesaria φ para baixo.
    const contiguous = geometric(0.18, 0.5, 9);
    const withGap = inYears([2010, 2011, 2012, 2013, 2018, 2019, 2020, 2021, 2022], 0.18, 0.5);
    const a = GrowthGuards.excessPersistence(contiguous)!;
    const b = GrowthGuards.excessPersistence(withGap)!;
    expect(a.pairs).toBe(8);
    expect(b.pairs, 'o par 2013→2018 não pode existir').toBe(7);
    expectClose(b.rawPhi, 0.5, 1e-12, 'descartado o par do buraco, o decaimento é o mesmo');
  });

  it('pares adjacentes de menos devolvem nulo', () => {
    // Quatro pontos alternados dão zero pares adjacentes.
    expect(GrowthGuards.excessPersistence(inYears([2010, 2012, 2014, 2016, 2018, 2020], 0.18, 0.5))).toBeNull();
  });

  it('o retorno terminal é a taxa mais phi elevado a N vezes o excedente', () => {
    const lambda = pow(0.5, 10);
    expectClose(moat(), 0.12 + lambda * (0.3 - 0.12), 1e-12);
  });

  it('o retorno terminal nunca ultrapassa o que a empresa entregou', () => {
    // Invariante da forma: `lambda` vive em [0, 1], logo o terminal vive em
    // (r_inf, ROIC do ciclo]. Preservar mais do que o próprio ciclo seria
    // inventar vantagem que a série não mostrou.
    for (const phi of [0.1, 0.3, 0.5, 0.7, 0.9]) {
      const t = moat({ excesses: geometric(0.18, phi, 12) });
      if (t === null) continue;
      expect(t).toBeGreaterThan(0.12);
      expect(t).toBeLessThanOrEqual(0.3 + 1e-12);
    }
  });

  it('NÃO há degrau: o terminal é contínuo no retorno do ciclo', () => {
    // É o defeito que a decisão 36 corrige. Antes dela, o retorno do ciclo
    // atravessando `1,5 · WACC` ou `WACC + 5 p.p.` fazia o preço justo
    // saltar; medido em 09/09/2026, o salto valia de 10% a 32% em onze
    // ativos, e estava ordenado ao contrário do tamanho do efeito.
    let previous: number | null = null;
    let evaluated = 0;
    for (let step = 0; step <= 60; step++) {
      const cycle = 0.1201 + step * 0.003;
      const t = moat({ returnRate: cycle });
      if (t === null) continue;
      evaluated++;
      if (previous !== null) {
        expect(t, 'monotonia no retorno do ciclo').toBeGreaterThan(previous - 1e-12);
        // O passo do terminal é `lambda` vezes o passo do ciclo. Com lambda
        // em [0, 1], nenhum incremento pode superar o do próprio ciclo — que
        // é justamente o que um degrau faria.
        expect(t - previous, 'salto maior que o passo do ciclo é degrau').toBeLessThanOrEqual(0.003 + 1e-12);
      }
      previous = t;
    }
    expect(evaluated).toBeGreaterThan(50);
  });

  it('excedente pequeno recebe preservação pequena, e não recusa', () => {
    // Sob o degrau, 2,4 p.p. de excedente reprovavam por inteiro: era o caso
    // de SAPR4, SAPR11, TAEE4 e TAEE11, que perdiam de 12% a 16% de preço
    // justo por um limiar. Agora recebem o que a persistência sustenta.
    const t = moat({ returnRate: 0.144 });
    expect(t).not.toBeNull();
    expect(t!).toBeGreaterThan(0.12);
    expect(t!).toBeLessThan(0.144);
  });

  it('horizonte nulo não vira excedente perene', () => {
    // `φ⁰ = 1` preservaria o excedente inteiro para sempre — o oposto do que
    // o decaimento existe para fazer, e um erro silencioso porque produziria
    // um número plausível. `DcfCalculator` recusa projeção com menos de um
    // ano antes disso; o piso aqui existe para a função não depender dessa
    // recusa para estar certa.
    const withZero = moat({ years: 0 });
    const withOne = moat({ years: 1 });
    expect(withZero).not.toBeNull();
    expect(withZero).toBe(withOne);
    expect(withZero!, 'preservar o excedente inteiro seria φ⁰ = 1').toBeLessThan(0.3);
  });

  it('crescimento inorgânico reprova, no limiar de 0,60', () => {
    expect(moat({ phi: 0.61 })).toBeNull();
    expect(moat({ phi: 0.6 })).not.toBeNull();
    // Sob o corte anterior de 0,35, a EGIE3 (0,58) e o ITUB4 (0,50) caíam
    // aqui — concessão e banco acusam Φ alto por definição do negócio.
    expect(moat({ phi: 0.58 })).not.toBeNull();
  });

  it('Phi não medido reprova — ausência não é aprovação', () => {
    expect(moat({ phi: null })).toBeNull();
  });

  it('histórico curto reprova, no piso da Porta 0', () => {
    expect(moat({ fiscalYears: 7 })).toBeNull();
    expect(moat({ fiscalYears: 8 })).not.toBeNull();
  });

  it('sem retorno do ciclo não há vantagem a preservar', () => {
    expect(moat({ returnRate: null })).toBeNull();
  });

  it('retorno abaixo do custo de capital não é excedente', () => {
    expect(moat({ returnRate: 0.11 })).toBeNull();
    const v = GrowthGuards.residualMoat({
      cycleReturn: 0.11,
      terminalDiscountRate: 0.12,
      externalCapitalRatio: 0.1,
      periods: 14,
      excessReturns: geometric(0.18, 0.5, 9),
      projectionYears: 10,
    });
    expect(v.blocks, 'só a ausência de excedente barrou').toEqual([MoatBlock.noExcess]);
  });

  it('o veredito nomeia todas as condições que barraram', () => {
    const v = GrowthGuards.residualMoat({
      cycleReturn: 0.1,
      terminalDiscountRate: 0.12,
      externalCapitalRatio: 0.9,
      periods: 5,
      excessReturns: geometric(0.01, 0.5, 2),
      projectionYears: 10,
    });
    expect(v.isProven).toBe(false);
    // Avaliar em curto-circuito esconderia as demais recusas.
    for (const block of [
      MoatBlock.shortHistory,
      MoatBlock.inorganicGrowth,
      MoatBlock.persistenceNotEstimable,
      MoatBlock.noExcess,
    ]) {
      expect(v.blocks, block.name).toContain(block);
    }
  });

  it('o veredito carrega phi cru e phi aplicado lado a lado', () => {
    // Os dois números viajam juntos para que o confinamento seja auditável:
    // quem recalibrar o teto precisa saber onde ele mordeu.
    const v = GrowthGuards.residualMoat({
      cycleReturn: 0.3,
      terminalDiscountRate: 0.12,
      externalCapitalRatio: 0.1,
      periods: 14,
      excessReturns: geometric(0.18, 0.5, 9),
      projectionYears: 10,
    });
    expectClose(v.rawPersistence, 0.5, 1e-12);
    expectClose(v.persistence, 0.5, 1e-12);
    expectClose(v.retainedFraction, pow(0.5, 10), 1e-12);
    expect(v.persistencePoints).toBe(8);
  });

  it('o terminal com moat supera o do estado estacionário', () => {
    const base = new DcfAssumptions({
      projectionYears: 10,
      growthRate: 0.08,
      perpetualGrowth: 0.05,
      discountRate: 0.14,
      terminalDiscountRate: 0.12,
      returnOnCapital: 0.3,
    });
    const neutral = DcfCalculator.terminalValue({ finalProfit: 100, assumptions: base }).unwrap();
    const withMoat = DcfCalculator.terminalValue({
      finalProfit: 100,
      assumptions: base.copyWith({ terminalReturnOnCapital: 0.174 }),
    }).unwrap();
    // Neutro: 105 / 0,12 = 875.
    expectClose(neutral, 875.0, 1e-9);
    // Moat: 105 x (1 - 0,05/0,174) / (0,12 - 0,05) = 1039,3...
    expectClose(withMoat, (105 * (1 - 0.05 / 0.174)) / 0.07, 1e-9);
    expect(withMoat).toBeGreaterThan(neutral);
  });

  it('o terminal com moat exige folga entre desconto e crescimento', () => {
    const tight = new DcfAssumptions({
      projectionYears: 10,
      growthRate: 0.08,
      perpetualGrowth: 0.119,
      discountRate: 0.14,
      terminalDiscountRate: 0.12,
      returnOnCapital: 0.3,
      terminalReturnOnCapital: 0.174,
    });
    const r = DcfCalculator.terminalValue({ finalProfit: 100, assumptions: tight });
    expect(r.isErr).toBe(true);
  });
});

describe('Constantes que carregam decisão', () => {
  it('horizonte de convergência é de 36 meses', () => {
    // Com 12 a anualização vira a identidade e o upside bruto passa a ser
    // lido como retorno anual — o defeito D1 da decisão 25.
    expect(ExpectedReturn.defaultHorizonMonths).toBe(36);
    const r = ExpectedReturn.annualizedFromUpside(1.0);
    expectClose(r, 0.2599, 1e-4, '(1 + 1,00)^(1/3) − 1, e não os 100% da identidade');
  });

  it('teto nominal compõe crescimento real medido com inflação', () => {
    const a = new MarketAnchors({
      riskFreeCagr: 0.1,
      marketCagr: 0.12,
      inflationCagr: 0.05,
      realEconomyGrowth: 0.0145,
      observedYears: 10,
    });
    expectClose(a.nominalEconomyGrowth, 0.0652, 1e-4);
  });

  it('projeção explícita é de dez anos', () => {
    const a = new DcfAssumptions({ growthRate: 0.1, perpetualGrowth: 0.04, discountRate: 0.12 });
    expect(a.projectionYears).toBe(10);
  });
});

// ------------------------------------------------------- Decisão 31 --

describe('Série de retorno — exercício de prejuízo entra', () => {
  it('a mediana do ciclo não é a mediana só dos anos bons', () => {
    // Forma da CVCB3: quatro exercícios de prejuízo numa janela de oito.
    // Descartá-los levava a mediana de ROIC de 0,55% para 33,8%, e o fator
    // de normalização — `ciclo ÷ atual` — carregava o viés inteiro para o
    // preço justo, porque o DCF é homogêneo de grau 1 no fluxo-base.
    const results = new Map<number, number>([
      [2016, 100.0],
      [2017, 110.0],
      [2018, -400.0],
      [2019, -350.0],
      [2020, -300.0],
      [2021, -250.0],
      [2022, 120.0],
      [2023, 130.0],
      [2024, 140.0],
      [2025, 150.0],
    ]);
    const points = [...results].map(([year, value]) =>
      fiscalYear(year, { bookValuePerShare: 1.0, shares: 1000, profit: value, nopat: value }),
    );
    const series = CapitalSeries.build(points, ValuationLane.firm);

    const withLoss = series.returns.filter((r) => r.value < 0).length;
    expect(withLoss, 'os quatro anos de prejuízo entram').toBe(4);

    const cycle = series.cycleReturn({ window: ValuationParameters.cycleWindow })!;
    expect(
      cycle,
      'a mediana de um ciclo com quatro anos de prejuízo não pode descrever só os anos bons',
    ).toBeLessThan(0.1);
  });

  it('exercício sem lucro publicado continua fora', () => {
    // Ausência de dado não é retorno nulo: incluí-la como zero inventaria
    // observação onde não há nenhuma.
    const points: FundamentalsSnapshot[] = [];
    for (let year = 2016; year <= 2025; year++) {
      points.push(
        fiscalYear(year, {
          bookValuePerShare: 1.0,
          shares: 1000,
          ...(year === 2020 ? {} : { profit: 100.0, nopat: 100.0 }),
        }),
      );
    }
    const series = CapitalSeries.build(points, ValuationLane.firm);
    expect(series.returns.some((r) => r.year === 2020)).toBe(false);
  });
});

describe('Guarda 1 — a deriva não depende do horizonte da tela', () => {
  it('o veredito é o mesmo qualquer que seja a projeção pedida', () => {
    // Forma da AZZA3: tendência de queda significante, com a deriva na
    // fronteira da correção por reversão. Medindo a deriva no horizonte,
    // `N = 10` dava dominância 1,49 e `N = 5` dava 0,74 — o veredito
    // virava, a base era normalizada por 2,50x e o preço justo saía de
    // R$ 16,11 para R$ 57,48 na mesma empresa, no mesmo dia.
    let pl = 1000.0;
    const points: FundamentalsSnapshot[] = [];
    for (let year = 2010; year <= 2025; year++) {
      const roic = 0.26 - 0.0175 * (year - 2010);
      const profit = roic * pl;
      points.push(fiscalYear(year, { bookValuePerShare: pl / 1000, shares: 1000, profit, nopat: profit }));
      pl += profit * 0.7;
    }
    const series = CapitalSeries.build(points, ValuationLane.firm);

    const v = GrowthGuards.trend(series);
    expect(v).not.toBeNull();
    expectClose(
      v!.dominance,
      GrowthGuards.trend(series)!.dominance,
      1e-12,
      'a guarda não tem mais por onde receber o horizonte',
    );

    // A janela é a do ciclo, e é a mesma sobre a qual a correção é medida.
    expect(ValuationParameters.trendDriftWindow).toBe(ValuationParameters.cycleWindow);
    const half = GrowthGuards.trend(series, { driftWindow: 4 })!;
    expectClose(
      half.dominance,
      v!.dominance / 2,
      1e-9,
      'a deriva é linear na janela, e o parâmetro só existe para a análise de sensibilidade',
    );
  });
});

describe('Contagem de papéis da ponte', () => {
  const withMarket = (o: {
    current: number;
    fiscalYearValue: number;
    marketValueOf: number;
    profit?: number;
    eps?: number;
  }): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(2025, 12, 31),
      bookValuePerShare: 10,
      sharesOutstanding: o.current,
      sharesOutstandingAsOf: o.fiscalYearValue,
      marketCap: o.marketValueOf,
      netIncome: o.profit ?? null,
      earningsPerShare: o.eps ?? null,
    });

  it('contagens que concordam: vale a implícita no valor de mercado', () => {
    // É a que forma o preço comparado, e adotá-la faz o potencial virar
    // `E ÷ VM − 1`, sem contagem de ação nenhuma no caminho.
    const s = withMarket({
      current: 206489810,
      fiscalYearValue: 206489810,
      marketValueOf: 206489810 * 17.69,
      profit: 911249000,
      eps: 4.413046,
    });
    const d = ValuationCascade.quotedShares({ latest: s, marketPrice: 17.69, sharesPerQuote: 1.0 });
    expect(d!.source).toBe(QuotedSharesSource.market);
    expect(d!.diverge).toBe(false);
    expectClose(d!.count, 206489810, 1);
  });

  it('na divergência vale a maior, e o mercado pode ser a maior', () => {
    // Forma da MOVI3: LPA publicado como zero, o árbitro `lucro ÷ LPA` fica
    // indisponível, e a contagem do exercício — 152.068.530 — era adotada
    // contra as 402.158.940 que formam o preço. Erro de 2,65x, direto no
    // preço justo, e no sentido de inflá-lo.
    const s = withMarket({
      current: 402158940,
      fiscalYearValue: 152068530,
      marketValueOf: 402158940 * 8.11,
      profit: 318364000,
      eps: 0.0,
    });
    const d = ValuationCascade.quotedShares({ latest: s, marketPrice: 8.11, sharesPerQuote: 1.0 });
    expect(d!.diverge).toBe(true);
    expect(d!.source).toBe(QuotedSharesSource.market);
    expectClose(d!.count, 402158940, 1);
    expect(
      s.reconciledShares,
      'a contagem contábil não muda: é ela que reconstrói o patrimônio publicado',
    ).toBe(152068530);
  });

  it('na divergência vale a maior, e a contábil pode ser a maior', () => {
    // Forma do MILS3: valor de mercado de R$ 760 mil, herdado de uma
    // contagem corrente corrompida de 48.172 papéis. Adotá-la daria preço
    // justo de R$ 37.708,72 contra R$ 15,79 de mercado — o sinal falso de
    // desconto levado ao absurdo.
    const s = withMarket({
      current: 48172,
      fiscalYearValue: 234178210,
      marketValueOf: 48172 * 15.79,
      profit: 1000000000,
      eps: 4.2646,
    });
    const d = ValuationCascade.quotedShares({ latest: s, marketPrice: 15.79, sharesPerQuote: 1.0 });
    expect(d!.diverge).toBe(true);
    expect(d!.source).toBe(QuotedSharesSource.reconciled);
    expectClose(d!.count, 234178210, 1);
    expect(d!.divergence!).toBeGreaterThan(1000);
  });

  it('a contábil entra na ponte já na unidade negociada', () => {
    // As demonstrações contam **ações**; a cotação e o valor de mercado vêm
    // por *unit*. Comparar as duas candidatas em unidades diferentes
    // escolheria a maior por erro de escala, não por conservadorismo.
    const s = withMarket({
      current: 503735170,
      fiscalYearValue: 1511205500,
      marketValueOf: 100747034 * 34.95,
      profit: 1000000000,
      eps: 0.6617,
    });
    const d = ValuationCascade.quotedShares({ latest: s, marketPrice: 34.95, sharesPerQuote: 5.0 });
    expectClose(d!.fromMarketCap!, 100747034, 1);
    expectClose(d!.fromStatements!, 1511205500 / 5, 1);
    expect(d!.source).toBe(QuotedSharesSource.reconciled);
    expectClose(d!.count, 302241100, 1);
  });

  it('sem valor de mercado, a contábil é a única disponível', () => {
    const s = withMarket({ current: 48172, fiscalYearValue: 234178210, marketValueOf: 0 });
    const d = ValuationCascade.quotedShares({ latest: s, marketPrice: 15.79, sharesPerQuote: 1.0 });
    expect(d!.source).toBe(QuotedSharesSource.onlyAvailable);
    expectClose(d!.count, 234178210, 1);
    expect(d!.diverge, 'não há duas candidatas a divergir').toBe(false);
  });

  describe('O registro oficial da B3 arbitra — decisão 83', () => {
    const today = day(2026, 9, 14);

    it('corrige a regra do maior quando a maior é a errada', () => {
      // Forma da CTKA4: a fonte dá 62 milhões correntes e no valor de
      // mercado, e 6,2 milhões no exercício. A regra do maior adotava 62, e o
      // preço justo saía dez vezes menor. A B3 registra 6.205.375.
      const s = withMarket({ current: 62053752, fiscalYearValue: 6205375, marketValueOf: 62053751 * 3.0 });
      const before = ValuationCascade.quotedShares({ latest: s, marketPrice: 3.0, sharesPerQuote: 1.0 });
      expectClose(before!.count, 62053751, 1);
      const d = ValuationCascade.quotedShares({
        latest: s,
        marketPrice: 3.0,
        sharesPerQuote: 1.0,
        official: new OfficialShareCount({ total: 6205375, asOf: today }),
        asOf: today,
      });
      expect(d!.source).toBe(QuotedSharesSource.official);
      expectClose(d!.count, 6205375, 1);
    });

    it('desconta a tesouraria pela fração, e entra na unidade negociada', () => {
      const s = new FundamentalsSnapshot({
        ticker,
        fiscalPeriodEnd: day(2025, 12, 31),
        sharesOutstanding: 1000,
        sharesOutstandingAsOf: 1000,
        marketCap: 200 * 10.0,
        treasuryFraction: 0.04,
        // Contagem absoluta em outra escala: não pode entrar.
        treasuryShares: 40000,
      });
      const d = ValuationCascade.quotedShares({
        latest: s,
        marketPrice: 10.0,
        sharesPerQuote: 5.0,
        official: new OfficialShareCount({ total: 1000, asOf: today }),
        asOf: today,
      });
      expect(d!.source).toBe(QuotedSharesSource.official);
      expectClose(d!.count, 960 / 5, 1e-9);
    });

    it('registro antigo que diverge das duas não é usado', () => {
      // Um desdobramento depois da consulta: a fonte já dobrou, o registro
      // não. Adotá-lo daria o preço justo em dobro.
      const s = withMarket({ current: 2000, fiscalYearValue: 2000, marketValueOf: 2000 * 5.0 });
      const d = ValuationCascade.quotedShares({
        latest: s,
        marketPrice: 5.0,
        sharesPerQuote: 1.0,
        official: new OfficialShareCount({ total: 1000, asOf: day(2026, 6, 1) }),
        asOf: today,
      });
      expect(d!.source).toBe(QuotedSharesSource.market);
      expect(d!.fromRegistry, 'recusado, mas registrado').toBe(1000);
    });

    it('registro antigo que concorda com a fonte é usado', () => {
      const s = withMarket({ current: 1030, fiscalYearValue: 1030, marketValueOf: 1030 * 5.0 });
      const d = ValuationCascade.quotedShares({
        latest: s,
        marketPrice: 5.0,
        sharesPerQuote: 1.0,
        official: new OfficialShareCount({ total: 1000, asOf: day(2026, 6, 1) }),
        asOf: today,
      });
      expect(d!.source).toBe(QuotedSharesSource.official);
      expect(d!.count).toBe(1000);
    });

    it('registro consultado depois da avaliação não existia nela', () => {
      const s = withMarket({ current: 2000, fiscalYearValue: 2000, marketValueOf: 2000 * 5.0 });
      const d = ValuationCascade.quotedShares({
        latest: s,
        marketPrice: 5.0,
        sharesPerQuote: 1.0,
        official: new OfficialShareCount({ total: 1000, asOf: today }),
        asOf: day(2024, 9, 4),
      });
      expect(d!.source).toBe(QuotedSharesSource.market);
      expect(d!.fromRegistry).toBeNull();
    });
  });
});

describe('Ponte de equity — recusa nomeada quando não há o que repartir', () => {
  /**
   * Empresa com fluxo de firma positivo e dívida líquida maior que o valor
   * da firma: o fluxo do acionista derivado do da firma não sustenta capital
   * próprio positivo, e desde a decisão 102 nenhuma outra via é tentada.
   */
  const drownedSeries = (): FundamentalsSnapshot[] => {
    const points: FundamentalsSnapshot[] = [];
    let pl = 1000.0;
    for (let year = 2012; year <= 2025; year++) {
      pl += 20.0;
      points.push(
        new FundamentalsSnapshot({
          ticker,
          fiscalPeriodEnd: day(year, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          marketCap: 20000,
          netIncome: -50.0,
          nopat: 30.0,
          ebit: 45.0,
          ebitda: 60.0,
          interestExpense: 400.0,
          longTermDebt: 900000.0,
        }),
      );
    }
    return points;
  };

  it('a recusa nomeia o motivo, e não devolve resíduo de subtração', () => {
    const r = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 6, 30),
        fundamentals: drownedSeries(),
        marketPrice: 20.0,
        capm: new CapmInputs({ riskFreeRate: 0.105, beta: 1.0, marketPremium: 0.055 }),
      }),
    );
    expect(r.isErr).toBe(true);
    const msg = r.failureOrNull!.message;
    expect(msg).toContain('não sustenta capital próprio positivo');
    expect(msg).toContain('não é avaliável por fluxo descontado');
    expect(msg, 'participação não positiva não pode virar 1/0 na mensagem').not.toContain('Infinity');
  });
});

describe('Diagnósticos — o resultado diz o que a conta fez', () => {
  it('não há nota ordinal de confiança, e a ausência é medida', () => {
    // A primeira versão trazia `ValuationConfidence` derivada da contagem de
    // ressalvas. A validação preditiva da decisão 32 mediu o contrário do
    // prometido: em 36 meses, o grupo sem ressalva alguma teve IC de −0,007
    // (positivo em 2 de 5 coortes) e o grupo com uma ou duas teve 0,206
    // (5 de 5). Uma nota que ordena ao contrário é pior que nenhuma.
    const d = new ValuationDiagnostics({
      terminalShare: 0.5,
      equityShare: 0.8,
      baseFactor: 1.0,
      growthIdentified: true,
      moatApplied: false,
      costOfEquity: 0.16,
      terminalDiscountRate: 0.12,
      terminalRetainedSpread: 0.0,
      growthRate: 0.06,
      returnOnCapital: 0.15,
      terminalReturnOnCapital: null,
    });
    expect(d.caveats).toEqual([]);
  });

  it('a ressalva de custo da dívida não está no conjunto', () => {
    // Ela disparava em 469 das 821 avaliações do backtest. Ressalva que vale
    // para a maioria não distingue nada, e a classificação sintética virou
    // método pela decisão 31 — não é mais um recuo a declarar aqui.
    expect(ValuationCaveat.values.map((c) => c.key)).not.toContain('custoDaDividaEstimado');
  });

  it('os cortes carregam a decisão que os originou', () => {
    // 80% é o topo da faixa que a decisão 25 citou para justificar dez anos
    // de projeção em vez de cinco; 2,0x é metade da autoridade que a
    // saturação da decisão 28 concede a um único exercício; 35% é a faixa em
    // que o capital próprio fino amplifica o erro do fluxo — declarada, e,
    // desde a decisão 102, nunca motivo para trocar de via.
    expect(ValuationDiagnostics.terminalShareLimit).toBe(0.8);
    expect(ValuationDiagnostics.baseFactorLimit).toBe(2.0);
    expect(ValuationDiagnostics.fragileEquityShare).toBe(0.35);
  });

  it('resultado montado à mão não inventa diagnóstico', () => {
    const r = new ValuationResult({
      ticker,
      asOf: day(2026, 9, 4),
      model: ValuationModel.dcfFcff,
      fairValue: Money.fromReais(10),
      marketPrice: Money.fromReais(8),
      discountRate: 0.15,
    });
    expect(r.diagnostics).toBeNull();
    expect(r.caveats).toEqual([]);
  });

  it('a cascata preenche o diagnóstico com o que ela mesma apurou', () => {
    const points: FundamentalsSnapshot[] = [];
    let pl = 1000.0;
    for (let year = 2012; year <= 2025; year++) {
      const profit = 0.15 * pl;
      pl += profit * 0.5;
      points.push(
        new FundamentalsSnapshot({
          ticker,
          fiscalPeriodEnd: day(year, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          marketCap: 20000,
          netIncome: profit,
          nopat: profit,
          ebit: profit * 1.4,
          ebitda: profit * 1.8,
          interestExpense: 50,
          longTermDebt: 500,
        }),
      );
    }
    const r = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 6, 30),
        fundamentals: points,
        marketPrice: 20.0,
        capm: new CapmInputs({ riskFreeRate: 0.105, beta: 1.0, marketPremium: 0.055 }),
      }),
    );
    expect(r.isOk).toBe(true);
    const d = r.unwrap().diagnostics;
    expect(d).not.toBeNull();
    expect(d!.terminalShare).toBeGreaterThan(0.0);
    expect(d!.terminalShare).toBeLessThan(1.0);
    expect(d!.baseFactor).toBeGreaterThan(0.0);
    expect(d!.equityShare).toBeGreaterThan(0.0);
  });
});

describe('Consistência da base acionária entre exercícios', () => {
  const ex = (year: number, shares: number, bookValuePerShare: number): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(year, 12, 31),
      sharesOutstandingAsOf: shares,
      sharesOutstanding: 1259387000,
      bookValuePerShare,
      marketCap: 49317593000,
    });

  it('falha de escala da fonte é descartada do divisor', () => {
    // Forma da EQTL3: o exercício de 2024 vem com 246.152 ações contra 1,50
    // bilhão em 2023 e 1,26 bilhão em 2025, e o VPA acompanha em
    // R$ 121.419,23. O patrimônio sai certo porque o erro se cancela em
    // `VPA × N`; o divisor da ponte, que usa `N` sozinho, sairia cinco mil
    // vezes errado.
    const series = [
      ex(2021, 1128934500, 12.94),
      ex(2022, 1129315500, 16.44),
      ex(2023, 1500000000, 16.86),
      ex(2024, 246152, 121419.23),
    ];
    expect(ValuationCascade.shareBaseIsConsistent(series, series[series.length - 1]!)).toBe(false);

    const d = ValuationCascade.quotedShares({
      latest: series[series.length - 1]!,
      marketPrice: 39.36,
      sharesPerQuote: 1.0,
      published: series,
    });
    expect(d).not.toBeNull();
    expect(d!.fromStatements, 'a contagem quebrada não pode entrar como candidata').toBeNull();
    expect(d!.source).toBe(QuotedSharesSource.onlyAvailable);
    expectClose(d!.count, 49317593000 / 39.36, 1);
  });

  it('ação societária real passa, e é o ponto do fator ser largo', () => {
    // Forma da VIVT3: a base dobra em 2024 — 1,65 para 3,26 bilhões — com o
    // VPA caindo de R$ 42,13 para R$ 21,40. `VPA × N` fica estável em
    // R$ 69 bilhões o tempo todo: foi desdobramento, não erro.
    const series = [
      ex(2021, 1690985000, 41.4),
      ex(2022, 1676938200, 40.82),
      ex(2023, 1652588400, 42.13),
      ex(2024, 3261287400, 21.4),
    ];
    expect(
      ValuationCascade.shareBaseIsConsistent(series, series[series.length - 1]!),
      'dobrar a base é ação societária; o corte é de ordem de grandeza, não de fator dois',
    ).toBe(true);
  });

  it('série curta demais aprova em vez de reprovar', () => {
    // Mesmo critério da Porta 0 com a liquidez: sem vizinhança contra a qual
    // julgar, ausência de informação não é evidência de defeito.
    const series = [ex(2024, 246152, 121419.23)];
    expect(ValuationCascade.shareBaseIsConsistent(series, series[0]!)).toBe(true);
    expect(ValuationCascade.shareBaseIsConsistent([], series[0]!)).toBe(true);
  });

  it('o corte é o mesmo que a série de capital já usa', () => {
    // Duas cópias do mesmo limiar divergiriam na primeira recalibragem, e o
    // raciocínio é idêntico: falha de fonte é de ordem de grandeza, salto
    // societário fica entre duas e nove vezes.
    expect(CapitalSeries.neighbourFactor).toBe(8.0);
  });
});

describe('Escudo fiscal e custo da dívida', () => {
  it('o escudo do WACC é a alíquota estatutária', () => {
    // A fonte publica `nopat` como `EBIT × 0,66` em 4.572 de 4.572
    // exercícios do cache: o fluxo da firma já vinha apurado à alíquota
    // legal, e só o escudo do desconto não vinha. O parâmetro fica travado
    // aqui para que a incoerência não volte por descuido.
    expect(ValuationParameters.statutoryTaxRate).toBe(0.34);
  });

  it('a alavancagem ordena o prêmio, e é monótona', () => {
    const spread = (l: number | null): number => CostOfCapital.leverageSpread(l);
    expect(spread(-0.5)).toBeLessThan(spread(1.5));
    expect(spread(1.5)).toBeLessThan(spread(2.8));
    expect(spread(2.8)).toBeLessThan(spread(4.5));
    expect(spread(6.0)).toBe(CostOfCapital.maxCreditSpread);
    expect(spread(null), 'sem EBITDA positivo vale o pior caso').toBe(CostOfCapital.maxCreditSpread);
    let previous = 0.0;
    for (let l = -2.0; l <= 8.0; l += 0.1) {
      const current = spread(l);
      expect(current, `prêmio caiu ao subir a alavancagem em ${l}`).toBeGreaterThanOrEqual(previous);
      previous = current;
    }
  });

  it('a despesa financeira arbitra se a cobertura pode falar', () => {
    const rf = 0.1409;
    const s = (o: { obs: number; coverage?: number; lev?: number }): number =>
      CostOfCapital.syntheticSpread({
        leverage: o.lev ?? null,
        coverage: o.coverage ?? null,
        observedCostOfDebt: o.obs,
        riskFreeRate: rf,
      });

    // Forma da SAPR11: despesa observada de 41,7% ao ano é contaminada por
    // arrendamento e variação cambial. A cobertura de 0,76x que sai dela não
    // pode decidir o crédito de quem tem 0,60x de alavancagem.
    expect(s({ obs: 0.417, coverage: 0.76, lev: 0.6 })).toBe(CostOfCapital.leverageSpread(0.6));

    // Forma da MOVI3: despesa de 16,4% ao ano é juro de dívida de verdade.
    // A cobertura de 0,91x é informação, e ela é mais exigente que a
    // alavancagem de 3,13x — vale a pior das duas.
    const movi = s({ obs: 0.164, coverage: 0.91, lev: 3.13 });
    expect(movi).toBe(CostOfCapital.coverageSpread(0.91));
    expect(movi).toBeGreaterThan(CostOfCapital.leverageSpread(3.13));

    // Dentro da banda, mas com cobertura folgada: quem manda é a alavancagem.
    expect(s({ obs: 0.16, coverage: 9.0, lev: 4.5 })).toBe(CostOfCapital.leverageSpread(4.5));

    // Abaixo do piso a despesa também não serve: dívida subsidiada não
    // descreve o custo marginal de captar.
    expect(s({ obs: 0.02, coverage: 44.0, lev: 1.45 })).toBe(CostOfCapital.leverageSpread(1.45));
  });
});

describe('Fronteira das vias e monotonia na taxa', () => {
  // A pós-condição da ponte de equity era um degrau entre dois estimadores
  // diferentes, e medi-la na taxa do dia fazia o degrau andar com o ciclo
  // monetário (decisão 34); a rampa da decisão 38 trocou o degrau por uma
  // mistura, e a mistura continuava subindo com a taxa. **Desde a decisão
  // 102 não há fronteira**: a via da firma é a via da firma em toda taxa, e o
  // capital próprio fino é ressalva, e não troca de modelo. Este fixture é
  // alavancado de propósito, para atravessar a faixa que migrava.
  const leveredYear = (year: number, scale: number): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(year, 12, 31),
      totalRevenue: 10000 * scale,
      ebit: 1400 * scale,
      ebitda: 1900 * scale,
      netIncome: 500 * scale,
      incomeBeforeTax: 800 * scale,
      // Negativo, na convenção da fonte: 800 − 300 = 500 de líquido.
      incomeTaxExpense: -300 * scale,
      interestExpense: 600,
      earningsPerShare: 0.5 * scale,
      cash: 500,
      shortTermInvestments: 200,
      shortTermDebt: 3200,
      longTermDebt: 12800,
      totalStockholderEquity: 4000 * scale,
      bookValuePerShare: 4.0 * scale,
      operatingCashFlow: 1500 * scale,
      freeCashFlow: 900 * scale,
      nopat: 924 * scale,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 9000,
      enterpriseToEbitda: 8.0,
    });

  const series = (): FundamentalsSnapshot[] => {
    const out: FundamentalsSnapshot[] = [];
    let scale = 1.0;
    for (let i = 15; i >= 0; i--) {
      out.push(leveredYear(2025 - i, scale));
      scale *= 1.06;
    }
    return out;
  };

  type Extra = Partial<ConstructorParameters<typeof ValuationInputs>[0]>;
  const evaluateWith = (rf: number, extra: Extra = {}): ValuationResult | null => {
    const r = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series(),
        marketPrice: 9.0,
        capm: new CapmInputs({ riskFreeRate: rf, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
        ...extra,
      }),
    );
    return r.isOk ? r.unwrap() : null;
  };
  const withInput = (rf: number): ValuationResult | null => evaluateWith(rf);

  it('baratear o capital nunca derruba o preço justo', () => {
    let previous: number | null = null;
    let evaluated = 0;
    for (let step = 0; step <= 32; step++) {
      const rf = 0.16 - step * 0.0025;
      const v = withInput(rf);
      if (v === null) continue;
      const fairValue = v.fairValue.reais;
      evaluated++;
      if (previous !== null) {
        // A tolerância de um centavo é ruído de arredondamento em `Money`,
        // não folga de regra: a quebra medida era de 33%.
        expect(
          fairValue,
          `em Rf de ${toStringAsFixed(rf * 100, 2)}% o preço justo caiu de ${previous} para ${fairValue} ao baratear o capital`,
        ).toBeGreaterThanOrEqual(previous - 0.01);
      }
      previous = fairValue;
    }
    expect(evaluated, 'a varredura precisa cobrir a faixa para ter conteúdo').toBeGreaterThan(20);
  });

  it('NÃO há degrau: o preço justo é contínuo na taxa', () => {
    // É o defeito que a decisão 38 corrige. A pós-condição escolhia uma via
    // inteira em s = 20%, e as duas discordam além de 1,5x em 55 de 92
    // ativos — a VBBR3 saía a R$ 2,65 pela firma ou R$ 33,71 pelo acionista.
    // Cruzar o corte fazia o preço justo saltar por múltiplos.
    let previous: number | null = null;
    let largestJump = 0.0;
    let evaluated = 0;
    for (let step = 0; step <= 60; step++) {
      const fairValue = withInput(0.16 - step * 0.001)?.fairValue.reais ?? null;
      if (fairValue === null || fairValue <= 0) continue;
      evaluated++;
      if (previous !== null) {
        const jump = Math.abs(fairValue / previous - 1);
        if (jump > largestJump) largestJump = jump;
      }
      previous = fairValue;
    }
    expect(evaluated, 'a varredura precisa cobrir a faixa para ter conteúdo').toBeGreaterThan(40);
    // Dez pontos-base de taxa não movem um fluxo descontado em mais de uns
    // poucos por cento. Um degrau de via move por múltiplos.
    expect(
      largestJump,
      `salto de ${toStringAsFixed(largestJump * 100, 1)}% entre dois passos de 10 pontos-base é degrau de via, não desconto`,
    ).toBeLessThan(0.15);
  });

  it('não há faixa de transição: o justo é o da via da firma em toda taxa', () => {
    const byLane = (rf: number, lane: ValuationLane | null): ValuationResult | null =>
      evaluateWith(rf, { laneOverride: lane });

    let fragileCount = 0;
    let evaluated = 0;
    for (let step = 0; step <= 60; step++) {
      const rf = 0.16 - step * 0.001;
      const production = byLane(rf, null);
      if (production === null) continue;
      evaluated++;
      expect(production.model).toBe(ValuationModel.dcfFcff);
      const caveats = production.diagnostics!.caveats;
      expect(caveats).not.toContain(ValuationCaveat.mergedLanes);
      expect(caveats).not.toContain(ValuationCaveat.migratedLane);
      if (caveats.includes(ValuationCaveat.fragileBridge)) fragileCount++;
      // A mesma conta que a via imposta faz: não há segunda via na mistura.
      expect(production.fairValue.cents).toBe(byLane(rf, ValuationLane.firm)!.fairValue.cents);
    }
    expect(evaluated).toBeGreaterThan(40);
    expect(
      fragileCount,
      'a varredura precisa atravessar o capital próprio fino que migrava — se não atravessar, o teste não mede o que promete',
    ).toBeGreaterThan(0);
  });

  it('deslocar o nível da curva inteira não faz o preço justo subir com a taxa — o critério do B10', () => {
    // A decisão 34 resolvia a taxa corrente, e não o nível: deslocar as duas
    // taxas juntas movia a participação estrutural, e a fronteira voltava a
    // ser cruzada — 46 de 122 ativos no `dcf_reverso`, 25 de 128 na varredura
    // do aplicativo em 16/09/2026.
    const base = new ValuationInputs({
      ticker,
      asOf: day(2026, 9, 9),
      fundamentals: series(),
      marketPrice: 9.0,
      capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
      declaredTerminalRiskFreeRate: 0.094,
    });
    let previous: number | null = null;
    const models = new Set<ValuationModel>();
    let evaluated = 0;
    for (let step = -40; step <= 40; step++) {
      const r = ValuationCascade.evaluate(base.withRiskFreeShift(step * 0.001));
      if (r.isErr) {
        previous = null;
        continue;
      }
      const v = r.unwrap();
      evaluated++;
      models.add(v.model);
      const fairValue = v.fairValue.reais;
      if (previous !== null) {
        expect(
          fairValue,
          `no deslocamento de ${toStringAsFixed(step / 10, 1)} p.p. o preço justo subiu de ${previous} para ${fairValue} com a taxa`,
        ).toBeLessThanOrEqual(previous + 0.01);
      }
      previous = fairValue;
    }
    expect(evaluated).toBeGreaterThan(60);
    expect([...models]).toEqual([ValuationModel.dcfFcff]);
  });

  it('crescimento e fator impostos são nulos em produção', () => {
    // As duas costuras do teste A1 não podem mover nada quando não são
    // usadas: elas existem para medir o motor, não para ser o motor.
    const production = withInput(0.14);
    const withNulls = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series(),
        marketPrice: 9.0,
        capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
        growthOverride: null,
        baseFactorOverride: null,
      }),
    );
    expect(production).not.toBeNull();
    expect(withNulls.isOk).toBe(true);
    expect(withNulls.unwrap().fairValue.cents).toBe(production!.fairValue.cents);
  });

  it('crescimento imposto entra no cálculo e é declarado', () => {
    const withG = (g: number | null): ValuationResult | null =>
      evaluateWith(0.14, { laneOverride: ValuationLane.firm, growthOverride: g });

    const low = withG(0.02);
    const high = withG(0.09);
    expect(low).not.toBeNull();
    expect(high).not.toBeNull();
    expectClose(high!.diagnostics!.growthRate, 0.09, 1e-12);
    expectClose(low!.diagnostics!.growthRate, 0.02, 1e-12);
    // **Crescer mais não vale mais por princípio**, e o fixture mostra por
    // quê: com o retorno da base abaixo do custo de capital, o freio
    // `b = g/ROIC` cobra mais reinvestimento do que o crescimento devolve, e
    // o valor cai. É a economia do modelo, não defeito — e é o sinal certo
    // para travar, porque um motor que premiasse crescimento indiscriminado
    // estaria errado.
    expect(
      high!.diagnostics!.returnOnCapital,
      'o fixture precisa estar no regime de retorno abaixo do custo de capital para o teste significar isto',
    ).toBeLessThan(high!.diagnostics!.terminalDiscountRate);
    expect(high!.fairValue.cents, 'crescimento sem retorno excedente destrói valor').toBeLessThan(
      low!.fairValue.cents,
    );
    expect(
      Math.abs(high!.fairValue.cents - low!.fairValue.cents),
      'sem efeito algum, a varredura de A1 não mediria nada',
    ).toBeGreaterThan(0);
    expect(high!.warnings.some((w) => w.includes('Crescimento imposto'))).toBe(true);
  });

  it('fator de base imposto multiplica o preço justo, e é declarado', () => {
    const withF = (f: number): ValuationResult | null =>
      evaluateWith(0.14, { laneOverride: ValuationLane.firm, baseFactorOverride: f });

    const one = withF(1.0);
    const two = withF(2.0);
    expect(one).not.toBeNull();
    expect(two).not.toBeNull();
    expectClose(two!.diagnostics!.baseFactor, 2.0, 1e-12);
    // O DCF é homogêneo de grau 1 no fluxo-base, e a ponte de dívida
    // líquida é o que impede a razão de ser exatamente 2.
    expect(two!.fairValue.cents).toBeGreaterThan(one!.fairValue.cents);
    expect(two!.warnings.some((w) => w.includes('Fator de normalização imposto'))).toBe(true);
  });

  it('com ou sem o caminho resolvido, o capital próprio não passa pela ponte, e nada é mesclado', () => {
    // O fixture é alavancado de propósito: sob a ponte ele atravessava a
    // pós-condição dos 20% e recebia a mescla da decisão 38. Com o caminho
    // resolvido já não havia ponte (decisão 43); sem ele, desde a decisão 102,
    // também não.
    const evaluate = (o: { betaU?: number | null; rf: number }): ValuationResult | null =>
      evaluateWith(o.rf, { unleveredBeta: o.betaU ?? null });

    let evaluatedWithout = 0;
    let evaluatedWith = 0;
    for (let step = 0; step <= 40; step++) {
      const rf = 0.16 - step * 0.0015;
      for (const [betaU, account] of [
        [null, 0],
        [0.6, 1],
      ] as const) {
        const v = evaluate({ betaU, rf });
        if (v === null) continue;
        if (account === 0) {
          evaluatedWithout++;
        } else {
          evaluatedWith++;
        }
        expect(v.diagnostics!.caveats).not.toContain(ValuationCaveat.mergedLanes);
      }
    }
    expect(evaluatedWithout, 'a varredura precisa cobrir a faixa para ter conteúdo').toBeGreaterThan(20);
    expect(evaluatedWith, 'a varredura precisa cobrir a faixa para ter conteúdo').toBeGreaterThan(20);
  });

  it('a rota derivada é contínua na taxa, sem degrau de ponte', () => {
    const fairValue = (rf: number): number | null => evaluateWith(rf, { unleveredBeta: 0.6 })?.fairValue.reais ?? null;

    let previous: number | null = null;
    let largestJump = 0.0;
    let evaluated = 0;
    for (let step = 0; step <= 50; step++) {
      const v = fairValue(0.16 - step * 0.001);
      if (v === null || v <= 0) continue;
      evaluated++;
      if (previous !== null) {
        const jump = Math.abs(v / previous - 1);
        if (jump > largestJump) largestJump = jump;
      }
      previous = v;
    }
    expect(evaluated).toBeGreaterThan(30);
    expect(
      largestJump,
      `salto de ${toStringAsFixed(largestJump * 100, 1)}% entre dois passos de 10 pontos-base seria degrau, não desconto`,
    ).toBeLessThan(0.15);
  });

  it('a narrativa do moat cita a taxa resolvida, não a interpolada', () => {
    // D1d: o veredito de vantagem competitiva é fechado contra a taxa que o
    // ponto fixo devolve. Publicá-lo contra a interpolada afirmaria um
    // veredito que a conta final descartou.
    const v = evaluateWith(0.14, { laneOverride: ValuationLane.firm, unleveredBeta: 0.6 });
    expect(v).not.toBeNull();
    const narrative = v!.warnings.filter((w) => w.startsWith('Vantagem competitiva residual:'));
    if (narrative.length === 0) return; // este fixture pode não ter excedente
    const pct = toStringAsFixed(v!.diagnostics!.terminalDiscountRate * 100, 1);
    expect(narrative.length).toBe(1);
    expect(narrative[0], 'a taxa citada tem de ser a que o diagnóstico carrega').toContain(`equilíbrio de ${pct}%`);
  });

  it('sem beta desalavancado, o desconto é a interpolação de antes', () => {
    // O caminho novo é opcional por construção: quem não tem `β_U` continua
    // exatamente onde estava. É o que permite ligá-lo sem quebrar o que a
    // fonte não sustenta.
    const production = withInput(0.14);
    expect(production).not.toBeNull();
    expect(production!.warnings.some((w) => w.includes('resolvido ano a ano'))).toBe(false);
  });

  it('com beta desalavancado, o custo de capital é resolvido e declarado', () => {
    const withBetaU = (betaU: number | null): ValuationResult | null =>
      evaluateWith(0.14, { laneOverride: ValuationLane.firm, unleveredBeta: betaU });

    const without = withBetaU(null);
    const withU = withBetaU(0.6);
    expect(without).not.toBeNull();
    expect(withU).not.toBeNull();

    expect(
      withU!.warnings.some((w) => w.includes('resolvido ano a ano')),
      'o resultado precisa declarar que a taxa virou caminho',
    ).toBe(true);
    expect(
      withU!.warnings.some((w) => w.includes('participação do capital próprio sai de')),
      'e precisa dizer quanto a alavancagem se moveu',
    ).toBe(true);

    // O fixture é alavancado: resolver a taxa contra a alavancagem tem de
    // mover o número. Sem efeito, a decisão 41 não estaria ligada.
    expect(withU!.fairValue.cents).not.toBe(without!.fairValue.cents);
  });

  it('o terminal do diagnóstico é o resolvido, não o interpolado', () => {
    const v = evaluateWith(0.14, { laneOverride: ValuationLane.firm, unleveredBeta: 0.6 });
    expect(v).not.toBeNull();
    const d = v!.diagnostics!;
    // O texto do aviso traz a mesma taxa que o diagnóstico carrega: se os
    // dois divergissem, um relatório contaria uma história e a máquina
    // outra.
    const warning = v!.warnings.find((w) => w.includes('perpetuidade é descontada a'));
    expect(warning).not.toBeUndefined();
    const pct = toStringAsFixed(d.terminalDiscountRate * 100, 1);
    expect(warning).toContain(`${pct}%`);
  });

  it('a via imposta ignora o roteamento, e declara', () => {
    const v = evaluateWith(0.14, { laneOverride: ValuationLane.firm });
    expect(v).not.toBeNull();
    expect(v!.model).toBe(ValuationModel.dcfFcff);
    expect(
      v!.warnings.some((w) => w.includes('Via imposta')),
      'o resultado precisa declarar que é instrumento, não avaliação',
    ).toBe(true);
    expect(
      v!.diagnostics!.caveats.includes(ValuationCaveat.mergedLanes),
      'nada mescla desde a decisão 102, e a via imposta muito menos',
    ).toBe(false);
  });

  it('a via não muda com a taxa livre de risco corrente', () => {
    const lanes = new Set<ValuationModel>();
    for (let step = 0; step <= 16; step++) {
      const v = withInput(0.16 - step * 0.005);
      if (v !== null) lanes.add(v.model);
    }
    expect(
      lanes.size,
      'a estrutura de capital é fato de longo prazo; qual via a descreve não pode depender de onde a Selic está hoje',
    ).toBe(1);
  });
});

describe('Retorno terminal imposto — a costura do DCF reverso', () => {
  // `terminalReturnOverride` existe para a varredura da decisão 35. Ele é a
  // única entrada capaz de mudar o valor terminal de fora, e por isso precisa
  // de três garantias travadas: não fazer nada quando nulo, mandar quando
  // preenchido, e não se passar por vantagem competitiva reconhecida.
  const scaledYear = (year: number, scale: number): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(year, 12, 31),
      totalRevenue: 10000 * scale,
      ebit: 1400 * scale,
      ebitda: 1900 * scale,
      netIncome: 700 * scale,
      incomeBeforeTax: 1060 * scale,
      // Negativo, na convenção da fonte: 1060 − 360 = 700 de líquido.
      incomeTaxExpense: -360 * scale,
      interestExpense: 120,
      earningsPerShare: 0.7 * scale,
      cash: 800,
      shortTermInvestments: 200,
      shortTermDebt: 400,
      longTermDebt: 1600,
      totalStockholderEquity: 5000 * scale,
      bookValuePerShare: 5.0 * scale,
      operatingCashFlow: 1500 * scale,
      freeCashFlow: 900 * scale,
      nopat: 924 * scale,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 12000,
      enterpriseToEbitda: 8.0,
    });

  const series = (): FundamentalsSnapshot[] => {
    const out: FundamentalsSnapshot[] = [];
    let scale = 1.0;
    for (let i = 15; i >= 0; i--) {
      out.push(scaledYear(2025 - i, scale));
      scale *= 1.05;
    }
    return out;
  };

  const withInput = (tax: number | null): ValuationResult | null => {
    const r = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series(),
        marketPrice: 12.0,
        capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
        terminalReturnOverride: tax,
      }),
    );
    return r.isOk ? r.unwrap() : null;
  };

  it('nulo é exatamente o comportamento de produção', () => {
    const withoutField = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series(),
        marketPrice: 12.0,
        capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
      }),
    );
    const withNull = withInput(null);
    expect(withoutField.isOk).toBe(true);
    expect(withNull).not.toBeNull();
    expectClose(withNull!.fairValue.reais, withoutField.unwrap().fairValue.reais, 1e-9);
  });

  it('retorno terminal maior não reduz o preço justo', () => {
    // Monotonia é o que a varredura por bissecção pressupõe dentro do
    // intervalo que ela isola. Se ela quebrasse aqui, a raiz não teria
    // significado.
    const low = withInput(0.1);
    const high = withInput(0.4);
    expect(low).not.toBeNull();
    expect(high).not.toBeNull();
    expect(high!.fairValue.reais).toBeGreaterThanOrEqual(low!.fairValue.reais - 0.01);
    expect(high!.fairValue.reais, 'sem efeito algum, a varredura da decisão 35 não mede nada').toBeGreaterThan(
      low!.fairValue.reais,
    );
  });

  it('imposição não se passa por vantagem competitiva reconhecida', () => {
    const v = withInput(0.4);
    const production = withInput(null);
    expect(v).not.toBeNull();
    expect(production).not.toBeNull();
    // A bandeira e o retorno imposto são grandezas distintas: `moatApplied`
    // alimenta relatório de cobertura, e varredura de diagnóstico não é
    // veredito. O que se trava é que a imposição **não move a bandeira** —
    // e não que ela seja falsa, que depende do ativo do fixture.
    expect(v!.diagnostics!.moatApplied, 'a imposição não pode criar nem apagar veredito').toBe(
      production!.diagnostics!.moatApplied,
    );
    expect(v!.diagnostics!.terminalRetainedSpread, 'lambda é do veredito, não do valor imposto').toBe(
      production!.diagnostics!.terminalRetainedSpread,
    );
    expect(
      v!.warnings.some((w) => w.includes('imposto')),
      'o resultado precisa declarar que é instrumento, não avaliação',
    ).toBe(true);
    expect(
      v!.warnings.some((w) => w.includes('Vantagem competitiva residual:')),
      'a narrativa do veredito não sai junto com a imposição',
    ).toBe(false);
  });
});

describe('Caixa rende taxa livre de risco, e não o WACC', () => {
  // Sem dívida bruta não há custo de dívida a medir, e o recuo era a própria
  // taxa de desconto. Com dívida líquida **negativa** ela multiplica um peso
  // negativo: o motor creditava ao caixa o rendimento do negócio. Medido em
  // 11/09/2026, a ALOS3 — R$ 2,43 bi de caixa líquido — caiu 10,5% ao trocar
  // o recuo pela taxa livre de risco. Decisão 58.
  const assumptions = new DcfAssumptions({
    projectionYears: 5,
    growthRate: 0.04,
    perpetualGrowth: 0.04,
    discountRate: 0.12,
    terminalDiscountRate: 0.12,
    returnOnCapital: 0.0,
  });

  const fairWith = (kd: number, o: { netDebt: number }): number =>
    DcfCalculator.equityFromFirm({
      baseProfit: 100,
      assumptions,
      netDebt: o.netDebt,
      sharesOutstanding: 10,
      costOfDebt: kd,
      taxRate: 0.34,
      equityDiscountRate: 0.14,
      terminalEquityDiscountRate: 0.14,
    }).unwrap().fairValuePerShare;

  it('com caixa líquido, o rendimento atribuído a ele decide o preço', () => {
    const rf = 0.09;
    const wacc = 0.12;
    const withRf = fairWith(rf, { netDebt: -400 });
    const withWacc = fairWith(wacc, { netDebt: -400 });
    expect(
      withWacc,
      'creditar o WACC ao caixa infla o fluxo do acionista — é exatamente o que o recuo antigo fazia',
    ).toBeGreaterThan(withRf);
    expect(Math.abs(withWacc / withRf - 1), 'se a diferença fosse desprezível o teste não mediria nada').toBeGreaterThan(
      0.01,
    );
  });

  it('sem dívida líquida, o rendimento do caixa não decide nada', () => {
    // O termo da ponte é `D·(kd(1−τ) − g)`: com `D = 0` ele some, e a
    // escolha do recuo deixa de importar.
    expectClose(fairWith(0.09, { netDebt: 0 }), fairWith(0.3, { netDebt: 0 }), 1e-9);
  });

  it('sem dívida bruta não há custo de dívida a medir', () => {
    const withoutDebt = new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(2025, 12, 31),
      interestExpense: 50,
      cash: 900,
      netIncome: 100,
      ebit: 150,
    });
    expect(withoutDebt.totalDebt).toBe(0);
    expect(withoutDebt.costOfDebt).toBeNull();
    expect(withoutDebt.netDebt, 'é o caso que torna o recuo alcançável').toBeLessThan(0);
  });
});

describe('O vale do ciclo não descarta a empresa', () => {
  // A normalização funcionava no pico e desligava no vale: o fator é
  // `ciclo ÷ atual` e exige denominador positivo. Medido em 11/09/2026:
  // sete ativos elegíveis eram recusados por fluxo-base não positivo, entre
  // eles USIM3, USIM5, CSAN3 e CSNA3 — cíclicos num ano ruim.
  const year = (y: number, profit: number, o: { equity?: number; ebitda?: number | null } = {}): FundamentalsSnapshot => {
    const equity = o.equity ?? 10000;
    return new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(y, 12, 31),
      totalRevenue: 20000,
      ebit: profit / 0.66,
      ebitda: o.ebitda ?? profit / 0.66 + 800,
      netIncome: profit,
      incomeBeforeTax: profit * 1.4,
      incomeTaxExpense: -profit * 0.4,
      interestExpense: 120,
      earningsPerShare: profit / 1000,
      cash: 500,
      shortTermInvestments: 100,
      shortTermDebt: 300,
      longTermDebt: 1200,
      totalStockholderEquity: equity,
      bookValuePerShare: equity / 1000,
      operatingCashFlow: profit * 1.5,
      freeCashFlow: profit,
      nopat: profit,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 12000,
    });
  };

  /** Série com [negatives] exercícios de prejuízo no fim. */
  const series = (o: { negatives: number; goodProfit?: number; ebitdaFinal?: number | null }): FundamentalsSnapshot[] => {
    const goodProfit = o.goodProfit ?? 1200;
    const out: FundamentalsSnapshot[] = [];
    for (let i = 15; i >= 0; i--) {
      const y = 2025 - i;
      const bad = i < o.negatives;
      out.push(year(y, bad ? -400 : goodProfit, { ebitda: i === 0 ? (o.ebitdaFinal ?? null) : null }));
    }
    return out;
  };

  const evaluate = (
    f: FundamentalsSnapshot[],
    o: { sector?: string | null; subsector?: string | null } = {},
  ): ValuationResult | null => {
    const r = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: f,
        marketPrice: 12.0,
        capm: new CapmInputs({ riskFreeRate: 0.13, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
        sectorKey: o.sector ?? null,
        industry: o.subsector ?? null,
      }),
    );
    return r.isOk ? r.unwrap() : null;
  };

  it('um ano de prejuízo deixa de descartar a empresa', () => {
    // Cíclico de propósito: em não cíclico, prejuízo depois de lucro sempre
    // reprova na trava de saúde — ver o teste dela abaixo.
    const v = evaluate(series({ negatives: 1 }), { sector: 'materiais-basicos' });
    expect(v, 'com o fluxo-base do exercício, este fixture seria recusado por lucro não positivo').not.toBeNull();
    expect(v!.fairValue.reais).toBeGreaterThan(0);
    expect(v!.diagnostics!.caveats).toContain(ValuationCaveat.rebuiltBase);
    expect(v!.warnings.some((w) => w.includes('reconstruído do ciclo'))).toBe(true);
  });

  it('o fluxo-base é o retorno do ciclo sobre o capital de hoje', () => {
    const f = series({ negatives: 1 });
    const v = evaluate(f, { sector: 'materiais-basicos' })!;
    const pub = new PointInTimeView(day(2026, 9, 9)).published(f);
    // A mesma alíquota que a cascata aplica: sem ela o NOPAT da série é
    // outro, e o ciclo também.
    const s = CapitalSeries.build(pub, ValuationLane.firm, {
      firmTaxRate: CapitalSeries.structuralTaxRate(pub, { statutoryRate: ValuationParameters.statutoryTaxRate }),
    });
    const cycle = s.cycleReturn({ window: ValuationParameters.cycleWindow })!;
    // O retorno que governa o freio é o do ciclo, e não o do exercício de
    // prejuízo: sem isso o fluxo viria do ciclo e o reinvestimento do vale.
    expectClose(v.diagnostics!.returnOnCapital, cycle, 1e-12);
    expect(cycle).toBeGreaterThan(0);
  });

  it('ciclo não positivo continua recusando', () => {
    // Empresa que perde dinheiro na maior parte da janela: não há a que
    // voltar, e a mediana não é resgate.
    expect(evaluate(series({ negatives: 7 }), { sector: 'materiais-basicos' })).toBeNull();
  });

  it('prejuízo que virou regra continua recusando', () => {
    // Metade da janela negativa passa no teste do sinal da mediana e falha
    // no da frequência — é o caso que separa vale de declínio.
    const f = series({ negatives: 5 });
    const pub = new PointInTimeView(day(2026, 9, 9)).published(f);
    const s = CapitalSeries.build(pub, ValuationLane.firm);
    const fraction = s.positiveShare({ window: ValuationParameters.cycleWindow })!;
    expect(fraction, 'o fixture precisa cair abaixo do corte para medir o que promete').toBeLessThan(
      ValuationParameters.minPositiveFlow,
    );
    expect(evaluate(f, { sector: 'materiais-basicos' })).toBeNull();
  });

  it('a trava de saúde bloqueia, e cíclico é isento dela', () => {
    // Ela foi retirada e reposta por medição: sem ela a RAPT4 entra a
    // +311,7% de potencial, com o resultado caído 109% no triênio e o
    // fluxo-base reconstruído sobre um retorno de ciclo que a empresa
    // acabou de deixar de ter. Reconstruir a base erra para cima, e é esse
    // risco que a trava controla.
    const f = series({ negatives: 1 });
    const decline = GrowthGuards.recentOperationalDecline(new PointInTimeView(day(2026, 9, 9)).published(f));
    expect(decline).not.toBeNull();
    expect(decline!).toBeGreaterThan(ValuationParameters.maxOperationalDecline);

    expect(evaluate(f, { sector: 'bens-industriais' })).toBeNull();
    // A isenção cíclica da decisão 30 vale aqui pela mesma razão que vale na
    // normalização: em commodity, queda entre pico e vale é o ciclo.
    expect(evaluate(f, { sector: 'materiais-basicos' })).not.toBeNull();
  });

  it('a trava tem um buraco, e a frequência o cobre', () => {
    // Quando a referência de três anos atrás também era prejuízo, a trava
    // **aprova** — não há queda a medir. É a frequência do prejuízo na
    // janela que recusa nesse caso, e não a trava.
    const f = series({ negatives: 5 });
    const decline = GrowthGuards.recentOperationalDecline(new PointInTimeView(day(2026, 9, 9)).published(f));
    expect(decline).not.toBeNull();
    expect(decline!, 'a trava aprova este caso — é o buraco que a frequência cobre').toBeLessThan(
      ValuationParameters.maxOperationalDecline,
    );
    expect(evaluate(f, { sector: 'materiais-basicos' })).toBeNull();
  });
});

describe('Ausência não é zero: o exercício sem resultado', () => {
  // Medido em 10/09/2026: a fonte publica o exercício com o balanço
  // preenchido e o resultado inteiro zerado em 4 dos 376 ativos. A TIMS3
  // aparecia com receita, EBIT, lucro e LPA zerados e patrimônio de R$ 24
  // bilhões, tendo tido EBIT de R$ 4,7 bi dois exercícios antes — e era
  // recusada por "os dados não sustentam nenhuma das duas vias", que é a
  // mensagem errada para um dado que a fonte não entregou.
  const exercise = (
    year: number,
    o: { revenue?: number; ebit?: number; profit?: number; eps?: number; equity?: number } = {},
  ): FundamentalsSnapshot => {
    const equity = o.equity ?? 24000;
    const ebit = o.ebit ?? null;
    const profit = o.profit ?? null;
    return new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(year, 12, 31),
      totalRevenue: o.revenue ?? null,
      ebit,
      ebitda: ebit === null ? null : ebit * 1.3,
      netIncome: profit,
      incomeBeforeTax: profit === null ? null : profit * 1.4,
      incomeTaxExpense: profit === null ? null : -profit * 0.4,
      earningsPerShare: o.eps ?? null,
      cash: 500,
      shortTermDebt: 400,
      longTermDebt: 1600,
      totalStockholderEquity: equity,
      bookValuePerShare: equity / 1000,
      nopat: ebit === null ? null : ebit * 0.66,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 30000,
    });
  };

  it('os quatro zerados juntos é ausência; um só não é', () => {
    // Zerar um deles é possível — holding sem receita, empresa no zero a
    // zero, exercício sem LPA publicado.
    expect(exercise(2025).hasIncomeStatement).toBe(false);
    expect(exercise(2025, { revenue: 0, ebit: 0, profit: 0, eps: 0 }).hasIncomeStatement).toBe(false);
    expect(exercise(2025, { revenue: 8000 }).hasIncomeStatement).toBe(true);
    expect(exercise(2025, { ebit: 1000 }).hasIncomeStatement).toBe(true);
    expect(exercise(2025, { profit: 700 }).hasIncomeStatement).toBe(true);
    expect(exercise(2025, { eps: 0.7 }).hasIncomeStatement).toBe(true);
    // Prejuízo é resultado publicado, e não pode ser confundido com ausência.
    expect(exercise(2025, { ebit: -1000 }).hasIncomeStatement).toBe(true);

    // **Resíduo de ponto flutuante não é resultado.** A fonte devolve o zero
    // às vezes sujo, e `== 0` leria `1e-16` como lucro publicado.
    expect(exercise(2025, { revenue: 1e-16, ebit: -1e-14, profit: 0, eps: 0 }).hasIncomeStatement).toBe(false);
    // E o corte por papel é o centavo, não o real: LPA de R$ 0,50 é
    // legítimo, e o corte dos agregados o descartaria.
    expect(exercise(2025, { eps: 0.5 }).hasIncomeStatement).toBe(true);
    expect(exercise(2025, { eps: 0.001 }).hasIncomeStatement).toBe(false);
  });

  const series = (o: { emptyCount: number }): FundamentalsSnapshot[] => {
    const out: FundamentalsSnapshot[] = [];
    let scale = 1.0;
    for (let i = 15; i >= 0; i--) {
      const year = 2025 - i;
      const isEmptyValue = i < o.emptyCount;
      out.push(
        isEmptyValue
          ? exercise(year)
          : exercise(year, {
              revenue: 10000 * scale,
              ebit: 1400 * scale,
              profit: 700 * scale,
              eps: 0.7 * scale,
              equity: 6000 * scale,
            }),
      );
      scale *= 1.05;
    }
    return out;
  };

  const evaluate = (emptyCount: number): ValuationResult | null => {
    const r = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series({ emptyCount }),
        marketPrice: 10.0,
        capm: new CapmInputs({ riskFreeRate: 0.13, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
      }),
    );
    return r.isOk ? r.unwrap() : null;
  };

  it('o exercício vazio sai da série, e a base vem do anterior', () => {
    const clean = evaluate(0);
    const withEmpty = evaluate(1);
    expect(clean).not.toBeNull();
    expect(
      withEmpty,
      'lido como zero, o último exercício produziria base nula e a avaliação seria recusada',
    ).not.toBeNull();
    // A base passa a ser o exercício anterior, que é menor pela escala — o
    // preço justo cai, e não vai a zero nem some.
    expect(withEmpty!.fairValue.reais).toBeGreaterThan(0);
    expect(withEmpty!.fairValue.reais).toBeLessThan(clean!.fairValue.reais);
  });

  it('a exclusão é declarada, com a contagem', () => {
    const v = evaluate(2)!;
    expect(v.warnings.some((w) => w.includes('sem demonstração de resultado'))).toBe(true);
    expect(v.warnings.some((w) => w.startsWith('2 exercícios'))).toBe(true);
  });

  it('série inteira vazia vira recusa que nomeia a causa', () => {
    const r = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series({ emptyCount: 16 }),
        marketPrice: 10.0,
        capm: new CapmInputs({ riskFreeRate: 0.13, beta: 1.0, marketPremium: 0.055 }),
      }),
    );
    expect(r.isErr).toBe(true);
    const m = r.failureOrNull!.message;
    expect(m).toContain('sem demonstração de resultado');
    expect(m, 'a causa é o dado que a fonte não entregou, e não o modelo não se aplicar').not.toContain(
      'nenhuma das duas vias',
    );
  });
});

describe('O peso do terminal mede a mesma coisa nas três rotas', () => {
  // Antes da decisão 51 a ponte media contra o valor da **firma** e as
  // outras duas contra o do **acionista**: o mesmo campo carregava duas
  // grandezas conforme um caminho que o leitor não vê, e o corte de 80% da
  // ressalva valia para as duas.
  const assumptions = new DcfAssumptions({
    projectionYears: 5,
    growthRate: 0.04,
    perpetualGrowth: 0.04,
    discountRate: 0.12,
    terminalDiscountRate: 0.12,
    returnOnCapital: 0.0,
  });

  it('a ponte mede contra o capital próprio, não contra a firma', () => {
    const o = DcfCalculator.firm({ baseProfit: 100, assumptions, netDebt: 300, sharesOutstanding: 10 }).unwrap();

    expectClose(o.terminalShare, o.discountedTerminalValue / o.equityValue, 1e-12);
    expect(
      o.terminalShare,
      'com dívida, a referência do acionista é maior — e é a que diz quanto do preço repousa na perpetuidade',
    ).toBeGreaterThan(o.discountedTerminalValue / o.enterpriseValue);
  });

  it('sem dívida as duas referências coincidem', () => {
    const o = DcfCalculator.firm({ baseProfit: 100, assumptions, netDebt: 0, sharesOutstanding: 10 }).unwrap();
    expectClose(o.terminalShare, o.discountedTerminalValue / o.enterpriseValue, 1e-12);
  });

  it('capital próprio fino leva a razão acima de 100%, e não trunca', () => {
    // Truncar em 1 esconderia exatamente o caso mais frágil.
    const o = DcfCalculator.firm({ baseProfit: 100, assumptions, netDebt: 900, sharesOutstanding: 10 }).unwrap();
    expect(o.equityValue, 'o fixture precisa sobreviver à ponte para medir o que promete').toBeGreaterThan(0);
    expect(o.terminalShare).toBeGreaterThan(1.0);
  });

  it('a rota derivada desconta o minoritário da referência também', () => {
    const derivedOutcome = (m: number): DcfOutcome =>
      DcfCalculator.equityFromFirm({
        baseProfit: 100,
        assumptions,
        netDebt: 300,
        sharesOutstanding: 10,
        costOfDebt: 0.1,
        taxRate: 0.34,
        equityDiscountRate: 0.14,
        terminalEquityDiscountRate: 0.14,
        minorityInterest: m,
      }).unwrap();
    expect(
      derivedOutcome(200).terminalShare,
      'o que sobra ao controlador é menor, e o terminal pesa mais nele',
    ).toBeGreaterThan(derivedOutcome(0).terminalShare);
  });
});

describe('Concessão não preserva excedente na perpetuidade', () => {
  // Medido em 10/09/2026: 15 dos 120 avaliados operam sob contrato de prazo
  // determinado, e cinco recebiam excedente de retorno preservado para
  // sempre — a CPFE3 com λ = 0,261. Uma concessão é relicitada, e a tarifa
  // remunera o capital ao custo dele.
  it('a classificação pega concessão e não pega o resto', () => {
    const term = (sector: string | null, sub: string | null): boolean =>
      ConcessionSectors.hasFiniteTerm({ sectorKey: sector, industry: sub });

    expect(term('energia', 'Energia Elétrica')).toBe(true);
    expect(term('saneamento', null)).toBe(true);
    expect(term('infraestrutura', null)).toBe(true);
    expect(term('bens-industriais', 'Exploração de Rodovias')).toBe(true);
    expect(term('bens-industriais', 'Transporte Ferroviário')).toBe(true);
    // Acentuação e pontuação não decidem nada: a fonte publica variantes.
    expect(term('energia', 'ENERGIA ELETRICA')).toBe(true);

    expect(term('energia', 'Exploração. Refino e Distribuição')).toBe(false);
    expect(term('materiais-basicos', 'Siderurgia')).toBe(false);
    expect(term('consumo-ciclico', 'Tecidos, Vestuário e Calçados')).toBe(false);
    expect(term(null, null)).toBe(false);
  });

  it('o excedente perpétuo é recusado, com o motivo nomeado', () => {
    const verdict = (o: { term: boolean }) => {
      const excessReturns: YearExcess[] = [];
      for (let year = 2014; year <= 2025; year++) excessReturns.push({ year, excess: 0.16 * pow(0.9, year - 2014) });
      return GrowthGuards.residualMoat({
        cycleReturn: 0.28,
        terminalDiscountRate: 0.12,
        externalCapitalRatio: 0.1,
        periods: 12,
        excessReturns,
        projectionYears: 10,
        finiteTerm: o.term,
      });
    };

    const free = verdict({ term: false });
    expect(
      free.terminalReturn,
      'sem prazo este fixture precisa conceder o excedente — se não conceder, o teste não mede o que promete',
    ).not.toBeNull();

    const locked = verdict({ term: true });
    expect(locked.terminalReturn).toBeNull();
    expect(locked.blocks).toContain(MoatBlock.fixedTerm);
  });
});

describe('O rastro descreve a conta que foi feita', () => {
  // A lente `metodo` apontou, e é o tipo de divergência que a auditoria
  // existe justamente para impedir: a fórmula publicada omitia o
  // levantamento de meio de ano e descrevia um desconto 6% maior que o
  // aplicado.
  const scaledYear = (year: number, scale: number): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(year, 12, 31),
      totalRevenue: 10000 * scale,
      ebit: 1400 * scale,
      ebitda: 1900 * scale,
      netIncome: 700 * scale,
      incomeBeforeTax: 1000 * scale,
      incomeTaxExpense: -300 * scale,
      interestExpense: 120,
      earningsPerShare: 0.7 * scale,
      cash: 500,
      shortTermInvestments: 200,
      shortTermDebt: 400,
      longTermDebt: 1600,
      totalStockholderEquity: 6000 * scale,
      bookValuePerShare: 6.0 * scale,
      operatingCashFlow: 1500 * scale,
      freeCashFlow: 900 * scale,
      nopat: 924 * scale,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 10000,
    });

  const formulas = (timing: CashTiming): string[] => {
    const captured: string[] = [];
    AuditRecorder.attach((event) => {
      for (const c of event.calculations) captured.push(c.latexRepresentation);
    });
    try {
      const fundamentals: FundamentalsSnapshot[] = [];
      for (let i = 15; i >= 0; i--) fundamentals.push(scaledYear(2025 - i, pow(1.05, 15 - i)));
      ValuationCascade.evaluate(
        new ValuationInputs({
          ticker,
          asOf: day(2026, 9, 9),
          fundamentals,
          marketPrice: 10.0,
          capm: new CapmInputs({ riskFreeRate: 0.13, beta: 1.0, marketPremium: 0.055 }),
          declaredTerminalRiskFreeRate: 0.094,
          cashTimingOverride: timing,
        }),
      );
    } finally {
      AuditRecorder.detach();
    }
    return captured;
  };

  it('a fórmula do explícito declara o levantamento, e só quando há', () => {
    const mid = formulas(CashTiming.midYear).join(' ');
    const end = formulas(CashTiming.endOfYear).join(' ');
    expect(mid.length, 'o rastro precisa ter sido capturado').toBeGreaterThan(0);
    // O fluxo desta via é o do acionista derivado, descontado ao `Ke` de
    // cada ano — `k_t` na fórmula (item B35).
    expect(mid).toContain(String.raw`\sqrt{1 + k_t}`);
    expect(end).not.toContain(String.raw`\sqrt{1 + k_t}`);
  });

  it('a fórmula do terminal declara o levantamento de equilíbrio', () => {
    const mid = formulas(CashTiming.midYear).join(' ');
    const end = formulas(CashTiming.endOfYear).join(' ');
    expect(mid).toContain(String.raw`\sqrt{1 + K_{e,\infty}}`);
    expect(end).not.toContain(String.raw`\sqrt{1 + K_{e,\infty}}`);
  });
});

describe('A ponte devolve o que não é do controlador', () => {
  // Medido em 10/09/2026 na fonte: a conta-mãe `loansAndFinancing` **já
  // contém** debêntures e arrendamento — somá-los estouraria o passivo não
  // circulante em PETR4, VALE3 e RENT3. O que de fato falta na ponte é a
  // participação dos não controladores, e ela é grande: 24,1% do valor de
  // mercado na CSNA3.
  const assumptions = new DcfAssumptions({
    projectionYears: 5,
    growthRate: 0.04,
    perpetualGrowth: 0.04,
    discountRate: 0.12,
    terminalDiscountRate: 0.12,
    returnOnCapital: 0.0,
  });

  const withMinority = (m: number): DcfOutcome =>
    DcfCalculator.firm({ baseProfit: 100, assumptions, netDebt: 300, sharesOutstanding: 10, minorityInterest: m }).unwrap();

  it('o preço por papel cai exatamente a parte dos minoritários', () => {
    const without = withMinority(0);
    const withInput = withMinority(200);
    expectClose(without.fairValuePerShare - withInput.fairValuePerShare, 200 / 10, 1e-9);
    expectClose(withInput.equityValue, without.equityValue - 200, 1e-9);
  });

  it('a alavancagem NÃO muda: minoritário é capital próprio', () => {
    // Tirá-los de `equityShare` os trataria como dívida, e a pós-condição da
    // ponte e o ponto fixo leriam uma estrutura de capital que não existe.
    const without = withMinority(0);
    const withInput = withMinority(200);
    expectClose(withInput.equityShare, without.equityShare, 1e-12);
    expectClose(withInput.enterpriseValue, without.enterpriseValue, 1e-12);
  });

  it('participação negativa é tratada como zero', () => {
    // Controlada com patrimônio negativo produz minoritário negativo, e
    // subtraí-lo **aumentaria** o valor do controlador.
    expectClose(withMinority(-500).fairValuePerShare, withMinority(0).fairValuePerShare, 1e-12);
  });

  it('a rota derivada desconta a mesma parte', () => {
    const derivedOutcome = (m: number): DcfOutcome =>
      DcfCalculator.equityFromFirm({
        baseProfit: 100,
        assumptions,
        netDebt: 300,
        sharesOutstanding: 10,
        costOfDebt: 0.1,
        taxRate: 0.34,
        equityDiscountRate: 0.14,
        terminalEquityDiscountRate: 0.14,
        minorityInterest: m,
      }).unwrap();
    expectClose(derivedOutcome(0).fairValuePerShare - derivedOutcome(200).fairValuePerShare, 200 / 10, 1e-9);
  });
});

describe('Equivalência patrimonial não é tributada duas vezes', () => {
  // Na DRE brasileira a equivalência entra acima do EBIT, e chega líquida do
  // imposto pago pela investida. Medido no ITSA4 em 10/09/2026: EBIT de
  // R$ 18,1 bi contra equivalência de R$ 17,5 bi — 97% do resultado
  // operacional era lucro já tributado, e recebia 34% de novo.
  const withEquityMethod = (equiv: number | null): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(2025, 12, 31),
      ebit: 1000,
      ebitda: 1200,
      netIncome: 800,
      incomeBeforeTax: 900,
      incomeTaxExpense: -100,
      equityIncomeResult: equiv,
      sharesOutstanding: 100,
      sharesOutstandingAsOf: 100,
    });

  it('sem equivalência, nada muda', () => {
    expectClose(withEquityMethod(null).nopatAtRate(0.25)!, 750, 1e-9);
    expectClose(withEquityMethod(0).nopatAtRate(0.25)!, 750, 1e-9);
  });

  it('a parte da equivalência passa sem imposto', () => {
    // `NOPAT = (1000 − 400)·0,75 + 400 = 850`, contra os 750 de antes.
    expectClose(withEquityMethod(400).nopatAtRate(0.25)!, 850, 1e-9);
  });

  it('equivalência negativa não devolve imposto', () => {
    // Prejuízo da investida reduz o EBIT sem ter gerado crédito na
    // controladora; devolver imposto ali inventaria caixa.
    expectClose(withEquityMethod(-400).nopatAtRate(0.25)!, 750, 1e-9);
  });

  it('não passa do próprio EBIT', () => {
    // Operação no prejuízo com equivalência maior que o EBIT: o NOPAT não
    // pode superar o resultado que o gerou.
    const s = withEquityMethod(1500);
    expectClose(s.taxableEquityIncome, 1000, 1e-9);
    expectClose(s.nopatAtRate(0.25)!, 1000, 1e-9);
  });
});

describe('Estrutura de capital recusada pela realavancagem', () => {
  // Medido em 10/09/2026: seis dos noventa e seis ativos com as duas vias
  // avaliáveis caem aqui, e são **exatamente** os seis que ainda eram
  // mesclados e migrados. O solucionador recusa — capital próprio não
  // positivo no ano zero, ou taxa de equilíbrio abaixo do crescimento
  // perpétuo — e o motor recuava para a interpolação, que não enxerga o
  // problema porque desconta pela taxa que a realavancagem rejeitou.
  const drownedYear = (year: number, scale: number, debt: number): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(year, 12, 31),
      totalRevenue: 10000 * scale,
      ebit: 1400 * scale,
      ebitda: 1900 * scale,
      netIncome: 500 * scale,
      incomeBeforeTax: 800 * scale,
      incomeTaxExpense: -300 * scale,
      interestExpense: 600,
      earningsPerShare: 0.5 * scale,
      cash: 500,
      shortTermInvestments: 200,
      shortTermDebt: debt * 0.2,
      longTermDebt: debt * 0.8,
      totalStockholderEquity: 4000 * scale,
      bookValuePerShare: 4.0 * scale,
      operatingCashFlow: 1500 * scale,
      freeCashFlow: 900 * scale,
      nopat: 924 * scale,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 9000,
      enterpriseToEbitda: 8.0,
    });

  const series = (debt: number): FundamentalsSnapshot[] => {
    const out: FundamentalsSnapshot[] = [];
    let scale = 1.0;
    for (let i = 15; i >= 0; i--) {
      out.push(drownedYear(2025 - i, scale, debt));
      scale *= 1.06;
    }
    return out;
  };

  const evaluate = (o: { debt: number; betaU?: number | null }): Result<ValuationResult> =>
    ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series(o.debt),
        marketPrice: 9.0,
        capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
        unleveredBeta: o.betaU ?? null,
      }),
    );

  it('a recusa da realavancagem não vira preço de outra via', () => {
    // Decisão 102. A estrutura recusada migrava para a via do acionista
    // (decisão 45), e sem beta desalavancado a ponte fina era mesclada com
    // ela (decisão 38). Nenhuma das duas acontece mais: com ou sem caminho
    // resolvido, o ativo é avaliado pela via da firma ou recusado.
    let refusedByStructure = 0;
    let evaluated = 0;
    for (let step = 0; step <= 30; step++) {
      const debt = 16000 + step * 2000.0;
      for (const betaU of [null, 0.6]) {
        const r = evaluate({ debt, betaU });
        if (r.isErr) {
          const reason = r.failureOrNull!.message;
          if (reason.includes('não sustenta a via da firma')) {
            refusedByStructure++;
            expect(reason).toContain('não muda de via');
          }
          continue;
        }
        evaluated++;
        const v = r.unwrap();
        expect(v.model, `dívida ${debt}`).toBe(ValuationModel.dcfFcff);
        expect(v.diagnostics!.caveats).not.toContain(ValuationCaveat.mergedLanes);
        expect(v.diagnostics!.caveats).not.toContain(ValuationCaveat.migratedLane);
      }
    }
    expect(evaluated).toBeGreaterThan(0);
    expect(
      refusedByStructure,
      'a varredura precisa alcançar a recusa da realavancagem — se não alcançar, o teste não mede o que promete',
    ).toBeGreaterThan(0);
  });

  it('sem via da firma, o ativo é recusado, e a recusa diz por quê', () => {
    // Dívida escolhida para a recusa disparar: com ela o capital próprio
    // some quando o custo dele é reprecificado pela alavancagem que tem.
    const r = evaluate({ debt: 60000, betaU: 0.6 });
    expect(r.isErr, 'a via do acionista é outro modelo, e não carrega o ativo que a da firma recusou').toBe(true);
    expect(r.failureOrNull!.message).toContain('não sustenta a via da firma');
    expect(r.failureOrNull!.message).toContain('não muda de via');
  });
});

describe('A via do acionista resolve o próprio custo de capital', () => {
  // Decisão 46. A via do acionista avalia sozinha 33 dos 120 em produção, e
  // em nenhum deles a via da firma produz caminho de taxas para emprestar:
  // ou o `Ke` sai dos fluxos dela mesma, ou ela segue supondo a alavancagem
  // de hoje perene — a hipótese que a decisão 41 mediu e descartou.
  const scaledYear = (year: number, scale: number): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(year, 12, 31),
      totalRevenue: 10000 * scale,
      ebit: 1400 * scale,
      ebitda: 1900 * scale,
      netIncome: 500 * scale,
      incomeBeforeTax: 800 * scale,
      incomeTaxExpense: -300 * scale,
      interestExpense: 600,
      earningsPerShare: 0.5 * scale,
      cash: 500,
      shortTermInvestments: 200,
      shortTermDebt: 2000,
      longTermDebt: 8000,
      totalStockholderEquity: 4000 * scale,
      bookValuePerShare: 4.0 * scale,
      operatingCashFlow: 1500 * scale,
      freeCashFlow: 900 * scale,
      nopat: 924 * scale,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 9000,
      enterpriseToEbitda: 8.0,
    });

  const series = (): FundamentalsSnapshot[] => {
    const out: FundamentalsSnapshot[] = [];
    let scale = 1.0;
    for (let i = 15; i >= 0; i--) {
      out.push(scaledYear(2025 - i, scale));
      scale *= 1.06;
    }
    return out;
  };

  const shareholder = (o: { betaU?: number | null; sector?: string | null } = {}): ValuationResult | null => {
    const r = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series(),
        marketPrice: 9.0,
        capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
        sectorKey: o.sector ?? null,
        unleveredBeta: o.betaU ?? null,
        laneOverride: ValuationLane.shareholder,
      }),
    );
    return r.isOk ? r.unwrap() : null;
  };

  it('com beta desalavancado, o Ke é resolvido e declarado', () => {
    const without = shareholder()!;
    const withInput = shareholder({ betaU: 0.6 })!;

    expect(
      without.warnings.some((w) => w.includes('resolvido ano a ano')),
      'sem β_U não há realavancagem, e o comportamento é o antigo',
    ).toBe(false);
    const note = withInput.warnings.filter((w) => w.includes('resolvido ano a ano'));
    expect(note).toHaveLength(1);
    expect(note[0]).toContain('o Ke vai de');
    expect(note[0], 'esta via não tem custo médio a declarar').not.toContain('WACC');
    expectNotClose(
      withInput.fairValue.reais,
      without.fairValue.reais,
      1e-9,
      'resolver a taxa tem de mover o preço, ou não resolveu nada',
    );
  });

  it('instituição financeira fica de fora, e o preço não muda', () => {
    // Depósito e captação são insumo do negócio, não financiamento:
    // realavancar por `D/E` trataria a matéria-prima como estrutura de
    // capital, que é o que a Porta 1 existe para não fazer.
    const without = shareholder({ sector: 'servicos-financeiros' })!;
    const withInput = shareholder({ sector: 'servicos-financeiros', betaU: 0.6 })!;

    expect(withInput.warnings.some((w) => w.includes('resolvido ano a ano'))).toBe(false);
    expect(withInput.fairValue.cents, 'para banco, oferecer β_U não pode mudar coisa alguma').toBe(
      without.fairValue.cents,
    );
  });

  it('o Ke resolvido acompanha a alavancagem, e não a taxa do dia', () => {
    // O mesmo ativo com mais dívida tem de sair com preço justo menor: o
    // capital próprio de uma empresa mais alavancada é mais caro.
    const withDebt = (debt: number): ValuationResult | null => {
      const adjusted = series().map(
        (f) =>
          new FundamentalsSnapshot({
            ticker: f.ticker,
            fiscalPeriodEnd: f.fiscalPeriodEnd,
            totalRevenue: f.totalRevenue,
            ebit: f.ebit,
            ebitda: f.ebitda,
            netIncome: f.netIncome,
            incomeBeforeTax: f.incomeBeforeTax,
            incomeTaxExpense: f.incomeTaxExpense,
            interestExpense: f.interestExpense,
            earningsPerShare: f.earningsPerShare,
            cash: f.cash,
            shortTermInvestments: f.shortTermInvestments,
            shortTermDebt: debt * 0.2,
            longTermDebt: debt * 0.8,
            totalStockholderEquity: f.totalStockholderEquity,
            bookValuePerShare: f.bookValuePerShare,
            operatingCashFlow: f.operatingCashFlow,
            freeCashFlow: f.freeCashFlow,
            nopat: f.nopat,
            sharesOutstanding: f.sharesOutstanding,
            sharesOutstandingAsOf: f.sharesOutstandingAsOf,
            marketCap: f.marketCap,
            enterpriseToEbitda: f.enterpriseToEbitda,
          }),
      );
      const r = ValuationCascade.evaluate(
        new ValuationInputs({
          ticker,
          asOf: day(2026, 9, 9),
          fundamentals: adjusted,
          marketPrice: 9.0,
          capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
          declaredTerminalRiskFreeRate: 0.094,
          unleveredBeta: 0.6,
          laneOverride: ValuationLane.shareholder,
        }),
      );
      return r.isOk ? r.unwrap() : null;
    };

    const light = withDebt(4000);
    const heavy = withDebt(20000);
    expect(light).not.toBeNull();
    expect(heavy).not.toBeNull();
    expect(
      heavy!.fairValue.reais,
      'mais alavancagem, capital próprio mais caro, preço menor — e o lucro por papel é o mesmo nos dois',
    ).toBeLessThan(light!.fairValue.reais);
  });
});

describe('A janela curta do beta é declarada', () => {
  // Item B17, decisão 111. A fonte de cotações devolve dez anos: numa
  // avaliação datada de 2018 a série começa em 2016, e o beta sai de pouco
  // mais de um ano de pregões — 383 contra 1.240 — sem que nada diga.
  const year = (y: number, scale: number): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(y, 12, 31),
      totalRevenue: 10000 * scale,
      ebit: 1600 * scale,
      ebitda: 2100 * scale,
      netIncome: 800 * scale,
      incomeBeforeTax: 1200 * scale,
      incomeTaxExpense: -400 * scale,
      interestExpense: 300,
      earningsPerShare: 0.8 * scale,
      cash: 400,
      shortTermDebt: 800,
      longTermDebt: 2200,
      totalStockholderEquity: 5000 * scale,
      bookValuePerShare: 5.0 * scale,
      operatingCashFlow: 1800 * scale,
      nopat: 1056 * scale,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 10000,
    });

  const series = (): FundamentalsSnapshot[] => {
    const out: FundamentalsSnapshot[] = [];
    let scale = 1.0;
    for (let i = 12; i >= 0; i--) {
      out.push(year(2025 - i, scale));
      scale *= 1.05;
    }
    return out;
  };

  const evaluate = (window: number | null): ValuationResult =>
    ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series(),
        marketPrice: 10.0,
        capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
        betaWindowYears: window,
      }),
    ).unwrap();

  const declares = (r: ValuationResult): boolean => r.warnings.some((w) => w.includes('O beta foi estimado sobre'));

  it('janela inteira não gera ressalva', () => {
    expect(declares(evaluate(5.0))).toBe(false);
    expect(declares(evaluate(4.6)), 'feriado e pregão faltando tiram dias, não anos').toBe(false);
  });

  it('janela curta gera ressalva, com o número', () => {
    const r = evaluate(1.6);
    expect(declares(r)).toBe(true);
    const warning = r.warnings.find((w) => w.includes('O beta foi estimado sobre'))!;
    expect(warning).toContain('1.6 ano(s)');
    expect(warning).toContain(`${str(ValuationCascade.betaWindowYears)} que a janela pede`);
  });

  it('sem medição da janela, nada é afirmado', () => {
    // Quem monta os insumos à mão não informa a janela, e o silêncio é o
    // certo: afirmar janela cheia seria inventar.
    expect(declares(evaluate(null))).toBe(false);
    expect(declares(evaluate(0.0))).toBe(false);
  });

  it('a constante da janela é uma só nos dois lados', () => {
    expect(PrepareValuationInputs.betaWindowYears).toBe(ValuationCascade.betaWindowYears);
  });
});

describe('A perpetuidade declara de onde vêm o beta e a estrutura', () => {
  // Item B15, decisão 109. Em produção o beta de equilíbrio é o de hoje,
  // encolhido, e a estrutura é a do ano N do modelo. As duas alternativas do
  // item — convergir o beta em direção a 1 e impor uma alavancagem — entram
  // por imposição de diagnóstico, e é o que estes casos exercitam.
  const year = (y: number, scale: number): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(y, 12, 31),
      totalRevenue: 20000 * scale,
      ebit: 3000 * scale,
      ebitda: 4000 * scale,
      netIncome: 1500 * scale,
      incomeBeforeTax: 2200 * scale,
      incomeTaxExpense: -700 * scale,
      interestExpense: 500,
      earningsPerShare: 1.5 * scale,
      cash: 600,
      shortTermDebt: 1500,
      longTermDebt: 4500,
      totalStockholderEquity: 9000 * scale,
      bookValuePerShare: 9.0 * scale,
      operatingCashFlow: 3400 * scale,
      nopat: 1980 * scale,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 18000,
    });

  const series = (): FundamentalsSnapshot[] => {
    const out: FundamentalsSnapshot[] = [];
    let scale = 1.0;
    for (let i = 12; i >= 0; i--) {
      out.push(year(2025 - i, scale));
      scale *= 1.05;
    }
    return out;
  };

  const evaluate = (o: { beta?: number; betaWeight?: number | null; leverage?: number | null } = {}): ValuationResult =>
    ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series(),
        marketPrice: 18.0,
        capm: new CapmInputs({ riskFreeRate: 0.14, beta: o.beta ?? 1.6, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
        unleveredBeta: 0.6,
        terminalBetaWeightOverride: o.betaWeight ?? null,
        terminalLeverageOverride: o.leverage ?? null,
      }),
    ).unwrap();

  it('sem imposição, nada muda — é o caminho de produção', () => {
    const a = evaluate();
    const b = evaluate({ betaWeight: null, leverage: null });
    expect(b.fairValue.cents).toBe(a.fairValue.cents);
  });

  it('a estrutura de equilíbrio sai nos diagnósticos, e é a do ano N', () => {
    const d = evaluate().diagnostics!;
    expect(d.terminalEquityShare, 'com taxas resolvidas, a perpetuidade tem estrutura própria').not.toBeNull();
    expectNotClose(
      d.terminalEquityShare!,
      d.equityShare,
      1e-9,
      'a do ano N não é a de hoje — se fosse, a decisão 105 não teria mudado nada',
    );
  });

  it('convergir o beta aproxima a taxa de equilíbrio da de beta 1', () => {
    // **O beta que a perpetuidade usa é o realavancado do ano N** —
    // `β_U · fator(D_N/E_N)` —, e não o `beta` do CAPM: com o caminho de
    // taxas resolvido, quem entra é o desalavancado. Blume o puxa para 1, e o
    // sentido do movimento depende de que lado desse 1 ele estava. O que vale
    // nos dois lados é a aproximação.
    const betaOneRate = 0.094 + 1.0 * 0.055;
    for (const betaU of [0.35, 1.3]) {
      const run = (betaWeight: number | null): ValuationResult =>
        ValuationCascade.evaluate(
          new ValuationInputs({
            ticker,
            asOf: day(2026, 9, 9),
            fundamentals: series(),
            marketPrice: 18.0,
            capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
            declaredTerminalRiskFreeRate: 0.094,
            unleveredBeta: betaU,
            terminalBetaWeightOverride: betaWeight,
          }),
        ).unwrap();
      const without = run(null);
      const withInput = run(0.67);
      expect(Math.abs(withInput.diagnostics!.terminalCostOfEquity! - betaOneRate), `β_U = ${betaU}`).toBeLessThan(
        Math.abs(without.diagnostics!.terminalCostOfEquity! - betaOneRate),
      );
      // A **corrente** não se move: a imposição é só da perpetuidade.
      expectClose(withInput.diagnostics!.costOfEquity, without.diagnostics!.costOfEquity, 1e-12);
    }
  });

  it('alavancagem imposta impossível é recusada, e não vira NaN', () => {
    // Auditoria do gate, 21/09/2026. `D/E = −1` é caixa líquido igual ao
    // capital próprio: o valor da firma zera e o peso `1/(1 + D/E)` divide
    // por zero. A varredura que pede o impossível precisa ouvir isso.
    for (const debtToEquity of [-1.0, -2.0, Number.NaN, Number.POSITIVE_INFINITY]) {
      const r = ValuationCascade.evaluate(
        new ValuationInputs({
          ticker,
          asOf: day(2026, 9, 9),
          fundamentals: series(),
          marketPrice: 18.0,
          capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.6, marketPremium: 0.055 }),
          declaredTerminalRiskFreeRate: 0.094,
          unleveredBeta: 0.6,
          terminalLeverageOverride: debtToEquity,
        }),
      );
      // A recusa do solucionador é recuo declarado, não queda: a cascata
      // segue pela interpolação. O que não pode é sair número não finito.
      if (r.isOk) {
        const v = r.unwrap();
        expect(Number.isFinite(v.fairValue.reais), `${debtToEquity}`).toBe(true);
        expect(Number.isFinite(v.diagnostics!.terminalDiscountRate), `${debtToEquity}`).toBe(true);
      }
    }
  });

  it('a alavancagem imposta encarece o capital próprio de equilíbrio', () => {
    const without = evaluate();
    const withInput = evaluate({ leverage: 3.0 });
    expect(
      withInput.diagnostics!.terminalCostOfEquity!,
      'mais dívida na perpetuidade, capital próprio mais caro',
    ).toBeGreaterThan(without.diagnostics!.terminalCostOfEquity!);
    // O custo do capital próprio **corrente** é o do CAPM sobre a taxa de
    // hoje: ele não passa pelo ponto fixo, e nenhuma imposição de equilíbrio
    // o alcança.
    expectClose(withInput.diagnostics!.costOfEquity, without.diagnostics!.costOfEquity, 1e-12);
  });
});

describe('Com taxas resolvidas, a tela mostra as premissas finais', () => {
  // Item B11. O preço justo sai do caminho de taxas e do retorno terminal do
  // último passe; o rastro, os cenários, a taxa exibida e os diagnósticos
  // saíam das premissas **interpoladas**, que são o chute de que o ponto fixo
  // parte. No aplicativo de antes as duas coincidiam, porque ele não
  // resolvia o prior — ligar o prior sem isto descasaria a banda do preço.
  const year = (y: number, scale: number): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(y, 12, 31),
      totalRevenue: 20000 * scale,
      ebit: 3000 * scale,
      ebitda: 4000 * scale,
      netIncome: 1500 * scale,
      incomeBeforeTax: 2200 * scale,
      incomeTaxExpense: -700 * scale,
      interestExpense: 500,
      earningsPerShare: 1.5 * scale,
      cash: 600,
      shortTermDebt: 1500,
      longTermDebt: 4500,
      totalStockholderEquity: 9000 * scale,
      bookValuePerShare: 9.0 * scale,
      operatingCashFlow: 3400 * scale,
      nopat: 1980 * scale,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 18000,
    });

  const series = (): FundamentalsSnapshot[] => {
    const out: FundamentalsSnapshot[] = [];
    let scale = 1.0;
    for (let i = 12; i >= 0; i--) {
      out.push(year(2025 - i, scale));
      scale *= 1.05;
    }
    return out;
  };

  const evaluate = (o: { betaU?: number | null } = {}): ValuationResult =>
    ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series(),
        marketPrice: 18.0,
        capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
        unleveredBeta: o.betaU ?? null,
      }),
    ).unwrap();

  it('a taxa exibida é a do ano 1 resolvido, e não o chute', () => {
    const without = evaluate();
    const withInput = evaluate({ betaU: 0.6 });
    const note = withInput.warnings.find((w) => w.includes('resolvido ano a ano'))!;
    // O aviso diz a taxa do primeiro ano com uma casa; a exibida tem de ser
    // a mesma, e não a da interpolação.
    const first = `${toStringAsFixed(withInput.discountRate * 100, 1)}%`;
    expect(note).toContain(`o WACC vai de ${first} no primeiro ano`);
    expectNotClose(
      withInput.discountRate,
      without.discountRate,
      1e-9,
      'resolver a taxa tem de mover a taxa que a tela mostra',
    );
  });

  it('o cenário base volta ao preço justo', () => {
    const withInput = evaluate({ betaU: 0.6 });
    const base = withInput.discreteScenarios!.get(ScenarioBand.base)!;
    expect(
      base.cents,
      'a faixa de sensibilidade cerca o preço justo; centrada nas premissas interpoladas, ela cercava outro número',
    ).toBe(withInput.fairValue.cents);
  });

  it('a faixa responde ao desconto no caminho resolvido', () => {
    const withInput = evaluate({ betaU: 0.6 });
    const bear = withInput.discreteScenarios!.get(ScenarioBand.bear)!;
    const bull = withInput.discreteScenarios!.get(ScenarioBand.bull)!;
    expect(bear.reais).toBeLessThan(withInput.fairValue.reais);
    expect(bull.reais).toBeGreaterThan(withInput.fairValue.reais);
  });

  it('os diagnósticos saem do retorno terminal do último passe', () => {
    const withInput = evaluate({ betaU: 0.6 });
    const d = withInput.diagnostics!;
    // O desconto de equilíbrio é o resolvido, e o retorno terminal tem de
    // estar do mesmo lado da conta: neutro significa ausente, e não o número
    // que a interpolação teria dado.
    expectNotClose(d.terminalDiscountRate, 0.094, 1e-9);
    if (!d.moatApplied) {
      expect(d.terminalReturnOnCapital, 'terminal neutro não tem retorno próprio a declarar').toBeNull();
    }
  });
});

describe('A composição declarada da unit decide, e a medida confere', () => {
  // Item B16, decisão 106. A razão medida — `contagem × preço ÷ valor de
  // mercado` — só devolve o número de ações da unit quando as espécies valem
  // o mesmo; nas coortes ela erra 79 de 220 observações de unit.
  const year = (y: number, scale: number): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(y, 12, 31),
      totalRevenue: 10000 * scale,
      ebit: 1600 * scale,
      ebitda: 2100 * scale,
      netIncome: 800 * scale,
      incomeBeforeTax: 1200 * scale,
      incomeTaxExpense: -400 * scale,
      interestExpense: 300,
      earningsPerShare: 0.8 * scale,
      cash: 400,
      shortTermDebt: 800,
      longTermDebt: 2200,
      totalStockholderEquity: 5000 * scale,
      bookValuePerShare: 5.0 * scale,
      operatingCashFlow: 1800 * scale,
      nopat: 1056 * scale,
      sharesOutstanding: 3000,
      sharesOutstandingAsOf: 3000,
      // Valor de mercado de 30.000 com 3.000 ações: a razão **medida** com
      // preço de unit 30 dá 3. É a unit em que as espécies valem o mesmo.
      marketCap: 30000,
    });

  const series = (): FundamentalsSnapshot[] => {
    const out: FundamentalsSnapshot[] = [];
    let scale = 1.0;
    for (let i = 12; i >= 0; i--) {
      out.push(year(2025 - i, scale));
      scale *= 1.05;
    }
    return out;
  };

  // A contagem oficial da B3 arbitra o divisor (decisão 83), e é sobre ela
  // que a razão de unidade age: `divisor = contagem ÷ u`. É o caminho do
  // aplicativo, e por isso é o que o teste exercita.
  const evaluate = (o: { declared?: number | null; price?: number } = {}): ValuationResult | null => {
    const r = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series(),
        marketPrice: o.price ?? 30.0,
        capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
        declaredSharesPerUnit: o.declared ?? null,
        officialShares: new OfficialShareCount({ total: 3000, asOf: day(2026, 9, 1) }),
      }),
    );
    return r.isOk ? r.unwrap() : null;
  };

  it('sem declaração vale a medida, e a avaliação diz que inferiu', () => {
    const v = evaluate()!;
    const warning = v.warnings.find((w) => w.includes('negociada em unit'))!;
    expect(warning).toContain('3 ações');
    expect(warning).toContain('inferida do valor de mercado');
  });

  it('a declarada decide quando discorda da medida', () => {
    // O preço de 20 faz a razão medida cair em 2 — é o que acontece quando a
    // preferencial negocia abaixo da ordinária. A companhia declara 3.
    const withoutDeclared = evaluate({ price: 20.0 })!;
    expect(withoutDeclared.warnings.find((w) => w.includes('unit de'))).toContain('2 ações');

    const withDeclared = evaluate({ declared: 3, price: 20.0 })!;
    expect(withDeclared.warnings.find((w) => w.includes('unit de'))).toContain('3 ações');
    expect(
      withDeclared.warnings.some((w) => w.includes('razão de unidade medida')),
      'a divergência é a conferência, e tem de aparecer',
    ).toBe(true);
    // Perto de 3/2, e não exatamente: a razão também divide o divisor, e o
    // divisor forma o peso do capital próprio no WACC. Uma unit de três
    // ações tem um terço menos unidades, valor de mercado menor e desconto
    // um pouco diferente — o efeito de segunda ordem fica declarado aqui em
    // vez de virar uma tolerância sem explicação.
    expectClose(
      withDeclared.fairValue.reais / withoutDeclared.fairValue.reais,
      3 / 2,
      0.02,
      'três ações por unit valem uma vez e meia duas',
    );
  });

  it('declarada igual à medida não gera conferência', () => {
    const v = evaluate({ declared: 3 })!;
    expect(v.warnings.some((w) => w.includes('razão de unidade medida'))).toBe(false);
    expect(v.warnings.find((w) => w.includes('unit de'))).toContain('formulário cadastral');
  });

  it('declaração fora da faixa é ignorada, e vale a medida', () => {
    const absurd = evaluate({ declared: 99 })!;
    const withNothing = evaluate()!;
    expectClose(absurd.fairValue.reais, withNothing.fairValue.reais, 1e-9);
  });

  it('o rastro mostra as duas razões e diz qual valeu', () => {
    const trace: AuditEvent[] = [];
    AuditRecorder.attach((e) => trace.push(e));
    try {
      evaluate({ declared: 3, price: 20.0 });
    } finally {
      AuditRecorder.detach();
    }
    expect(trace).toHaveLength(1);
    const step = trace[0]!.calculations.find((p) => p.formulaName.includes('unidade negociada'))!;
    expect(step.mappedVariables['u_declarada']).toBe(3);
    expect(step.mappedVariables['u_medida'] as number).toBe(2.0);
    expect(step.intermediateSteps[step.intermediateSteps.length - 1]).toContain('é ela que vale');
    expect(step.finalValue).toBe(3.0);
  });
});

describe('A dívida do WACC é a mesma do resto do modelo', () => {
  // Item B9, decisão 104. O peso do WACC vinha da dívida **bruta**, enquanto
  // a apuração do capital próprio subtrai a **líquida** e a realavancagem da
  // decisão 41 pondera a líquida — o mesmo caixa barateava a taxa e depois
  // se somava ao acionista.
  type Options = { debt?: number; publishedExpense?: boolean };
  const year = (y: number, scale: number, o: Options & { cash: number }): FundamentalsSnapshot => {
    const debt = o.debt ?? 4000;
    const publishedExpense = o.publishedExpense ?? true;
    return new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: day(y, 12, 31),
      totalRevenue: 10000 * scale,
      ebit: 1800 * scale,
      ebitda: 2400 * scale,
      netIncome: 900 * scale,
      incomeBeforeTax: 1300 * scale,
      incomeTaxExpense: -400 * scale,
      interestExpense: debt > 0 && publishedExpense ? 400 : null,
      earningsPerShare: 0.9 * scale,
      cash: o.cash,
      shortTermDebt: debt * 0.25,
      longTermDebt: debt * 0.75,
      totalStockholderEquity: 6000 * scale,
      bookValuePerShare: 6.0 * scale,
      operatingCashFlow: 2000 * scale,
      nopat: 1188 * scale,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 12000,
    });
  };

  const series = (cash: number, o: Options = {}): FundamentalsSnapshot[] => {
    const out: FundamentalsSnapshot[] = [];
    let scale = 1.0;
    for (let i = 12; i >= 0; i--) {
      out.push(year(2025 - i, scale, { cash, ...o }));
      scale *= 1.05;
    }
    return out;
  };

  const evaluate = (cash: number, o: Options = {}): ValuationResult | null => {
    const r = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series(cash, o),
        marketPrice: 12.0,
        capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
      }),
    );
    return r.isOk ? r.unwrap() : null;
  };

  const waccStep = (run: () => void) => {
    const trace = captureEvents(run);
    expect(trace).toHaveLength(1);
    return trace[0]!.calculations.find((p) => p.formulaName.includes('WACC'))!;
  };

  it('mais caixa, mesma dívida bruta: o desconto sobe', () => {
    const few = evaluate(200)!;
    const many = evaluate(3000)!;
    expect(
      many.discountRate,
      'o caixa reduz a dívida líquida, o peso do capital próprio sobe e o WACC se aproxima do Ke — com a dívida bruta o peso não se movia',
    ).toBeGreaterThan(few.discountRate);
  });

  it('caixa maior que a dívida: o peso é negativo e o WACC passa do Ke', () => {
    const v = evaluate(6000)!;
    expect(
      v.discountRate,
      'com caixa líquido o ativo operacional sozinho é mais arriscado que a companhia inteira',
    ).toBeGreaterThan(v.diagnostics!.costOfEquity);
    expect(
      v.warnings.some((w) => w.includes('caixa líquido')),
      'a taxa acima do Ke precisa estar declarada na tela',
    ).toBe(true);
  });

  it('o rastro declara que a dívida do peso é a líquida', () => {
    const itsSeries = series(3000);
    const step = waccStep(() =>
      ValuationCascade.evaluate(
        new ValuationInputs({
          ticker,
          asOf: day(2026, 9, 9),
          fundamentals: itsSeries,
          marketPrice: 12.0,
          capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
          declaredTerminalRiskFreeRate: 0.094,
        }),
      ),
    );
    const last = itsSeries[itsSeries.length - 1]!;
    const net = last.netDebt;
    expect(Object.keys(step.mappedVariables)).toContain('D líquida (R$)');
    expectClose(step.mappedVariables['D líquida (R$)'] as number, net, 0.01);
    expect(net).toBeLessThan(last.totalDebt);
  });

  it('despesa financeira ausente não zera o prêmio de crédito (B26)', () => {
    // A NATU3 no gabarito de 22/09/2026: dívida contratada, despesa em
    // branco na fonte. O WACC estático degenerava para o `Ke`, o prêmio que
    // o ponto fixo recebia virava zero, e o caminho resolvido tomava
    // dinheiro à taxa livre de risco — com o aviso dizendo «desconto ao
    // Ke» ao lado do caminho de WACC que a conta de fato usou.
    const without = evaluate(200, { publishedExpense: false })!;
    expect(
      without.warnings.some((w) => w.includes('Estrutura de capital indisponível')),
      'há valor de mercado: o WACC é montável',
    ).toBe(false);
    expect(without.warnings.some((w) => w.includes('não está publicada'))).toBe(true);
    // Dívida líquida de 3.800 sobre EBITDA de ~4.310 no último ano: 0,88x,
    // a faixa de 1,0 p.p. — e não o teto de 10 que a cobertura nula daria.
    const step = waccStep(() => evaluate(200, { publishedExpense: false }));
    const kd = step.mappedVariables['K_d (% a.a.)'] as number;
    expectClose(kd, 14.0 + 100 * CostOfCapital.leverageSpread(0.88), 0.01);
    expect(step.intermediateSteps.some((p) => p.includes('não está publicada'))).toBe(true);
  });

  it('com a despesa publicada nada muda no prêmio (B26)', () => {
    // O prêmio do ponto fixo passou a sair do `_wacc` em vez de ser
    // recalculado do custo que ele devolvia: para quem tinha WACC, são o
    // mesmo número.
    const withInput = evaluate(200)!;
    expect(withInput.warnings.some((w) => w.includes('não está publicada'))).toBe(false);
  });

  it('caixa maior que a dívida é estrutura conhecida, e não ausente', () => {
    const capm = new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 });
    const withCash = evaluate(6000)!;
    expect(withCash.warnings.some((w) => w.includes('Estrutura de capital indisponível'))).toBe(false);
    expectNotClose(withCash.discountRate, capm.costOfEquity, 1e-9);
  });

  it('sem dívida contratada o caixa entra no desconto, e não degenera', () => {
    // Lente `metodo`, 20/09/2026. Companhia sem empréstimo e com caixa tem
    // estrutura conhecida — dívida líquida negativa —, e a apuração do
    // capital próprio devolve esse caixa. Degenerar para o `Ke` aqui
    // devolveria o caixa duas vezes.
    const capm = new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 });
    const withoutDebt = evaluate(3000, { debt: 0 })!;
    expect(withoutDebt.warnings.some((w) => w.includes('Estrutura de capital indisponível'))).toBe(false);
    expect(withoutDebt.discountRate, 'peso negativo do caixa põe o WACC acima do Ke').toBeGreaterThan(
      capm.costOfEquity,
    );
    expect(withoutDebt.warnings.some((w) => w.includes('não tem dívida contratada'))).toBe(true);
    // O que remunera o peso negativo é caixa, e caixa rende a taxa livre de
    // risco: sem dívida não há prêmio de crédito a cobrar (decisão 58).
    const weight =
      1 -
      (withoutDebt.discountRate - capm.costOfEquity) /
        (capm.riskFreeRate * (1 - ValuationParameters.statutoryTaxRate) - capm.costOfEquity);
    expect(weight).toBeGreaterThan(1.0);
  });
});

describe('A tradução do cenário para o Ke é escolha declarada', () => {
  // Item B20, decisão 121. O cenário perturba `discountRate`; na via do
  // acionista esse campo **é** o `Ke`, e na via da firma é o WACC. A rota
  // derivada desconta ao `Ke`, e traduzir exige escolher o que o cenário
  // perturba. As três leituras estão no enum, e o padrão é o um a um.
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
      cash: 500,
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

  const series = (): FundamentalsSnapshot[] => {
    const out: FundamentalsSnapshot[] = [];
    let scale = 1.0;
    for (let i = 12; i >= 0; i--) {
      out.push(year(2025 - i, scale));
      scale *= 1.05;
    }
    return out;
  };

  const evaluate = (reading: ScenarioTranslation): ValuationResult => {
    const r = ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series(),
        marketPrice: 12.0,
        capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
        unleveredBeta: 0.8,
        scenarioTranslation: reading,
      }),
    );
    expect(r.isOk, r.failureOrNull?.message).toBe(true);
    return r.unwrap();
  };

  const width = (v: ValuationResult): number => {
    const c = v.discreteScenarios!;
    return (c.get(ScenarioBand.bull)!.cents - c.get(ScenarioBand.bear)!.cents) / v.fairValue.cents;
  };

  it('o padrão declarado é o um a um', () => {
    // Se alguém trocar o padrão do enum, a faixa de produção muda de largura
    // sem que nada mais no repositório mude — e este é o único lugar que
    // reprova.
    const pattern = new ValuationInputs({
      ticker,
      asOf: day(2026, 9, 9),
      fundamentals: series(),
      marketPrice: 12.0,
      capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
    });
    expect(pattern.scenarioTranslation).toBe(ScenarioTranslation.oneToOne);
  });

  it('as três leituras dão o mesmo preço justo', () => {
    // O cenário base tem deslocamento zero, e multiplicar zero por qualquer
    // fator dá zero: a tradução não pode mover o centro. Se mover, a faixa
    // passa a cercar outro número.
    const a = evaluate(ScenarioTranslation.oneToOne);
    for (const reading of ScenarioTranslation.values) {
      expect(evaluate(reading).fairValue, reading.name).toEqual(a.fairValue);
    }
  });

  it('o cenário base volta ao preço justo nas três', () => {
    for (const reading of ScenarioTranslation.values) {
      const v = evaluate(reading);
      expect(v.discreteScenarios!.get(ScenarioBand.base), `${reading.name} — pós-condição da decisão 105`).toEqual(
        v.fairValue,
      );
    }
  });

  it('amplificar alarga a faixa, e na ordem esperada', () => {
    const oneToOne = width(evaluate(ScenarioTranslation.oneToOne));
    const riskFreeBand = width(evaluate(ScenarioTranslation.riskFreeRate));
    const structure = width(evaluate(ScenarioTranslation.fixedStructure));
    expect(riskFreeBand).toBeGreaterThan(oneToOne);
    expect(structure, '`1 ÷ w_E` passa de `1 ÷ (1 − w_D·t)` sempre que há dívida').toBeGreaterThan(riskFreeBand);
  });

  it('sem via da firma, a tradução não tem o que traduzir', () => {
    // **Por construção, e não por medição**: `_discountFlow` devolve o
    // fluxo do acionista antes de calcular o fator, porque lá o campo
    // perturbado **é** o `Ke`. É por isso que a medição do universo se
    // restringe aos 77 da via da firma — nos outros as três leituras são a
    // mesma conta, e medi-las seria medir nada.
    //
    // O que este teste cobra é o lado observável disso: o fator só existe
    // para a via da firma, e o enum não tem efeito fora dela.
    const v = evaluate(ScenarioTranslation.oneToOne);
    expect(v.model, 'o cenário do grupo precisa mesmo ser da via da firma').toBe(ValuationModel.dcfFcff);
  });
});

describe('O minoritário no peso do WACC estático é declarado', () => {
  // Item B23, decisão 120. O peso do WACC **estático** é o valor de mercado
  // da controladora, e o fluxo que ele desconta é o **consolidado**: com
  // minoritário material, a participação da dívida sai inflada. O caminho
  // **resolvido** não tem o problema — ele pondera pelo capital próprio que o
  // próprio modelo produz, `V − D` sobre fluxo consolidado.
  //
  // A interseção das três condições é **vazia** no universo de hoje. O aviso
  // existe para o dia em que deixar de ser.
  const year = (y: number, scale: number, o: { minority?: number | null } = {}): FundamentalsSnapshot =>
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
      cash: 500,
      shortTermDebt: 1000,
      longTermDebt: 3000,
      totalStockholderEquity: 6000 * scale,
      minorityInterest: o.minority ?? null,
      bookValuePerShare: 6.0 * scale,
      operatingCashFlow: 2000 * scale,
      nopat: 1188 * scale,
      sharesOutstanding: 1000,
      sharesOutstandingAsOf: 1000,
      marketCap: 12000,
    });

  const series = (o: { minority?: number | null } = {}): FundamentalsSnapshot[] => {
    const out: FundamentalsSnapshot[] = [];
    let scale = 1.0;
    for (let i = 12; i >= 0; i--) {
      out.push(year(2025 - i, scale, o));
      scale *= 1.05;
    }
    return out;
  };

  /**
   * Sem beta desalavancado **não há realavancagem**, e a avaliação recua
   * para o WACC estático — que é exatamente a condição do aviso.
   */
  const evaluate = (o: { minority?: number | null; betaU?: number | null } = {}): ValuationResult | null =>
    ValuationCascade.evaluate(
      new ValuationInputs({
        ticker,
        asOf: day(2026, 9, 9),
        fundamentals: series({ minority: o.minority ?? null }),
        marketPrice: 12.0,
        capm: new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 }),
        declaredTerminalRiskFreeRate: 0.094,
        unleveredBeta: o.betaU ?? null,
      }),
    ).valueOrNull;

  const declares = (v: ValuationResult | null): boolean =>
    v?.warnings.some((w) => w.includes('não controladores')) ?? false;

  it('recuo estático com minoritário material declara', () => {
    // 900 de minoritário contra 6.000 do controlador: 13% do consolidado.
    const v = evaluate({ minority: 900 });
    expect(v).not.toBeNull();
    expect(declares(v)).toBe(true);
  });

  it('minoritário abaixo da materialidade não declara', () => {
    // 30 contra 6.000: 0,5% do consolidado, abaixo do corte de 1%.
    expect(declares(evaluate({ minority: 30 }))).toBe(false);
  });

  it('sem minoritário não declara', () => {
    expect(declares(evaluate())).toBe(false);
  });

  it('com as taxas resolvidas não declara, mesmo com minoritário grande', () => {
    // **É a metade que importa.** O caminho resolvido pondera pelo capital
    // próprio do modelo, que já é o consolidado: ali o minoritário não falta
    // no peso, e avisar seria cobrar defeito que não existe.
    const v = evaluate({ minority: 900, betaU: 0.8 });
    expect(v).not.toBeNull();
    expect(
      v!.warnings.some((w) => w.includes('resolvido ano a ano')),
      'o cenário precisa mesmo resolver as taxas, ou o teste não prova nada',
    ).toBe(true);
    expect(declares(v)).toBe(false);
  });

  it('o aviso não muda o preço justo', () => {
    const withInput = evaluate({ minority: 900 });
    const without = evaluate({ minority: 30 });
    // A mesma companhia, com o minoritário apenas mudando de tamanho, muda
    // de preço pela ponte (decisão 49) — o que o teste cobra é que o aviso
    // em si não entre na conta: ele é narrativa.
    expect(withInput).not.toBeNull();
    expect(without).not.toBeNull();
    expectClose(
      withInput!.discountRate,
      without!.discountRate,
      1e-12,
      'o minoritário não entra no peso, e declarar não o põe lá',
    );
  });
});

describe('A rota derivada remunera o caixa pela taxa dele', () => {
  // Lente `metodo`, 21/09/2026; decisão 119. A decisão 113 separou o caixa
  // no **WACC**; a ponte do acionista continuava com `D_líquida · K_d`, de
  // modo que a companhia de caixa líquido recebia receita financeira ao
  // custo de **empréstimo**. É o caminho de produção da via da firma desde a
  // decisão 102, e o fluxo do acionista saía inflado.
  const assumptions = new DcfAssumptions({
    growthRate: 0.06,
    perpetualGrowth: 0.045,
    discountRate: 0.16,
    terminalDiscountRate: 0.14,
    reinvestmentPolicy: ReinvestmentPolicy.none,
  });

  /**
   * A **dívida líquida é a mesma em todas as chamadas**: é ela que a ponte
   * desconta, e variá-la mediria outra coisa. O que varia é quanto dela é
   * caixa, e a que taxa esse caixa rende.
   */
  const derivedOutcome = (o: { cash?: number; income?: number | null } = {}): DcfOutcome =>
    DcfCalculator.equityFromFirm({
      baseProfit: 1000,
      assumptions,
      netDebt: 1500,
      sharesOutstanding: 1000,
      costOfDebt: 0.18,
      taxRate: 0.34,
      equityDiscountRate: 0.18,
      terminalEquityDiscountRate: 0.16,
      cash: o.cash ?? 0,
      cashYield: o.income ?? null,
    }).unwrap();

  it('sem rendimento declarado, vale a forma anterior', () => {
    expectClose(
      derivedOutcome({ cash: 2500 }).fairValuePerShare,
      derivedOutcome().fairValuePerShare,
      1e-9,
      'sem `cashYield`, as duas metades pagam a mesma taxa e a separação não pode mover nada',
    );
  });

  it('com o rendimento, o caixa deixa de render prêmio de crédito', () => {
    const before = derivedOutcome({ cash: 2500 });
    const after = derivedOutcome({ cash: 2500, income: 0.14 });
    expect(after.fairValuePerShare, 'render `R_f` em vez de `R_f + spread` reduz o fluxo do acionista').toBeLessThan(
      before.fairValuePerShare,
    );
  });

  it('a diferença é exatamente o spread sobre o caixa, descontada', () => {
    // O serviço da dívida muda em `C·(K_d − R_f)·(1 − τ)` no ano 1, e o
    // caixa cresce a `g` como a dívida: a diferença de fluxo de cada ano é
    // essa, e nada mais.
    const cash = 2500.0;
    const kd = 0.18;
    const rf = 0.14;
    const tau = 0.34;
    const before = derivedOutcome({ cash });
    const after = derivedOutcome({ cash, income: rf });
    const expected = cash * (kd - rf) * (1 - tau);
    expectClose(before.projectedFlows[0]! - after.projectedFlows[0]!, expected, 1e-9);
  });

  it('caixa zero não muda nada, com ou sem rendimento', () => {
    expectClose(derivedOutcome({ income: 0.14 }).fairValuePerShare, derivedOutcome().fairValuePerShare, 1e-12);
  });

  it('a dívida projetada é a mesma: o que muda é a taxa', () => {
    // As duas metades crescem com o mesmo fator, e a diferença delas é a
    // série líquida de antes. Se a separação mudasse a dívida, a ponte
    // deixaria de ser a mesma do DCF.
    const a = derivedOutcome({ cash: 2500 });
    const b = derivedOutcome({ cash: 2500, income: 0.14 });
    // O fluxo da **firma** não depende do financiamento: ele é o mesmo nos
    // dois, e é isso que isola a mudança no serviço da dívida.
    expect(a.projectedFlows.length).toBe(b.projectedFlows.length);
    for (let t = 1; t < a.projectedFlows.length; t++) {
      const diffA = a.projectedFlows[t]! - b.projectedFlows[t]!;
      const previousDiff = a.projectedFlows[t - 1]! - b.projectedFlows[t - 1]!;
      // `g_t` é o crescimento do ano `t`, que é o que leva o saldo do
      // início do ano `t` ao do início do ano `t+1`. Ele **decai** ao longo
      // da projeção, e fixar 6% aqui era supor um caminho que o modelo não
      // percorre.
      expectClose(
        diffA / previousDiff,
        1 + assumptions.growthAt(t),
        1e-9,
        `a diferença cresce a \`g_t\`, porque o caixa cresce a \`g_t\` — ano ${t}`,
      );
    }
  });
});

describe('O caixa rende a taxa livre de risco, e não o custo de empréstimo', () => {
  // Lente `metodo`, 21/09/2026. A decisão 104 pôs a dívida **líquida** nos
  // pesos e disse, no caso sem dívida contratada, que o que remunera o peso
  // negativo é caixa — e caixa rende `R_f`. A regra valia só quando a dívida
  // **bruta** era zero: com dívida e caixa maior que ela, o peso negativo
  // continuava remunerado ao custo de **empréstimo**, e o WACC saía baixo
  // demais justamente nos balanços mais líquidos.
  const capm = new CapmInputs({ riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055 });
  const tax = ValuationParameters.statutoryTaxRate;

  const cost = (o: { cash?: number | null; debt?: number } = {}): CostOfCapital =>
    new CostOfCapital({
      capm,
      costOfDebt: 0.18,
      taxRate: tax,
      equityValue: 12000,
      debtValue: o.debt ?? -2000,
      interestCoverage: 4.0,
      cashValue: o.cash ?? null,
    });

  it('sem o caixa, vale a forma de uma perna só', () => {
    const c = cost();
    expect(c.grossDebtShare).toBeNull();
    expect(c.cashShare).toBeNull();
    const expected = c.equityShare * c.costOfEquity + c.debtShare * c.effectiveCostOfDebt * (1 - c.effectiveTaxShield);
    expectClose(c.rawWacc, expected, 1e-12);
  });

  it('a separação move o WACC pela diferença entre as duas taxas', () => {
    const without = cost();
    const withInput = cost({ cash: 6000 });
    // `w_caixa · [K_d(1 − escudo) − R_f(1 − τ)]`: a perna é a mesma, e o que
    // muda é a taxa da metade que **rende**.
    const difference =
      withInput.cashShare! *
      (withInput.effectiveCostOfDebt * (1 - withInput.effectiveTaxShield) - capm.riskFreeRate * (1 - tax));
    expectClose(withInput.rawWacc - without.rawWacc, difference, 1e-12);
    expect(withInput.rawWacc, 'o caixa deixa de ser creditado com prêmio de crédito').toBeGreaterThan(without.rawWacc);
  });

  it('os pesos não mudam: só a taxa de cada metade', () => {
    const c = cost({ cash: 6000 });
    expectClose(c.grossDebtShare! - c.cashShare!, c.debtShare, 1e-12);
    expect(c.grossDebtShare!, 'a bruta é 4.000 com 6.000 de caixa e −2.000 de líquida').toBeGreaterThan(0.0);
  });

  it('mesma dívida líquida, mais caixa: o desconto é maior', () => {
    // O caso que a forma anterior não distinguia — os dois balanços davam o
    // mesmo WACC, embora um tenha o dobro de caixa aplicado à taxa básica.
    const lean = cost({ cash: 2000 });
    const bloated = cost({ cash: 8000 });
    expectClose(bloated.debtShare, lean.debtShare, 1e-12);
    expect(bloated.rawWacc).toBeGreaterThan(lean.rawWacc);
  });

  it('o rendimento do caixa é tributado, e não escudado', () => {
    const c = cost({ cash: 6000 });
    expectClose(c.afterTaxCashYield, capm.riskFreeRate * (1 - tax), 1e-12);
  });

  it('o rastro mostra a forma de três pernas que a conta usou', () => {
    const itsSeries: FundamentalsSnapshot[] = [];
    let scale = 1.0;
    for (let i = 12; i >= 0; i--) {
      itsSeries.push(
        new FundamentalsSnapshot({
          ticker,
          fiscalPeriodEnd: day(2025 - i, 12, 31),
          totalRevenue: 10000 * scale,
          ebit: 1800 * scale,
          ebitda: 2400 * scale,
          netIncome: 900 * scale,
          incomeBeforeTax: 1300 * scale,
          incomeTaxExpense: -400 * scale,
          interestExpense: 400,
          earningsPerShare: 0.9 * scale,
          cash: 3000,
          shortTermDebt: 1000,
          longTermDebt: 3000,
          totalStockholderEquity: 6000 * scale,
          bookValuePerShare: 6.0 * scale,
          operatingCashFlow: 2000 * scale,
          nopat: 1188 * scale,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          marketCap: 12000,
        }),
      );
      scale *= 1.05;
    }
    const trace = captureEvents(() =>
      ValuationCascade.evaluate(
        new ValuationInputs({
          ticker,
          asOf: day(2026, 9, 9),
          fundamentals: itsSeries,
          marketPrice: 12.0,
          capm,
          declaredTerminalRiskFreeRate: 0.094,
        }),
      ),
    );
    expect(trace).toHaveLength(1);
    const step = trace[0]!.calculations.find((p) => p.formulaName.includes('WACC'))!;
    expect(Object.keys(step.mappedVariables)).toContain('C — caixa (R$)');
    expect(Object.keys(step.mappedVariables)).toContain('D bruta (R$)');
    expectClose(step.mappedVariables['C — caixa (R$)'] as number, 3000, 0.01);
    expect(step.latexRepresentation).toContain('R_f');
    expect(step.intermediateSteps.some((e) => e.includes('o caixa rende a taxa livre'))).toBe(true);
  });
});
