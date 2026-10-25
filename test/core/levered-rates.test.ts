/**
 * O ponto fixo do custo de capital, e a identidade que ele existe para fechar.
 *
 * A sonda de 10/09/2026 mediu que as duas rotas para o capital próprio
 * divergem 4,2% quando há crescimento: a dívida cresce a `g`, o valor não, e o
 * `WACC` montado com os pesos do ano zero deixa de descrever os anos seguintes.
 *
 * A rota (b) aceita que a alavancagem muda e reprecifica `Ke` a cada ano. O que
 * prova que ela funciona é a identidade voltar a fechar **com crescimento** —
 * é o que o primeiro teste verifica, e é o critério de aceite de D1.
 */
import { describe, expect, it } from 'vitest';

import {
  CashTiming,
  DcfAssumptions,
  DcfCalculator,
  LeveredCostOfCapital,
  type LeveredRates,
  type Result,
  toStringAsFixed,
} from '../../src/core';
import { expectClose } from './helpers';

const spread = 0.02;
const tax = 0.3;
const premium = 0.055;
const betaU = 0.6;
const rf = 0.09;
// O `K_d` aplicado é `Rf + spread` — a classificação sintética, a mesma do
// WACC estático (item B11). Com a taxa livre de risco constante nestes
// testes, ele é o número único de antes.
const kd = rf + spread;

const filled = (n: number, x: number): number[] => new Array<number>(n).fill(x);

/** Cópia mutável para passar ao `copyWith`, que guarda a lista como está. */
const v = (x: readonly number[]): number[] => [...x];

// **Sob a convenção de fim de ano, de propósito.** `FCFF/WACC ≡ FCFE/Ke` é
// identidade algébrica exata quando os dois fluxos são descontados nos
// mesmos instantes. O meio de ano desloca cada um por meio ano descontado à
// **sua** taxa — `√(1+WACC)` de um lado, `√(1+Ke)` do outro —, e o vão que
// sobra é o termo de spread, medido no próprio arquivo. O que estes testes
// provam é a álgebra do ponto fixo, e ela se prova onde é exata.
const assumptions = (o: { g: number; rate?: number; timing?: CashTiming }): DcfAssumptions =>
  new DcfAssumptions({
    projectionYears: 10,
    growthRate: o.g,
    perpetualGrowth: o.g,
    discountRate: o.rate ?? 0.13,
    terminalDiscountRate: o.rate ?? 0.13,
    returnOnCapital: 0.0,
    cashTiming: o.timing ?? CashTiming.endOfYear,
  });

const base = 1000.0;
const resolver = (o: {
  g: number;
  debt: number;
  base?: number;
  timing?: CashTiming;
  cash?: number;
}): Result<LeveredRates> =>
  LeveredCostOfCapital.solve({
    baseProfit: o.base ?? base,
    assumptions: assumptions({ g: o.g, timing: o.timing ?? CashTiming.endOfYear }),
    netDebt: o.debt,
    unleveredBeta: betaU,
    riskFreePath: filled(10, rf),
    terminalRiskFree: rf,
    marketPremium: premium,
    creditSpread: spread,
    taxRate: tax,
    cash: o.cash ?? null,
  });

const ok = <T>(r: Result<T>): T => {
  expect(r.isOk, r.failureOrNull?.message).toBe(true);
  return r.unwrap();
};

describe('Ponto fixo do custo de capital', () => {
  it('converge, e o caminho de taxas acompanha a alavancagem', () => {
    const r = ok(resolver({ g: 0.05, debt: 3000 }));

    expect(r.converged, `não convergiu em ${r.iterations} iterações`).toBe(true);
    expect(r.costOfEquity).toHaveLength(10);
    expect(r.wacc).toHaveLength(10);

    // A dívida cresce a `g` e o valor cresce a outra taxa: a participação do
    // capital próprio **muda**, e é isso que a rota (b) precisa enxergar.
    const s0 = r.equityShareAt(0)!;
    const sN = r.equityShareAt(10)!;
    expect(Math.abs(s0 - sN), 'sem variação de alavancagem o teste não mede nada').toBeGreaterThan(0.01);

    // Alavancagem subindo é `Ke` subindo: é a relação de Hamada.
    if (sN < s0) {
      expect(r.costOfEquity[r.costOfEquity.length - 1]!).toBeGreaterThan(r.costOfEquity[0]!);
    } else {
      expect(r.costOfEquity[r.costOfEquity.length - 1]!).toBeLessThan(r.costOfEquity[0]!);
    }
  });

  it('o valor que alimenta a alavancagem é o mesmo que sai no preço', () => {
    // **A invariante que a convenção de caixa poderia quebrar em silêncio.**
    // O ponto fixo reconstrói o valor ano a ano por acumulação regressiva
    // para conhecer `D/E`; o preço sai do desconto direto. Se as duas contas
    // usarem convenções diferentes, `V` fica na de fim de ano e `D` não é
    // levantado — de modo que `D/E` sai inflado e o `Ke` com ele, sem que
    // nada acuse.
    for (const timing of CashTiming.values) {
      const r = ok(resolver({ g: 0.05, debt: 3000, timing }));

      const direct = DcfCalculator.firm({
        baseProfit: base,
        assumptions: assumptions({ g: 0.05, timing }).copyWith({
          discountRatePath: r.wacc,
          terminalDiscountRate: r.terminalWacc,
        }),
        netDebt: 0,
        sharesOutstanding: 1,
      }).unwrap();

      expectClose(
        r.enterpriseValue[0]! / direct.enterpriseValue,
        1.0,
        1e-9,
        `sob ${timing.key} a acumulação regressiva não reproduz o valor descontado`,
      );
    }
  });

  it('AS DUAS ROTAS COINCIDEM COM CRESCIMENTO — o critério de D1', () => {
    const g = 0.05;
    const debt = 3000.0;
    const securities = 100.0;
    const r = resolver({ g, debt }).unwrap();

    const withPath = assumptions({ g }).copyWith({ discountRatePath: v(r.wacc), terminalDiscountRate: r.terminalWacc });

    const firm = DcfCalculator.firm({ baseProfit: 1000, assumptions: withPath, netDebt: debt, sharesOutstanding: securities });
    expect(firm.isOk, firm.failureOrNull?.message).toBe(true);

    const shareholder = DcfCalculator.equityFromFirm({
      baseProfit: 1000,
      assumptions: withPath,
      netDebt: debt,
      sharesOutstanding: securities,
      costOfDebt: kd,
      taxRate: tax,
      equityDiscountRate: r.costOfEquity[0]!,
      terminalEquityDiscountRate: r.terminalCostOfEquity,
      equityDiscountRatePath: v(r.costOfEquity),
    });
    expect(shareholder.isOk, shareholder.failureOrNull?.message).toBe(true);

    const a = firm.unwrap().fairValuePerShare;
    const b = shareholder.unwrap().fairValuePerShare;
    const divergence = Math.abs(b / a - 1);

    // Sob a interpolação de dois pontos esta divergência era de 4,2%.
    expect(
      divergence,
      `firma R$ ${a} contra acionista R$ ${b} (${toStringAsFixed(divergence * 100, 2)}%)`,
    ).toBeLessThan(1e-6);
  });

  it('a dívida cresce ao ritmo do lucro, e o prêmio de crédito não tem o que mudar', () => {
    // O prêmio sintético sai de dívida ÷ EBITDA. Com a dívida crescendo a
    // `g_t` como o lucro projetado, a razão fica parada — e é essa a
    // premissa que torna correto um prêmio só para o caminho inteiro.
    const a = assumptions({ g: 0.06 });
    const r = resolver({ g: 0.06, debt: 3000 }).unwrap();
    for (let t = 1; t < r.debt.length; t++) {
      expectClose(r.debt[t]! / r.debt[t - 1]! - 1, a.growthAt(t), 1e-12);
    }
  });

  it('sem dívida o caminho é plano e igual ao CAPM sem alavancagem', () => {
    const r = resolver({ g: 0.04, debt: 0 }).unwrap();
    const expected = rf + betaU * premium;
    for (const k of r.costOfEquity) {
      expectClose(k, expected, 1e-9);
    }
    for (const w of r.wacc) {
      expectClose(w, expected, 1e-9, 'sem dívida o WACC é o próprio Ke');
    }
    expectClose(r.terminalCostOfEquity, expected, 1e-9);
  });

  it('capital próprio que desaparece vira recusa nomeada', () => {
    // Dívida grande demais para o fluxo sustentar: em vez de devolver um
    // preço por papel que é resíduo de subtração, recusa.
    const r = resolver({ g: 0.02, debt: 500000, base: 100 });
    expect(r.isErr).toBe(true);
    expect(r.failureOrNull!.message).toContain('capital próprio');
    // **A recusa diz quando aconteceu**, e é disso que a cascata precisa
    // para separar "a estrutura não fecha" de "o ponto fixo passeou": a
    // primeira iteração usa a interpolação de dois pontos como chute, de
    // modo que falhar nela é a interpolação já estar inviável.
    expect(r.failureOrNull!.message).toContain('iteração');
    expect(r.failureOrNull!.message).toContain('ano');
  });

  it('caixa líquido não quebra o peso do capital', () => {
    // `netDebt` negativo é empresa de caixa líquido, e `E + D` fica menor
    // que `E`. Sem guarda o peso divide por zero quando o caixa se aproxima
    // do próprio valor.
    const r = ok(resolver({ g: 0.03, debt: -2000 }));
    for (const w of r.wacc) {
      expect(Number.isFinite(w)).toBe(true);
      expect(w).toBeGreaterThan(0);
    }
    // Sem dívida líquida positiva não há alavancagem: o fator de Hamada é
    // confinado no piso, e o `Ke` é o desalavancado puro.
    const expected = rf + betaU * premium;
    expectClose(r.costOfEquity[0], expected, 1e-9);
  });

  it('caixa líquido extremo mantém as taxas finitas', () => {
    // `E + D` é o valor da firma, e com lucro-base positivo ele não pode ser
    // não positivo — a guarda contra isso é rede de segurança, não caminho
    // alcançável daqui. O que se trava é que caixa de ordem de grandeza
    // maior que o próprio negócio não produz taxa infinita nem NaN.
    const r = ok(resolver({ g: 0.01, debt: -1e9, base: 100 }));
    for (const w of r.wacc) {
      expect(Number.isFinite(w)).toBe(true);
      expect(w).toBeGreaterThan(0);
    }
    expect(Number.isFinite(r.terminalWacc)).toBe(true);
    // Com caixa dominando, o peso do capital próprio passa de 1 — e **não é
    // confinado** (decisão 104): o peso da dívida fica negativo e o `WACC`
    // sobe acima do `Ke`, que é o mesmo tratamento do WACC estático.
    expect(r.equityShareAt(0)!).toBeGreaterThan(1.0);
    expect(
      r.wacc[0]!,
      'com caixa líquido o ativo operacional sozinho é mais caro que a companhia inteira',
    ).toBeGreaterThan(r.costOfEquity[0]!);
  });

  it('o custo da dívida é Rf do ano mais o prêmio, e decai com a curva', () => {
    // Item B11. Antes entrava o custo **observado**, que não decai com a
    // curva: a perpetuidade herdava o juro de hoje. Agora o `K_d` de cada ano
    // é `Rf_t + spread`, como em `CostOfCapital.effectiveCostOfDebt`.
    const terminalRf = 0.06;
    const r = ok(
      LeveredCostOfCapital.solve({
        baseProfit: base,
        assumptions: assumptions({ g: 0.04 }),
        netDebt: 3000,
        unleveredBeta: betaU,
        riskFreePath: filled(10, rf),
        terminalRiskFree: terminalRf,
        marketPremium: premium,
        creditSpread: spread,
        taxRate: tax,
      }),
    );

    // O `K_d` implícito sai da própria identidade do WACC do ano, com o peso
    // que o ponto fixo fixou: é o número que a conta usou, e não um número
    // remontado por outro caminho.
    const impliedKd = (wacc: number, ke: number, equityWeight: number): number =>
      (wacc - ke * equityWeight) / ((1 - equityWeight) * (1 - tax));

    expectClose(impliedKd(r.wacc[0]!, r.costOfEquity[0]!, r.equityShareAt(0)!), rf + spread, 1e-9);
    expectClose(
      impliedKd(r.terminalWacc, r.terminalCostOfEquity, r.equityShareAt(10)!),
      terminalRf + spread,
      1e-9,
      'o prêmio de crédito é da empresa; a taxa base é do ano',
    );
  });

  it('exige beta desalavancado, e recusa sem ele', () => {
    const r = LeveredCostOfCapital.solve({
      baseProfit: 1000,
      assumptions: assumptions({ g: 0.04 }),
      netDebt: 1000,
      unleveredBeta: Number.NaN,
      riskFreePath: filled(10, rf),
      terminalRiskFree: rf,
      marketPremium: premium,
      creditSpread: spread,
      taxRate: tax,
    });
    expect(r.isErr).toBe(true);
    expect(r.failureOrNull!.message).toContain('desalavancado');
  });

  it('caminho de taxa livre de risco com tamanho errado é recusado', () => {
    const r = LeveredCostOfCapital.solve({
      baseProfit: 1000,
      assumptions: assumptions({ g: 0.04 }),
      netDebt: 1000,
      unleveredBeta: betaU,
      riskFreePath: filled(3, rf),
      terminalRiskFree: rf,
      marketPremium: premium,
      creditSpread: spread,
      taxRate: tax,
    });
    expect(r.isErr).toBe(true);
  });
});

describe('Caminho explícito de desconto no DCF', () => {
  it('caminho de tamanho errado é recusado', () => {
    const r = DcfCalculator.firm({
      baseProfit: 100,
      assumptions: new DcfAssumptions({
        projectionYears: 10,
        growthRate: 0.04,
        perpetualGrowth: 0.04,
        discountRate: 0.13,
        returnOnCapital: 0.0,
        discountRatePath: [0.13, 0.13, 0.13],
      }),
      netDebt: 0,
      sharesOutstanding: 1,
    });
    expect(r.isErr).toBe(true);
  });

  it('caminho constante reproduz a taxa única', () => {
    const a = new DcfAssumptions({
      projectionYears: 10,
      growthRate: 0.04,
      perpetualGrowth: 0.04,
      discountRate: 0.13,
      returnOnCapital: 0.0,
    });
    const withoutPath = DcfCalculator.firm({ baseProfit: 100, assumptions: a, netDebt: 0, sharesOutstanding: 1 });
    const withPath = DcfCalculator.firm({
      baseProfit: 100,
      assumptions: a.copyWith({ discountRatePath: filled(10, 0.13) }),
      netDebt: 0,
      sharesOutstanding: 1,
    });
    expectClose(withPath.unwrap().fairValuePerShare, withoutPath.unwrap().fairValuePerShare, 1e-12);
  });
});

describe('O ponto fixo não depende de onde começa', () => {
  // Item B18, decisão 110. A recusa da decisão 45 saía da interpolação de
  // dois pontos — o recuo que a decisão 41 substituiu —, e não do ponto
  // fixo: os 14 ativos que saíram do aplicativo em 20/09/2026 foram
  // recusados todos na primeira iteração. Agora o ponto fixo é tentado de
  // duas partidas, e um ponto fixo é um ponto fixo.
  const withGuess = (rate: number, debt = 3000): Result<LeveredRates> =>
    LeveredCostOfCapital.solve({
      baseProfit: base,
      assumptions: new DcfAssumptions({
        projectionYears: 10,
        growthRate: 0.05,
        perpetualGrowth: 0.05,
        discountRate: rate,
        terminalDiscountRate: rate,
        returnOnCapital: 0.0,
        cashTiming: CashTiming.endOfYear,
      }),
      netDebt: debt,
      unleveredBeta: betaU,
      riskFreePath: filled(10, rf),
      terminalRiskFree: rf,
      marketPremium: premium,
      creditSpread: spread,
      taxRate: tax,
    });

  it('dois chutes bem diferentes chegam ao mesmo lugar', () => {
    // O chute só semeia: dentro do laço o caminho é reescrito. Se a resposta
    // dependesse dele, ela seria do chute.
    const low = withGuess(0.1).unwrap();
    const high = withGuess(0.3).unwrap();
    expect(low.converged && high.converged).toBe(true);
    expect(
      Math.abs(high.equity[0]! / low.equity[0]! - 1),
      'o mesmo ponto fixo, por caminhos diferentes',
    ).toBeLessThan(LeveredCostOfCapital.startIndependence);
    expectClose(high.terminalWacc, low.terminalWacc, 1e-6);
  });

  it('chute que mata o capital próprio não decide a recusa', () => {
    // Com o chute alto o capital próprio some no ano zero da primeira
    // iteração; a partida desalavancada fecha, e é ela que vale.
    const warnings: string[] = [];
    const r = LeveredCostOfCapital.solve({
      baseProfit: base,
      assumptions: new DcfAssumptions({
        projectionYears: 10,
        growthRate: 0.05,
        perpetualGrowth: 0.05,
        // Um chute absurdamente caro: a interpolação não sustenta a dívida.
        discountRate: 0.9,
        terminalDiscountRate: 0.9,
        returnOnCapital: 0.0,
        cashTiming: CashTiming.endOfYear,
      }),
      netDebt: 6000,
      unleveredBeta: 0.3,
      riskFreePath: filled(10, rf),
      terminalRiskFree: rf,
      marketPremium: premium,
      creditSpread: spread,
      taxRate: tax,
      warnings,
    });
    expect(r.isOk, r.failureOrNull?.message).toBe(true);
    expect(
      warnings.some((a) => a.includes('não fecha a partir do caminho sem realavancagem')),
      'quando as duas partidas discordam sobre existir solução, a avaliação precisa dizer de onde veio a que valeu',
    ).toBe(true);
  });

  it('quando nenhuma das duas fecha, a recusa diz que é do método', () => {
    const r = LeveredCostOfCapital.solve({
      baseProfit: 1.0,
      assumptions: new DcfAssumptions({
        projectionYears: 10,
        growthRate: 0.05,
        perpetualGrowth: 0.05,
        discountRate: 0.13,
        terminalDiscountRate: 0.13,
        returnOnCapital: 0.0,
        cashTiming: CashTiming.endOfYear,
      }),
      // Dívida de ordem de grandeza acima do que o fluxo sustenta.
      netDebt: 1e9,
      unleveredBeta: betaU,
      riskFreePath: filled(10, rf),
      terminalRiskFree: rf,
      marketPremium: premium,
      creditSpread: spread,
      taxRate: tax,
    });
    expect(r.isErr).toBe(true);
    expect(r.failureOrNull!.message).toContain('nenhuma das duas partidas');
    expect(r.failureOrNull!.message).toContain('e não do chute');
  });
});

describe('Ponto fixo pelo lado do acionista', () => {
  // A via do acionista avalia sozinha 33 dos 120 em produção, e em nenhum
  // deles a via da firma produz caminho de taxas para emprestar: ou o `Ke`
  // sai dos fluxos dela mesma, ou continua supondo a alavancagem de hoje
  // perene. Decisão 46.
  const resolveShareholder = (o: { g: number; debtPerShare: number; eps?: number; rate?: number }): Result<LeveredRates> =>
    LeveredCostOfCapital.solveEquity({
      baseProfit: o.eps ?? 1.0,
      assumptions: assumptions({ g: o.g, rate: o.rate ?? 0.13 }),
      netDebtPerShare: o.debtPerShare,
      unleveredBeta: betaU,
      riskFreePath: filled(10, rf),
      terminalRiskFree: rf,
      marketPremium: premium,
      taxRate: tax,
    });

  it('sem dívida, o caminho é plano e igual ao CAPM desalavancado', () => {
    const r = ok(resolveShareholder({ g: 0.04, debtPerShare: 0 }));
    expect(r.converged).toBe(true);
    const expected = rf + betaU * premium;
    for (const ke of r.costOfEquity) {
      expectClose(ke, expected, 1e-12);
    }
    expectClose(r.terminalCostOfEquity, expected, 1e-12);
    // Não há custo médio nesta via: `wacc` repete `Ke`, por contrato.
    expect(r.wacc).toEqual(r.costOfEquity);
    expect(r.terminalWacc).toBe(r.terminalCostOfEquity);
  });

  it('mais dívida por papel eleva o Ke, e é monótono', () => {
    const keOf = (d: number): number | null => {
      const r = resolveShareholder({ g: 0.04, debtPerShare: d });
      return r.isOk ? r.unwrap().costOfEquity[0]! : null;
    };

    let previous: number | null = null;
    let evaluated = 0;
    for (let step = 0; step <= 8; step++) {
      const ke = keOf(step * 1.5);
      if (ke === null) continue;
      evaluated++;
      if (previous !== null) {
        expect(ke, 'alavancar mais não pode baratear o capital próprio').toBeGreaterThanOrEqual(previous - 1e-12);
      }
      previous = ke;
    }
    expect(evaluated).toBeGreaterThan(5);
    expect(previous!, 'no topo da varredura a realavancagem tem de ter mordido').toBeGreaterThan(rf + betaU * premium);
  });

  it('a escala não muda nada: D/E é razão', () => {
    // Dobrar lucro e dívida por papel é a mesma empresa com metade das ações.
    const a = resolveShareholder({ g: 0.04, eps: 1.0, debtPerShare: 4.0 });
    const b = resolveShareholder({ g: 0.04, eps: 3.0, debtPerShare: 12.0 });
    expect(a.isOk && b.isOk).toBe(true);
    for (let t = 0; t < 10; t++) {
      expectClose(b.unwrap().costOfEquity[t], a.unwrap().costOfEquity[t]!, 1e-12);
    }
    expectClose(b.unwrap().terminalCostOfEquity, a.unwrap().terminalCostOfEquity, 1e-12);
  });

  it('a alavancagem se move ao longo da projeção, e o Ke com ela', () => {
    const r = ok(resolveShareholder({ g: 0.06, debtPerShare: 6.0 }));
    expect(r.converged).toBe(true);
    const s0 = r.equityShareAt(0)!;
    const sN = r.equityShareAt(10)!;
    expect(Math.abs(s0 - sN), 'sem variação de alavancagem o teste não mede nada').toBeGreaterThan(0.005);
    expect(
      Math.abs(r.costOfEquity[0]! - r.costOfEquity[r.costOfEquity.length - 1]!),
      'a taxa tem de acompanhar a alavancagem que se move',
    ).toBeGreaterThan(1e-6);
  });

  it('valor terminal divergente vira recusa datada', () => {
    // **Só com vantagem residual declarada.** No terminal neutro o valor é
    // `lucro/r` e não depende do crescimento perpétuo — de propósito, pela
    // decisão 25 —, de modo que a divergência nem existe ali. Com `moat` a
    // perpetuidade volta à forma de Gordon, e aí a taxa de equilíbrio tem de
    // superar `g`.
    const r = LeveredCostOfCapital.solveEquity({
      baseProfit: 1.0,
      assumptions: assumptions({ g: 0.14, rate: 0.1 }).copyWith({ terminalReturnOnCapital: 0.2 }),
      netDebtPerShare: 1.0,
      unleveredBeta: betaU,
      riskFreePath: filled(10, rf),
      terminalRiskFree: rf,
      marketPremium: premium,
      taxRate: tax,
    });
    expect(r.isErr).toBe(true);
    expect(r.failureOrNull!.message).toContain('iteração');
    expect(r.failureOrNull!.message).toContain('crescimento perpétuo');
  });

  it('participação sem sentido é nula, e não NaN', () => {
    // Pelo lado do acionista `enterpriseValue` é `E + D`, e com caixa
    // líquido maior que o próprio negócio ele fica não positivo: a razão
    // deixa de ter significado. O sentinela de ponto flutuante atravessava a
    // formatação e chegava ao aviso do usuário como `NaN%` — a auditoria
    // pegou, e o nulo obriga quem lê a decidir o que dizer.
    const r = ok(resolveShareholder({ g: 0.02, debtPerShare: -1e6 }));
    expect(
      r.enterpriseValue[0]!,
      'o fixture precisa produzir E + D não positivo para medir o que promete',
    ).toBeLessThanOrEqual(0);
    expect(r.equityShareAt(0)).toBeNull();
    // Fora do intervalo também é nulo, e não NaN.
    expect(r.equityShareAt(-1)).toBeNull();
    expect(r.equityShareAt(999)).toBeNull();
  });

  it('a dívida não cresce: o crescimento já sai do lucro retido', () => {
    // Item B11. Esta via desconta `lucro × (1 − b)`, isto é, o crescimento já
    // é financiado por retenção. Fazer a dívida crescer a `g` junto
    // financiaria o mesmo crescimento duas vezes, e o acionista pagaria o
    // `Ke` mais alto sem receber nada pela dívida nova.
    const r = ok(
      LeveredCostOfCapital.solveEquity({
        baseProfit: 1.0,
        assumptions: assumptions({ g: 0.08 }),
        netDebtPerShare: 3.0,
        unleveredBeta: betaU,
        riskFreePath: filled(10, rf),
        terminalRiskFree: rf,
        marketPremium: premium,
        taxRate: tax,
      }),
    );

    for (const d of r.debt) expectClose(d, 3.0, 1e-12, 'a dívida fica parada em termos nominais');
    const debtToEquity0 = r.debt[0]! / r.equity[0]!;
    const debtToEquityN = r.debt[r.debt.length - 1]! / r.equity[r.equity.length - 1]!;
    expect(
      debtToEquityN,
      'o capital próprio cresce pelo lucro retido e a dívida não: a alavancagem cai',
    ).toBeLessThan(debtToEquity0);
    expect(
      r.costOfEquity[r.costOfEquity.length - 1]!,
      'desalavancagem de verdade barateia o capital próprio',
    ).toBeLessThan(r.costOfEquity[0]!);
  });

  it('sem beta desalavancado, recusa', () => {
    const r = LeveredCostOfCapital.solveEquity({
      baseProfit: 1.0,
      assumptions: assumptions({ g: 0.04 }),
      netDebtPerShare: 2.0,
      unleveredBeta: Number.NaN,
      riskFreePath: filled(10, rf),
      terminalRiskFree: rf,
      marketPremium: premium,
      taxRate: tax,
    });
    expect(r.isErr).toBe(true);
    expect(r.failureOrNull!.message).toContain('desalavancado');
  });
});

describe('O caixa da via alavancada rende a taxa livre de risco', () => {
  // Lente `metodo`, 21/09/2026. A via da firma projetava a dívida
  // **líquida** e remunerava a perna inteira ao custo de empréstimo. Quem
  // tem caixa via a metade que rende `R_f` ser creditada com prêmio de
  // crédito — e o WACC saía baixo demais. A separação não muda os pesos:
  // as duas metades crescem com o mesmo fator, e a diferença delas é a
  // mesma série líquida de antes.
  it('a mesma dívida líquida, com caixa conhecido, custa mais', () => {
    const a = ok(resolver({ g: 0.05, debt: 3000 }));
    const b = ok(resolver({ g: 0.05, debt: 3000, cash: 2000 }));
    for (let t = 0; t < a.wacc.length; t++) {
      expect(b.wacc[t]!, `ano ${t + 1}: o caixa deixa de render prêmio de crédito`).toBeGreaterThan(a.wacc[t]!);
    }
    expect(b.terminalWacc).toBeGreaterThan(a.terminalWacc);
    expect(b.equity[0]!, 'taxa maior, valor menor').toBeLessThan(a.equity[0]!);
  });

  it('a dívida projetada é a mesma: o que muda é a taxa', () => {
    const without = resolver({ g: 0.05, debt: 3000 }).unwrap();
    const withInput = resolver({ g: 0.05, debt: 3000, cash: 2000 }).unwrap();
    for (let t = 0; t < without.debt.length; t++) {
      expectClose(withInput.debt[t], without.debt[t]!, 1e-9);
    }
  });

  it('o WACC do ano 1 fecha na forma de três pernas', () => {
    const r = resolver({ g: 0.05, debt: 3000, cash: 2000 }).unwrap();
    const cash = 2000.0;
    const v0 = r.equity[0]! + r.debt[0]!;
    const equityWeight = r.equity[0]! / v0;
    const wGross = (r.debt[0]! + cash) / v0;
    const wCash = cash / v0;
    const interest = (rf + spread) * (1 - tax);
    const income = rf * (1 - tax);
    expectClose(r.wacc[0], r.costOfEquity[0]! * equityWeight + interest * wGross - income * wCash, 1e-9);
    // E a soma dos dois pesos da perna é a participação da líquida: a
    // separação redistribui a mesma perna entre duas taxas.
    expectClose(wGross - wCash, 1 - equityWeight, 1e-12);
  });

  it('caixa zero é a forma anterior, bit a bit', () => {
    const without = resolver({ g: 0.05, debt: 3000 }).unwrap();
    const withInput = resolver({ g: 0.05, debt: 3000, cash: 0 }).unwrap();
    for (let t = 0; t < without.wacc.length; t++) {
      expectClose(withInput.wacc[t], without.wacc[t]!, 1e-12);
    }
    expectClose(withInput.terminalWacc, without.terminalWacc, 1e-12);
  });
});
