/**
 * Encolhimento do beta por precisão, e a desalavancagem de Hamada.
 *
 * O que estes testes travam é o comportamento nos **dois extremos**: um beta
 * preciso decide sozinho, e um beta sem informação não decide nada. É o que
 * separa este desenho da proposta que a medição de 10/09/2026 descartou —
 * substituir a regressão pela mediana setorial moveria o `Ke` do ativo mediano
 * em 2,13 p.p. sem ganho medido.
 */
import { describe, expect, it } from 'vitest';

import {
  BetaObservation,
  BetaPrior,
  BetaShrinkage,
  DateRange,
  FundamentalsSnapshot,
  MarketLeverage,
  PricePoint,
  ResolveBetaPrior,
  type ShrunkBeta,
  Ticker,
} from '../../src/core';
import { day, expectClose, expectNotClose } from './helpers';

const prior = new BetaPrior({
  unleveredBySector: new Map([
    ['energia', 0.3],
    ['tecnologia', 1.1],
  ]),
  unleveredUniverse: 0.46,
  dispersion: 0.53,
});

describe('Hamada', () => {
  it('desalavancar e realavancar fecha o ciclo', () => {
    const debtToEquity = 0.8;
    const t = 0.25;
    const f = BetaShrinkage.leverageFactor({ debtToEquity, taxRate: t })!;
    const u = BetaShrinkage.unlever({ leveredBeta: 1.2, debtToEquity, taxRate: t })!;
    expectClose(f, 1 + 0.75 * 0.8, 1e-12);
    expectClose(u * f, 1.2, 1e-12);
  });

  it('sem dívida o beta desalavancado é o próprio', () => {
    expectClose(BetaShrinkage.unlever({ leveredBeta: 0.9, debtToEquity: 0, taxRate: 0.3 }), 0.9, 1e-12);
  });

  it('D/E é confinado no teto', () => {
    // A AZUL3 tem D/E de 94,5, e Hamada supõe dívida sem risco: acima de
    // alguma alavancagem o capital próprio é opção sobre os ativos, e a
    // relação linear deixa de descrever. Sem teto, realavancar um prior por
    // 94,5 inventaria um beta de dezenas.
    const atCap = BetaShrinkage.leverageFactor({ debtToEquity: BetaShrinkage.maxDebtToEquity, taxRate: 0.25 });
    const farAbove = BetaShrinkage.leverageFactor({ debtToEquity: 94.5, taxRate: 0.25 });
    expect(farAbove).toBe(atCap);
  });

  it('entrada não finita devolve nulo', () => {
    expect(BetaShrinkage.unlever({ leveredBeta: Number.NaN, debtToEquity: 0.5, taxRate: 0.3 })).toBeNull();
  });
});

describe('A régua da alavancagem é uma só', () => {
  // O beta é desalavancado numa ponta e realavancado na outra. Se as duas
  // usarem dívidas diferentes, a ida e a volta não se cancelam: medido em
  // 11/09/2026, com a bruta na ida e a líquida na volta, o beta que voltava
  // era menor que o medido em **100 dos 127** avaliados.
  const withCash = (cash: number, debt: number): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker: Ticker.parse('TEST3'),
      fiscalPeriodEnd: day(2025, 12, 31),
      cash,
      shortTermDebt: debt * 0.2,
      longTermDebt: debt * 0.8,
      netIncome: 500,
      ebit: 800,
    });

  it('é a dívida líquida sobre o valor de mercado', () => {
    const s = withCash(400, 1000);
    expectClose(s.debtToMarketEquity(2000), 600 / 2000, 1e-12);
    // E não a bruta, que daria metade a mais.
    expectNotClose(s.debtToMarketEquity(2000)!, 1000 / 2000, 1e-9);
  });

  it('caixa maior que a dívida devolve alavancagem negativa', () => {
    // Negativa e não nula: quem consome é que confina, e confinar aqui
    // esconderia o caixa de quem quisesse vê-lo.
    expect(withCash(1500, 1000).debtToMarketEquity(2000)!).toBeLessThan(0);
  });

  it('sem valor de mercado utilizável, não há alavancagem', () => {
    const s = withCash(400, 1000);
    expect(s.debtToMarketEquity(null)).toBeNull();
    expect(s.debtToMarketEquity(0)).toBeNull();
    expect(s.debtToMarketEquity(-100)).toBeNull();
    expect(s.debtToMarketEquity(Number.NaN)).toBeNull();
  });

  it('a ida e a volta se cancelam sob a mesma régua', () => {
    const s = withCash(400, 1000);
    const debtToEquity = s.debtToMarketEquity(2000)!;
    const tau = 0.3;
    const betaU = BetaShrinkage.unlever({ leveredBeta: 1.4, debtToEquity, taxRate: tau })!;
    const factor = BetaShrinkage.leverageFactor({ debtToEquity, taxRate: tau })!;
    expectClose(betaU * factor, 1.4, 1e-12);
  });
});

describe('A alavancagem é medida na janela do beta', () => {
  // O beta é covariância de cinco anos e carrega a estrutura de capital
  // daqueles cinco. Medido em 11/09/2026 sobre 124 ativos: o fator da janela
  // difere do de hoje em mais de 10% em 50 deles e em mais de 25% em 24 — a
  // CPLE3 aparece com 386,1% de dívida sobre valor de mercado hoje contra
  // 49,8% de mediana na janela.
  const ex = (year: number, debt: number, shares: number): FundamentalsSnapshot =>
    new FundamentalsSnapshot({
      ticker: Ticker.parse('TEST3'),
      fiscalPeriodEnd: day(year, 12, 31),
      shortTermDebt: debt * 0.3,
      longTermDebt: debt * 0.7,
      cash: 0,
      sharesOutstandingAsOf: shares,
      // A contagem **corrente**, propositalmente diferente: usá-la mediria
      // a empresa de hoje nos exercícios de então.
      sharesOutstanding: shares * 10,
      netIncome: 100,
    });

  const tradingDay = (year: number, month: number, d: number, price: number): PricePoint =>
    new PricePoint({ date: day(year, month, d), close: price });

  const window = new DateRange(day(2021, 1, 1), day(2026, 1, 1));

  it('mediana sobre a janela, com a contagem de ações do exercício', () => {
    // Preço 10 e 1.000 ações dão valor de mercado 10.000 em cada exercício;
    // a dívida varia, e a mediana é a do meio.
    const snaps = [ex(2022, 2000, 1000), ex(2023, 4000, 1000), ex(2024, 6000, 1000)];
    const prices = [tradingDay(2022, 12, 29, 10), tradingDay(2023, 12, 28, 10), tradingDay(2024, 12, 30, 10)];
    const debtToEquity = MarketLeverage.overWindow({ snapshots: snaps, prices, window });
    expectClose(debtToEquity, 0.4, 1e-12);
    // Com a contagem corrente — dez vezes maior — daria um décimo disso.
    expectNotClose(debtToEquity!, 0.04, 1e-9);
  });

  it('exercício sem pregão próximo fica de fora', () => {
    const snaps = [ex(2022, 2000, 1000), ex(2023, 4000, 1000), ex(2024, 6000, 1000)];
    // O pregão de 2023 está a mais de vinte dias do fechamento.
    const prices = [tradingDay(2022, 12, 29, 10), tradingDay(2023, 11, 20, 10), tradingDay(2024, 12, 30, 10)];
    expect(
      MarketLeverage.overWindow({ snapshots: snaps, prices, window }),
      'sobram dois exercícios, e o mínimo é três',
    ).toBeNull();
  });

  it('menos de três exercícios na janela devolve nulo', () => {
    expect(
      MarketLeverage.overWindow({
        snapshots: [ex(2023, 2000, 1000), ex(2024, 4000, 1000)],
        prices: [tradingDay(2023, 12, 28, 10), tradingDay(2024, 12, 30, 10)],
        window,
      }),
    ).toBeNull();
  });

  it('exercício fora da janela não entra', () => {
    const snaps = [
      ex(2015, 100000, 1000), // muito antigo, e muito alavancado
      ex(2022, 2000, 1000),
      ex(2023, 4000, 1000),
      ex(2024, 6000, 1000),
    ];
    const prices = [
      tradingDay(2015, 12, 30, 10),
      tradingDay(2022, 12, 29, 10),
      tradingDay(2023, 12, 28, 10),
      tradingDay(2024, 12, 30, 10),
    ];
    expectClose(
      MarketLeverage.overWindow({ snapshots: snaps, prices, window }),
      0.4,
      1e-12,
      'o exercício de 2015 deslocaria a mediana se entrasse',
    );
  });

  it('a contagem de dias não depende de horário de verão', () => {
    // `difference().inDays` entre datas locais dá 23 ou 25 horas numa
    // transição, e o truncamento erra por um dia — exatamente na margem em
    // que a escolha do pregão mais próximo é decidida.
    const snaps = [ex(2022, 2000, 1000), ex(2023, 4000, 1000), ex(2024, 6000, 1000)];
    // Pregões a exatamente vinte dias do fechamento, dos dois lados.
    const prices = [
      tradingDay(2023, 1, 18, 10), // 20 dias depois de 2022-12-31
      tradingDay(2023, 12, 11, 10), // 20 dias antes de 2023-12-31
      tradingDay(2025, 1, 20, 10), // 20 dias depois de 2024-12-31
    ];
    expectClose(
      MarketLeverage.overWindow({ snapshots: snaps, prices, window }),
      0.4,
      1e-12,
      'os três entram, e a mediana é a do exercício do meio',
    );
  });

  it('sem pregão algum devolve nulo', () => {
    expect(
      MarketLeverage.overWindow({
        snapshots: [ex(2022, 1, 1000), ex(2023, 1, 1000), ex(2024, 1, 1000)],
        prices: [],
        window,
      }),
    ).toBeNull();
  });
});

describe('Encolhimento por precisão', () => {
  const shrink = (o: { beta: number; se: number | null; sector?: string | null; debtToEquity?: number }): ShrunkBeta =>
    BetaShrinkage.shrink({
      leveredBeta: o.beta,
      standardError: o.se,
      prior,
      sectorKey: 'sector' in o ? (o.sector ?? null) : 'energia',
      debtToEquity: o.debtToEquity ?? 0.0,
      taxRate: 0.25,
    });

  it('beta preciso decide sozinho', () => {
    // Erro-padrão de 0,07 é a mediana medida no universo, com cinco anos de
    // pregão diário. O peso resultante é 0,98.
    const r = shrink({ beta: 1.2, se: 0.07 });
    expect(r.weight).toBeGreaterThan(0.97);
    expectClose(r.beta, 1.2, 0.02);
  });

  it('beta sem informação não decide nada — o caso AZUL3', () => {
    // β = 109.108 com ρ = 0,11 sobre 142 pregões dá erro-padrão de 83.228.
    const r = shrink({ beta: 109108.81, se: 83227.99 });
    expect(r.weight).toBeLessThan(1e-9);
    // A tolerância é 1e-4 e não 1e-9 de propósito: o peso não é zero cravado,
    // é 4e-11, e multiplicado por um beta de 109 mil deixa um resíduo de
    // 4,4e-6. É a conta fazendo exatamente o que deve — o traço do estimador
    // sem informação some, mas não por truncamento.
    expectClose(
      r.beta,
      prior.unleveredBySector.get('energia')!,
      1e-4,
      'sem dívida, o prior alavancado é o próprio desalavancado',
    );
  });

  it('erro-padrão ausente entrega o prior inteiro', () => {
    const r = shrink({ beta: 2.0, se: null });
    expect(r.weight).toBe(0.0);
    expectClose(r.beta, 0.3, 1e-12);
  });

  it('o peso é monótono na precisão', () => {
    const weight = (se: number): number => shrink({ beta: 1.0, se }).weight;
    let previous = 1.1;
    for (const se of [0.05, 0.1, 0.2, 0.4, 0.8, 1.6]) {
      const w = weight(se);
      expect(w).toBeLessThan(previous);
      previous = w;
    }
  });

  it('setor desconhecido cai no prior do universo', () => {
    const r = shrink({ beta: 3.0, se: null, sector: 'inexistente' });
    expectClose(r.beta, prior.unleveredUniverse, 1e-12);
    const withoutSector = shrink({ beta: 3.0, se: null, sector: null });
    expectClose(withoutSector.beta, prior.unleveredUniverse, 1e-12);
  });

  it('o prior é realavancado para a estrutura do próprio ativo', () => {
    // Duas empresas do mesmo setor com alavancagens diferentes não podem
    // receber o mesmo beta: o risco do negócio é o mesmo, o do acionista não.
    const withoutDebt = shrink({ beta: 1.0, se: null, debtToEquity: 0.0 });
    const withDebt = shrink({ beta: 1.0, se: null, debtToEquity: 1.0 });
    expect(withDebt.beta).toBeGreaterThan(withoutDebt.beta);
    expectClose(withDebt.beta, 0.3 * (1 + 0.75), 1e-12);
  });

  it('o desalavancado sai do beta ENCOLHIDO, e a volta é a identidade', () => {
    // É ele que liga `Ke` a `WACC`, e é por isso que sai junto em vez de
    // ficar dentro da conta.
    //
    // **Sai do encolhido e não do cru** (decisão 54): o ponto fixo
    // realavanca `unlevered` e nunca toca em `beta`, de modo que derivá-lo
    // do cru descartava o encolhimento inteiro para quem usa o caminho
    // resolvido — a maioria do universo. A decisão 40 troca precisão por
    // viés, e a troca não estava chegando ao preço.
    const r = shrink({ beta: 1.75, se: 0.07, debtToEquity: 1.0 });
    const factor = BetaShrinkage.leverageFactor({ debtToEquity: 1.0, taxRate: 0.25 })!;
    expectClose(r.unlevered, r.beta / factor, 1e-12);
    expectNotClose(r.beta, 1.75, 1e-6, 'sem encolhimento este teste não distingue as duas fontes');

    // Encolher em espaço alavancado e desalavancar o resultado é idêntico a
    // encolher em espaço desalavancado.
    const betaU = 1.75 / factor;
    const priorU = 0.3; // o prior setorial de energia no fixture
    expectClose(r.unlevered, r.weight * betaU + (1 - r.weight) * priorU, 1e-12);
  });

  it('a identidade vale também quando o prior leva tudo', () => {
    // Sem erro-padrão o encolhimento entrega o prior inteiro, e o
    // desalavancado tem de acompanhar.
    const r = shrink({ beta: 1.75, se: null, debtToEquity: 1.0 });
    const factor = BetaShrinkage.leverageFactor({ debtToEquity: 1.0, taxRate: 0.25 })!;
    expect(r.weight).toBe(0.0);
    expectClose(r.unlevered, r.beta / factor, 1e-12);
  });
});

describe('ResolveBetaPrior.fromObservations', () => {
  const obs = (beta: number, sector: string | null, debtToEquity = 0.0): BetaObservation =>
    new BetaObservation({ leveredBeta: beta, sectorKey: sector, debtToEquity, taxRate: 0.25 });

  it('mediana setorial exige pares suficientes', () => {
    const p = ResolveBetaPrior.fromObservations([
      obs(0.8, 'energia'),
      obs(0.9, 'energia'),
      obs(1.0, 'energia'),
      obs(2.0, 'raro'),
      obs(2.2, 'raro'),
    ]);
    expect(p).not.toBeNull();
    expect(p!.unleveredBySector.has('energia')).toBe(true);
    expect(p!.unleveredBySector.has('raro'), 'dois pares não sustentam mediana de setor').toBe(false);
    expectClose(p!.unleveredFor('energia'), 0.9, 1e-12);
    expect(p!.unleveredFor('raro')).toBe(p!.unleveredUniverse);
  });

  it('a dispersão sai dos betas alavancados', () => {
    const p = ResolveBetaPrior.fromObservations([0.5, 0.7, 0.9, 1.1, 1.3].map((b) => obs(b, 'energia')))!;
    expect(p.dispersion).toBeGreaterThan(0);
    // MAD escalado de {0,5..1,3} com passo 0,2: mediana 0,9, desvios
    // {0,4; 0,2; 0; 0,2; 0,4}, MAD 0,2, escalado por 1,4826.
    expectClose(p.dispersion, 0.2 * 1.4826, 1e-3);
  });

  it('sem observação utilizável devolve nulo', () => {
    expect(ResolveBetaPrior.fromObservations([])).toBeNull();
    expect(ResolveBetaPrior.fromObservations([obs(Number.NaN, 'energia')])).toBeNull();
  });

  it('setor vazio conta como ausência de setor', () => {
    const p = ResolveBetaPrior.fromObservations([obs(0.8, ''), obs(0.9, '  '), obs(1.0, null), obs(1.1, null)])!;
    expect(p.unleveredBySector.size).toBe(0);
    expect(p.unleveredFor('')).toBe(p.unleveredUniverse);
  });
});
