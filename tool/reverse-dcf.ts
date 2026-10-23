// DCF reverso — o que o preço de mercado está implicando.
//
// **A pergunta.** O potencial mediano do motor está em −38%: a cascata afirma
// que o mercado inteiro está caro. Isso é viés de nível, e há três causas
// candidatas, cada uma com um conserto diferente e caro:
//
//   1. o terminal neutro (`RONIC_∞ = WACC`), que zera todo valor de franquia
//      na perpetuidade e só é dispensado pela exceção binária de vantagem
//      competitiva;
//   2. a taxa de desconto, montada sobre CDI mais prêmio parametrizado de
//      5,5 p.p. com beta de regressão crua;
//   3. as saturações conservadoras — fator de base, trava de saúde, Porta 0.
//
// Corrigir a errada custa semanas. Pior: **o conserto do terminal fecha o vão
// independentemente da causa verdadeira**, porque um retorno terminal livre
// tem graus de liberdade de sobra para absorver um erro de taxa. O resultado
// pareceria certo por fora.
//
// **O que este utilitário mede.** Para cada ativo, varre a cascata inteira em
// dois eixos, um de cada vez, e procura o valor que iguala o preço justo ao
// preço de mercado:
//
//   - `RONIC_∞` implícito — que retorno sobre capital na perpetuidade o preço
//     está pagando, e como ele se compara ao ROIC que a empresa entregou na
//     mediana do ciclo;
//   - prêmio de risco implícito — que prêmio de mercado igualaria os dois, e
//     que Ke isso produz.
//
// **A varredura é por grade antes de bissecção, de propósito.** Bissecar
// pressupõe monotonia, e a cascata tem porta de migração de via, saturação e
// piso de WACC — qualquer um deles pode produzir degrau. A grade mede a
// monotonia em vez de supô-la, e um ativo com mais de um cruzamento é
// declarado como tal em vez de receber a primeira raiz encontrada.
//
// **Identificação.** As duas causas deixam assinaturas transversais
// diferentes: erro de terminal escala com o excedente `ROIC − WACC` do ativo
// — quem tem franquia é quem o motor mais subavalia —, e erro de taxa escala
// com beta e é indiferente ao excedente. A regressão do potencial nos dois
// regressores separa as hipóteses, e ela é a saída que decide o roteiro.
//
// Uso:
//   npm run tool -- reverse-dcf              # universo inteiro
//   npm run tool -- reverse-dcf PETR4 VALE3  # só estes
//   npm run tool -- reverse-dcf --limit 20   # os 20 primeiros
import {
  CapitalSeries,
  CapmInputs,
  compareNum,
  compareStr,
  DateTime,
  intDiv,
  MarketAnchors,
  PointInTimeView,
  PrepareValuationInputs,
  ResolveMarketAnchors,
  tryParseInt,
  ValuationCascade,
  ValuationInputs,
  ValuationLane,
  ValuationModel,
  ValuationParameters,
} from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';
import { Regression } from './validation/regression';

/** Data de referência. Fixa, para que a reexecução reproduza o relatório. */
const today = DateTime.local(2026, 9, 4);

/**
 * Grade do retorno terminal, log-espaçada entre 0,5% e 200% ao ano.
 *
 * Log e não linear porque a grandeza é um retorno sobre capital: a diferença
 * entre 8% e 10% importa, entre 150% e 152% não.
 */
function gridRonic(): number[] {
  const n = 61;
  const lo = 0.005;
  const hi = 2.0;
  const step = (Math.log(hi) - Math.log(lo)) / (n - 1);
  return Array.from({ length: n }, (_, i) => Math.exp(Math.log(lo) + step * i));
}

/** Grade do prêmio de risco, de 0 a 25% em passos de 0,5 p.p. */
const premiumGrid = (): number[] => Array.from({ length: 51 }, (_, i) => i * 0.005);

/**
 * Grade do deslocamento paralelo da taxa livre de risco, de −13 a +5 p.p.
 *
 * **Por que este eixo existe, e por que ele é o decisivo.** O prêmio de risco
 * não é o piso do desconto: `CostOfCapital.wacc` não deixa o WACC cair abaixo
 * da própria taxa livre de risco. Zerar o prêmio leva o desconto ao CDI e
 * para ali — de modo que uma varredura só no prêmio não consegue distinguir
 * "o prêmio está alto" de "a taxa livre de risco está alta". Deslocar as
 * duas taxas juntas, a corrente e a de equilíbrio, é o que mede o nível do
 * custo de capital sem esbarrar naquele piso.
 *
 * O limite inferior chega perto de zerar a taxa de equilíbrio de 9,40%: é
 * deliberadamente absurdo, porque o interesse é saber **se existe** taxa que
 * alcance o preço, e não propor uma.
 */
const gridRf = (): number[] => Array.from({ length: 73 }, (_, i) => -0.13 + i * 0.0025);

/** Resultado de uma varredura em um eixo. */
class Sweep {
  constructor(
    /** Valor que iguala preço justo a preço de mercado. `null` sem raiz única. */
    readonly implied: number | null,
    /** Como o preço justo se comporta ao longo da grade. */
    readonly monotonicity: string,
    /** Quantas vezes `justo − preço` troca de sinal na grade. */
    readonly crossings: number,
    /** Preço justo na ponta inferior e na superior da grade. */
    readonly fairValueMin: number | null,
    readonly fairValueMax: number | null,
    /** Pontos da grade em que a cascata não devolveu avaliação. */
    readonly failures: number,
    /**
     * Por que não houve raiz, quando não houve.
     *
     * A distinção importa mais que a raiz: `fora da grade — preço acima do
     * teto` diz que **nem retorno terminal infinito** alcança o preço, e nesse
     * ativo o terminal está descartado como explicação do vão. `já acima do
     * preço` é o oposto — o eixo não precisa se mover.
     */
    readonly situation: string,
  ) {}

  toJson(): SweepJson {
    return {
      implicito: this.implied,
      monotonia: this.monotonicity,
      cruzamentos: this.crossings,
      justoMin: this.fairValueMin,
      justoMax: this.fairValueMax,
      falhas: this.failures,
      situacao: this.situation,
    };
  }
}

interface SweepJson {
  implicito: number | null;
  monotonia: string;
  cruzamentos: number;
  justoMin: number | null;
  justoMax: number | null;
  falhas: number;
  situacao: string;
}

/** Classifica uma varredura sem raiz pela posição da grade contra o preço. */
function situationOf(fairValueMin: number | null, fairValueMax: number | null, price: number, crossCount: number): string {
  if (fairValueMin === null || fairValueMax === null) return 'sem avaliação';
  if (crossCount === 1) return 'raiz única';
  if (crossCount > 1) return 'múltiplas raízes';
  const greater = fairValueMin > fairValueMax ? fairValueMin : fairValueMax;
  const smaller = fairValueMin > fairValueMax ? fairValueMax : fairValueMin;
  if (greater < price) return 'fora da grade — preço acima do teto';
  if (smaller > price) return 'fora da grade — justo acima do preço em toda a grade';
  return 'sem cruzamento';
}

/** Avalia e devolve o preço justo, ou `null` quando a cascata recusa. */
function fairValueOf(inputs: ValuationInputs): number | null {
  const r = ValuationCascade.evaluate(inputs);
  return r.isOk ? r.unwrap().fairValue.reais : null;
}

/**
 * Varre um eixo pela grade, classifica a monotonia e refina a raiz.
 *
 * - [grid]: valores a percorrer, em ordem crescente.
 * - [buildInputs]: constrói os insumos para um valor da grade.
 * - [price]: preço de mercado, o alvo da igualdade.
 */
function sweep(args: { grid: readonly number[]; buildInputs: (x: number) => ValuationInputs; price: number }): Sweep {
  const { grid, buildInputs, price } = args;
  const xs: number[] = [];
  const fs: number[] = [];
  let failures = 0;
  for (const x of grid) {
    const j = fairValueOf(buildInputs(x));
    if (j === null || !Number.isFinite(j)) {
      failures++;
      continue;
    }
    xs.push(x);
    fs.push(j - price);
  }
  if (xs.length < 3) return new Sweep(null, 'sem avaliação', 0, null, null, failures, 'sem avaliação');

  // Monotonia medida, com tolerância relativa ao preço: variação abaixo de
  // 0,1% do preço é ruído de ponto flutuante, não direção.
  const tol = price * 1e-3;
  let rises = false;
  let falls = false;
  for (let i = 1; i < fs.length; i++) {
    const d = fs[i]! - fs[i - 1]!;
    if (d > tol) rises = true;
    if (d < -tol) falls = true;
  }
  const monotonicity = rises && falls ? 'não monótona' : rises ? 'crescente' : falls ? 'decrescente' : 'plana';

  // Cruzamentos de zero.
  const brackets: [number, number][] = [];
  for (let i = 1; i < fs.length; i++) {
    // Ponto da grade que já iguala o preço dentro da tolerância. Exigir zero
    // cravado numa diferença entre dois valores monetários calculados nunca
    // dispararia, e a bissecção teria de reencontrar por dentro uma raiz que
    // está bem debaixo do ponto.
    if (Math.abs(fs[i - 1]!) < tol) return withRoot(xs[i - 1]!, monotonicity, 1, fs, price, failures);
    if (fs[i - 1]! < 0 !== fs[i]! < 0) brackets.push([i - 1, i]);
  }
  const first = fs[0]! + price;
  const last = fs[fs.length - 1]! + price;
  if (brackets.length !== 1) {
    return new Sweep(null, monotonicity, brackets.length, first, last, failures, situationOf(first, last, price, brackets.length));
  }

  // Bissecção dentro do único intervalo que muda de sinal.
  let lo = xs[brackets[0]![0]]!;
  let hi = xs[brackets[0]![1]]!;
  let flo = fs[brackets[0]![0]]!;
  for (let it = 0; it < 60; it++) {
    const mid = (lo + hi) / 2;
    const j = fairValueOf(buildInputs(mid));
    if (j === null || !Number.isFinite(j)) break;
    const f = j - price;
    if (f < 0 === flo < 0) {
      lo = mid;
      flo = f;
    } else {
      hi = mid;
    }
    if (Math.abs(hi - lo) < 1e-9) break;
  }
  return withRoot((lo + hi) / 2, monotonicity, 1, fs, price, failures);
}

function withRoot(root: number, monotonicity: string, crossings: number, fs: readonly number[], price: number, failures: number): Sweep {
  return new Sweep(root, monotonicity, crossings, fs[0]! + price, fs[fs.length - 1]! + price, failures, 'raiz única');
}

/** Reconstrói os insumos trocando apenas o retorno terminal. */
const withRonic = (b: ValuationInputs, ronic: number): ValuationInputs =>
  new ValuationInputs({
    ticker: b.ticker,
    asOf: b.asOf,
    fundamentals: b.fundamentals,
    marketPrice: b.marketPrice,
    capm: b.capm,
    marginOfSafety: b.marginOfSafety,
    projectionYears: b.projectionYears,
    perpetualGrowthCap: b.perpetualGrowthCap,
    sectorKey: b.sectorKey,
    industry: b.industry,
    inflation: b.inflation,
    declaredTerminalRiskFreeRate: b.declaredTerminalRiskFreeRate,
    prices: b.prices,
    isDistressed: b.isDistressed,
    terminalReturnOverride: ronic,
  });

/**
 * Reconstrói os insumos trocando apenas o prêmio de risco de mercado.
 *
 * O prêmio viaja no `capm`, e `CapmInputs.withRiskFree` o preserva — de modo
 * que trocar aqui desloca **as duas** taxas, a corrente e a de equilíbrio, o
 * que é a definição de um deslocamento paralelo do custo de capital.
 */
const withPremium = (b: ValuationInputs, premium: number): ValuationInputs =>
  new ValuationInputs({
    ticker: b.ticker,
    asOf: b.asOf,
    fundamentals: b.fundamentals,
    marketPrice: b.marketPrice,
    capm: new CapmInputs({
      riskFreeRate: b.capm.riskFreeRate,
      beta: b.capm.beta,
      marketPremium: premium,
      betaSource: b.capm.betaSource,
      premiumSource: b.capm.premiumSource,
    }),
    marginOfSafety: b.marginOfSafety,
    projectionYears: b.projectionYears,
    perpetualGrowthCap: b.perpetualGrowthCap,
    sectorKey: b.sectorKey,
    industry: b.industry,
    inflation: b.inflation,
    declaredTerminalRiskFreeRate: b.declaredTerminalRiskFreeRate,
    prices: b.prices,
    isDistressed: b.isDistressed,
  });

/**
 * Reconstrói os insumos deslocando **as duas** taxas livres de risco.
 *
 * A corrente e a de equilíbrio andam juntas: o interesse é o nível da curva,
 * e mover só uma delas mudaria a inclinação da estrutura a termo, que é outra
 * pergunta. O piso de 0,1% evita taxa negativa, que não tem leitura aqui.
 */
function withRf(b: ValuationInputs, shift: number): ValuationInputs {
  const floor = (x: number): number => (x < 0.001 ? 0.001 : x);
  return new ValuationInputs({
    ticker: b.ticker,
    asOf: b.asOf,
    fundamentals: b.fundamentals,
    marketPrice: b.marketPrice,
    capm: b.capm.withRiskFree(floor(b.capm.riskFreeRate + shift)),
    marginOfSafety: b.marginOfSafety,
    projectionYears: b.projectionYears,
    perpetualGrowthCap: b.perpetualGrowthCap,
    sectorKey: b.sectorKey,
    industry: b.industry,
    inflation: b.inflation,
    declaredTerminalRiskFreeRate: floor(b.terminalRiskFreeRate + shift),
    prices: b.prices,
    isDistressed: b.isDistressed,
  });
}

interface RefusedRow {
  ticker: string;
  avaliado: false;
  recusa: string | null;
}

interface EvaluatedRow {
  ticker: string;
  avaliado: true;
  setor: string | null;
  preco: number;
  justo: number;
  potencial: number;
  via: string;
  modelo: string;
  desconto: number;
  pesoTerminal: number | null;
  participacaoEquity: number | null;
  fatorBase: number | null;
  moat: boolean | null;
  beta: number;
  betaOrigem: string;
  premioBase: number;
  rf: number;
  rfTerminal: number;
  retornoCiclo: number | null;
  excedente: number | null;
  ronicImplicito: SweepJson;
  premioImplicito: SweepJson;
  rfImplicito: SweepJson;
  keImplicito: number | null;
  rfTerminalImplicito: number | null;
  multiplicadorFluxo: number | null;
}

type Row = RefusedRow | EvaluatedRow;

type Axis = 'ronicImplicito' | 'premioImplicito' | 'rfImplicito';

export async function main(args: string[]): Promise<void> {
  const limitIndex = args.indexOf('--limit');
  const limit = limitIndex >= 0 ? (tryParseInt(args[limitIndex + 1] ?? '') ?? 0) : 0;
  const targets = args.filter((a) => !a.startsWith('--') && tryParseInt(a) === null);

  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark, asOf: today })).getOrElse(
      MarketAnchors.fallback2026,
    );

    errln(
      `âncoras: rf=${anchors.currentRiskFreeRate.toFixed(4)} rfTerm=${anchors.riskFreeCagr.toFixed(4)} ` +
        `gNom=${anchors.nominalEconomyGrowth.toFixed(4)}`,
    );

    let universe = (await ctx.fundamentals.universe()).unwrap();
    if (targets.length > 0) universe = universe.filter((t) => targets.includes(t.value));
    if (limit > 0 && universe.length > limit) universe = universe.slice(0, limit);
    errln(`universo: ${universe.length} ativos`);

    const ronicGrid = gridRonic();
    const premiums = premiumGrid();
    const rfShifts = gridRf();

    const output: Row[] = [];
    const started = Date.now();
    const elapsedSeconds = (): number => Math.floor((Date.now() - started) / 1000);
    let i = 0;
    for (const ticker of universe) {
      i++;
      if (i % 10 === 0) process.stderr.write(`  ${i}/${universe.length} (${elapsedSeconds()}s)      \r`);

      const prep = await PrepareValuationInputs.call({
        ticker,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        projectionYears: 10,
      });
      if (prep.isErr) {
        output.push({ ticker: ticker.value, avaliado: false, recusa: prep.failureOrNull?.message ?? null });
        continue;
      }
      const inputs = prep.unwrap();
      const baseResult = ValuationCascade.evaluate(inputs);
      if (baseResult.isErr) {
        output.push({ ticker: ticker.value, avaliado: false, recusa: baseResult.failureOrNull?.message ?? null });
        continue;
      }
      const base = baseResult.unwrap();
      const price = inputs.marketPrice;

      // Retorno do ciclo na via que a cascata efetivamente escolheu: comparar
      // ROIC com WACC numa e ROE com Ke na outra é a única comparação em que
      // o excedente significa a mesma coisa.
      const lane = base.model === ValuationModel.dcfFcff ? ValuationLane.firm : ValuationLane.shareholder;
      const pub = new PointInTimeView(inputs.asOf).published(inputs.fundamentals);
      const series = CapitalSeries.build(pub, lane);
      const cycleReturn = series.cycleReturn({ window: ValuationParameters.cycleWindow });

      const ronic = sweep({ grid: ronicGrid, buildInputs: (x) => withRonic(inputs, x), price });
      const premium = sweep({ grid: premiums, buildInputs: (x) => withPremium(inputs, x), price });
      const rf = sweep({ grid: rfShifts, buildInputs: (x) => withRf(inputs, x), price });

      // Quarto eixo, e este sai por identidade em vez de varredura: o DCF é
      // homogêneo de grau 1 no fluxo-base, então multiplicar o fluxo por `k`
      // multiplica o valor da firma por `k`. Na via do acionista o valor é o
      // próprio preço justo e o fator necessário é `preço ÷ justo`; na via da
      // firma a dívida líquida não escala junto, e o fator sai da ponte:
      //
      //   EV = E + D,  E = justo·N  =>  D por papel = justo·(1 − s)/s
      //   k = (preço + D/N) ÷ (justo + D/N)
      //
      // Varrer seria mais caro e devolveria o mesmo número.
      const s = base.diagnostics?.equityShare ?? null;
      const fairValue = base.fairValue.reais;
      let multiplier: number | null = null;
      if (fairValue > 0) {
        if (lane === ValuationLane.firm && s !== null && s > 0 && s <= 1) {
          const debtPerShare = (fairValue * (1 - s)) / s;
          multiplier = (price + debtPerShare) / (fairValue + debtPerShare);
        } else {
          multiplier = price / fairValue;
        }
      }

      const impliedKe = premium.implied === null ? null : inputs.capm.riskFreeRate + inputs.capm.beta * premium.implied;
      const impliedTerminalRf = rf.implied === null ? null : inputs.terminalRiskFreeRate + rf.implied;

      output.push({
        ticker: ticker.value,
        avaliado: true,
        setor: inputs.sectorKey,
        preco: price,
        justo: base.fairValue.reais,
        potencial: base.upside,
        via: lane.name,
        modelo: base.model.name,
        desconto: base.discountRate,
        pesoTerminal: base.diagnostics?.terminalShare ?? null,
        participacaoEquity: base.diagnostics?.equityShare ?? null,
        fatorBase: base.diagnostics?.baseFactor ?? null,
        moat: base.diagnostics?.moatApplied ?? null,
        beta: inputs.capm.beta,
        betaOrigem: inputs.capm.betaSource.name,
        premioBase: inputs.capm.marketPremium,
        rf: inputs.capm.riskFreeRate,
        rfTerminal: inputs.terminalRiskFreeRate,
        retornoCiclo: cycleReturn,
        excedente: cycleReturn === null ? null : cycleReturn - base.discountRate,
        ronicImplicito: ronic.toJson(),
        premioImplicito: premium.toJson(),
        rfImplicito: rf.toJson(),
        keImplicito: impliedKe,
        rfTerminalImplicito: impliedTerminalRf,
        multiplicadorFluxo: multiplier,
      });
    }
    errln(`\nvarredura em ${elapsedSeconds()}s`);

    const identification = identify(output);

    writeText('docs/validacao/dcf_reverso.json', jsonPretty({ ativos: output, identificacao: identification }, ' '));
    errln(`escrito docs/validacao/dcf_reverso.json (${output.filter((e) => e.avaliado).length} avaliados)`);
    printReport(output, identification);
  } finally {
    await ctx.dispose();
  }
}

interface Identification {
  n: number;
  erro?: string;
  spearmanPotencialExcedente?: number | null;
  spearmanPotencialBeta?: number | null;
  spearmanExcedenteBeta?: number | null;
  conjunta?: { coefExcedente: number; tExcedente: number; coefBeta: number; tBeta: number; r2: number } | null;
  soExcedente?: { coef: number; t: number; r2: number } | null;
  soBeta?: { coef: number; t: number; r2: number } | null;
}

/**
 * O teste que separa as duas hipóteses de viés de nível.
 *
 * Erro de **terminal** escala com o excedente `retorno do ciclo − desconto`:
 * a empresa com franquia é a que o estado estacionário mais castiga. Erro de
 * **taxa** escala com beta, e é indiferente ao excedente. Regredir o
 * potencial nos dois de uma vez é o que impede que a correlação de um seja
 * lida como evidência do outro.
 */
function identify(rows: readonly Row[]): Identification {
  const ok = rows.filter((e): e is EvaluatedRow => e.avaliado && e.excedente !== null);
  if (ok.length < 20) return { n: ok.length, erro: 'amostra insuficiente' };

  const upsides = ok.map((e) => e.potencial);
  const exc = ok.map((e) => e.excedente!);
  const bet = ok.map((e) => e.beta);

  // Postos padronizados: o potencial tem cauda pesada (a QUAL3 sozinha chega a
  // +477%), e regressão de nível sobre ele mede o extremo, não a relação.
  const zUpside = Regression.standardizedRanks(upsides);
  const zExc = Regression.standardizedRanks(exc);
  const zBet = Regression.standardizedRanks(bet);

  const joint = Regression.ols([zExc, zBet], zUpside);
  const onlyExc = Regression.ols([zExc], zUpside);
  const onlyBet = Regression.ols([zBet], zUpside);

  return {
    n: ok.length,
    spearmanPotencialExcedente: Regression.spearman(upsides, exc),
    spearmanPotencialBeta: Regression.spearman(upsides, bet),
    spearmanExcedenteBeta: Regression.spearman(exc, bet),
    conjunta:
      joint === null
        ? null
        : {
            coefExcedente: joint.coefficients[1]!,
            tExcedente: joint.tStats[1]!,
            coefBeta: joint.coefficients[2]!,
            tBeta: joint.tStats[2]!,
            r2: joint.r2,
          },
    soExcedente: onlyExc === null ? null : { coef: onlyExc.coefficients[1]!, t: onlyExc.tStats[1]!, r2: onlyExc.r2 },
    soBeta: onlyBet === null ? null : { coef: onlyBet.coefficients[1]!, t: onlyBet.tStats[1]!, r2: onlyBet.r2 },
  };
}

function printReport(rows: readonly Row[], ident: Identification): void {
  const ok = rows.filter((e): e is EvaluatedRow => e.avaliado);
  if (ok.length === 0) {
    outln('nenhum ativo avaliado');
    return;
  }

  const med = (v: Iterable<number>): number | null => {
    const s = [...v].sort(compareNum);
    if (s.length === 0) return null;
    const m = Math.floor(s.length / 2);
    return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
  };

  const pc = (x: number | null): string => (x === null ? '—' : `${(x * 100).toFixed(1)}%`);

  outln(`\n=== DCF REVERSO — ${ok.length} avaliados ===\n`);

  const upsides = ok.map((e) => e.potencial);
  outln(`potencial mediano: ${pc(med(upsides))}   positivos: ${upsides.filter((p) => p > 0).length}`);

  // --- Eixo do retorno terminal ---
  const withRonicRoot = ok.filter((e) => e.ronicImplicito.implicito !== null);
  const situations = (axis: Axis): void => {
    const account = new Map<string, number>();
    for (const e of ok) {
      const s = e[axis].situacao;
      account.set(s, (account.get(s) ?? 0) + 1);
    }
    const sortedEntries = [...account.entries()].sort((a, b) => compareNum(b[1], a[1]));
    for (const [k, v] of sortedEntries) outln(`  ${String(v).padStart(4)}  ${k}`);
  };

  outln('\n-- RONIC_infinito implícito --');
  situations('ronicImplicito');
  const nonMonotonic = ok.filter((e) => e.ronicImplicito.monotonia === 'não monótona').length;
  const flatOnes = ok.filter((e) => e.ronicImplicito.monotonia === 'plana').length;
  outln(`não monótonos: ${nonMonotonic}   planos (terminal insensível): ${flatOnes}`);
  if (withRonicRoot.length > 0) {
    const r = withRonicRoot.map((e) => e.ronicImplicito.implicito!);
    outln(`mediana do RONIC implícito: ${pc(med(r))}`);
    const withCycle = withRonicRoot.filter((e) => e.retornoCiclo !== null).map((e) => e.ronicImplicito.implicito! / e.retornoCiclo!);
    const cycleMedian = med(withCycle);
    outln(`mediana de RONIC implícito ÷ ROIC do ciclo: ${cycleMedian === null ? '—' : cycleMedian.toFixed(2)}x`);
    const above = withCycle.filter((x) => x > 1).length;
    outln(`acima do ciclo: ${above} de ${withCycle.length}`);
  }

  // --- Eixo do prêmio ---
  const withPremiumRoot = ok.filter((e) => e.premioImplicito.implicito !== null);
  outln('\n-- prêmio de risco implícito --');
  situations('premioImplicito');
  if (withPremiumRoot.length > 0) {
    const p = withPremiumRoot.map((e) => e.premioImplicito.implicito!);
    outln(`mediana do prêmio implícito: ${pc(med(p))} (parametrizado: 5,5%)`);
    const ke = withPremiumRoot.map((e) => e.keImplicito).filter((x): x is number => x !== null);
    outln(`mediana do Ke implícito: ${pc(med(ke))}`);
    const zero = p.filter((x) => x <= 0.0001).length;
    outln(`no piso da grade (prêmio nulo não basta): ${zero}`);
  }

  // --- Eixo do nível da taxa livre de risco ---
  const withRfRoot = ok.filter((e) => e.rfImplicito.implicito !== null);
  outln('\n-- deslocamento da taxa livre de risco --');
  situations('rfImplicito');
  if (withRfRoot.length > 0) {
    const d = withRfRoot.map((e) => e.rfImplicito.implicito!);
    outln(`mediana do deslocamento: ${pc(med(d))} (negativo = a curva teria de ser mais baixa)`);
    const rt = withRfRoot.map((e) => e.rfTerminalImplicito).filter((x): x is number => x !== null);
    outln(`mediana da taxa de equilíbrio implícita: ${pc(med(rt))} (medida: 9,4%)`);
  }

  // --- Eixo do fluxo-base ---
  const mult = ok
    .map((e) => e.multiplicadorFluxo)
    .filter((x): x is number => x !== null)
    .sort(compareNum);
  const factors = ok.map((e) => e.fatorBase).filter((x): x is number => x !== null);
  outln('\n-- fluxo-base --');
  if (mult.length > 0) {
    outln(
      `multiplicador necessário para igualar o preço: p25=${mult[intDiv(mult.length, 4)]!.toFixed(2)}x  ` +
        `mediana=${med(mult)!.toFixed(2)}x  p75=${mult[intDiv(3 * mult.length, 4)]!.toFixed(2)}x`,
    );
    outln(`acima de 1: ${mult.filter((x) => x > 1).length} de ${mult.length}`);
  }
  if (factors.length > 0) {
    outln(
      `fator de normalização APLICADO: mediana=${med(factors)!.toFixed(2)}x  ` +
        `abaixo de 1: ${factors.filter((x) => x < 0.999).length} de ${factors.length}`,
    );
  }
  outln(`desconto corrente mediano: ${pc(med(ok.map((e) => e.desconto)))}`);

  // --- O cruzamento dos eixos ---
  //
  // Duas perguntas diferentes, e confundi-las produz número errado:
  // *resolver* é ter raiz única; *ser inatingível* é o preço ficar fora do
  // alcance da grade inteira. "Múltiplas raízes" não é nenhuma das duas — o
  // eixo alcança o preço, mas não devolve um valor. A assimetria só significa
  // alguma coisa medida contra o inatingível.
  const resolves = (e: EvaluatedRow, axis: Axis): boolean => e[axis].implicito !== null;
  const unreachable = (e: EvaluatedRow, axis: Axis): boolean => e[axis].situacao.includes('acima do teto');

  const rateResolvesButTerminalNot = ok.filter((e) => resolves(e, 'rfImplicito') && unreachable(e, 'ronicImplicito')).length;
  const terminalResolvesButRateNot = ok.filter((e) => resolves(e, 'ronicImplicito') && unreachable(e, 'rfImplicito')).length;
  const inAllThree = ok.filter(
    (e) => unreachable(e, 'ronicImplicito') && unreachable(e, 'premioImplicito') && unreachable(e, 'rfImplicito'),
  );

  outln('\n-- cruzamento dos eixos --');
  outln(`  a TAXA resolve e o TERMINAL é inatingível: ${rateResolvesButTerminalNot}`);
  outln(`  o TERMINAL resolve e a TAXA é inatingível: ${terminalResolvesButRateNot}`);
  outln(`  inatingível nos TRÊS eixos:                ${inAllThree.length} de ${ok.length}`);
  if (inAllThree.length > 0) {
    const names = inAllThree.map((e) => e.ticker).sort(compareStr);
    outln(`    ${names.join(', ')}`);
  }

  // --- Identificação ---
  outln(`\n-- identificação (postos padronizados, n=${ident.n}) --`);
  const c = ident.conjunta ?? null;
  if (c !== null) {
    outln('potencial ~ excedente + beta');
    outln(`  excedente: coef=${c.coefExcedente.toFixed(3)} t=${c.tExcedente.toFixed(2)}`);
    outln(`  beta:      coef=${c.coefBeta.toFixed(3)} t=${c.tBeta.toFixed(2)}`);
    outln(`  R²=${c.r2.toFixed(3)}`);
  }
  const rho = (v: number | null | undefined): string => (v === null || v === undefined ? '—' : v.toFixed(3));
  outln(`Spearman potencial×excedente: ${rho(ident.spearmanPotencialExcedente)}`);
  outln(`Spearman potencial×beta:      ${rho(ident.spearmanPotencialBeta)}`);
}
