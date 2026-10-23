// Item B3 — o prêmio de risco de mercado deixa de ser parâmetro.
//
// **A pergunta.** O prêmio é 5,5% fixo, ponto médio de uma faixa de 5–6%
// adotada por convenção. As alternativas que o item nomeia são duas: histórico
// com encolhimento, ou **implícito** — o prêmio que faz o próprio modelo
// concordar com o preço de mercado.
//
// **O que esta ferramenta mede.**
//
//   1. **O histórico**, do Ibovespa contra o CDI na janela que a entrada
//      congelada tem, com o erro-padrão ao lado — porque um prêmio de risco
//      estimado em dez anos é ruído, e o número sem a barra engana.
//   2. **O implícito**, por varredura: o prêmio que zera o potencial **mediano**
//      do universo. É o prêmio que o motor teria de usar para dizer que a ação
//      mediana está no preço.
//
//      A mediana, e não o agregado ponderado pelo valor de mercado: ponderar
//      exigiria a contagem de papéis de cada ativo, que é justamente a grandeza
//      que a ponte arbitra (decisão 83), e o resultado passaria a depender dela.
//      A mediana do potencial é a mesma grandeza que a §0 do plano usa.
//   3. **O efeito de cada candidato** sobre preço justo, cobertura e ordenação.
//
//   npm run tool -- cascade-golden   # congela a entrada
//   npm run tool -- market-premium   # grava premio_de_mercado.json
import { compareStr, StateError, str, type Ticker, ValuationCascade, type ValuationResult } from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { truncatedMedian as median } from './lib/stats';
import { Frozen } from './validation/frozen';
import { Regression } from './validation/regression';

/**
 * A faixa varrida desce a **−6%** de propósito: um prêmio negativo é absurdo
 * econômico — o acionista exigindo menos que o CDI —, e é justamente por isso
 * que interessa saber se o implícito cai lá. Se cair, o desacordo entre motor
 * e mercado não é do prêmio.
 */
const premiums = [-0.06, -0.05, -0.04, -0.03, -0.02, -0.01, 0.0, 0.01, 0.02, 0.03, 0.04, 0.045, 0.05, 0.055, 0.06, 0.07, 0.08, 0.1];

/**
 * Posição de [premiums] que serve de referência — o 5,5% de hoje.
 *
 * **Posição, e não valor**: número de ponto flutuante não serve de chave de
 * mapa nem de critério de igualdade (regra R6). E é constante declarada, e não
 * `indexOf(0.055)`: procurar um número numa lista compara por `===` por
 * dentro, que é a mesma regra por outro nome. [checkReference] impede que a
 * posição e a lista se desencontrem.
 */
const referenceIndex = 13;

/** O prêmio de referência, para exibição. */
const reference = premiums[referenceIndex]!;

/** Falha cedo se alguém mexer em [premiums] sem mexer em [referenceIndex]. */
function checkReference(): void {
  if (Math.abs(reference - 0.055) > 1e-9) {
    throw new StateError(`referenceIndex aponta para ${str(reference)}, e não para o prêmio de 5,5% que a montagem do gabarito usa.`);
  }
}

const output = 'docs/validacao/premio_de_mercado.json';

/**
 * Diferença de potencial abaixo da qual dois degraus da varredura são o mesmo
 * número, e a interpolação entre eles não tem o que interpolar.
 *
 * Um centésimo de ponto percentual de potencial: a varredura anda de 1 p.p.
 * em prêmio e move o potencial em pontos inteiros, de modo que qualquer coisa
 * abaixo disso é ruído de arredondamento, e não inclinação.
 */
const plateau = 1e-4;

class Reading {
  readonly fairValueCents = new Map<string, number>();
  readonly upside = new Map<string, number>();
}

interface Row {
  premio: number;
  avaliados: number;
  potencialMediano: number | null;
  acimaDeZero: number;
  precoJustoMedianoVsReferencia: number;
  spearmanContraReferencia: number | null;
}

export async function main(_args: string[]): Promise<void> {
  checkReference();
  const c = await Frozen.build();
  try {
    // ---------------------------------------------------------------------
    // 1) O histórico, com a barra de erro
    // ---------------------------------------------------------------------
    const indexResult = await c.ctx.benchmark.ibovespa(c.betaWindow);
    if (indexResult.isErr) {
      errln(`sem índice: ${indexResult.failureOrNull?.message ?? null}`);
      process.exitCode = 2;
      return;
    }
    const points = indexResult.unwrap().points;
    const first = points[0]!;
    const last = points[points.length - 1]!;
    const years = last.date.difference(first.date).inDays / 365.25;
    const indexCagr = Math.pow(last.close / first.close, 1 / years) - 1.0;
    const cdi = c.anchors.riskFreeCagr;
    // Fisher, e não subtração: o prêmio é razão de fatores brutos.
    const historicalPremium = (1 + indexCagr) / (1 + cdi) - 1;

    // Volatilidade anualizada dos retornos diários do índice. O erro-padrão da
    // média de um prêmio é `σ ÷ √T`, com `T` em anos — é a conta que mostra
    // por que dez anos não estimam prêmio de risco.
    const returns: number[] = [];
    for (let i = 1; i < points.length; i++) returns.push(points[i]!.close / points[i - 1]!.close - 1);
    // Série de um pregão só não tem variância amostral, e `n − 1` daria zero
    // no denominador: o `NaN` se propagaria calado até o intervalo de 95%.
    if (returns.length < 2) {
      errln('índice com menos de dois pregões: sem variância amostral, e sem erro-padrão a declarar.');
      process.exitCode = 2;
      return;
    }
    const mean = returns.reduce((a, b) => a + b) / returns.length;
    const variance = returns.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) / (returns.length - 1);
    const dailyVol = Math.sqrt(variance);
    const annualVol = dailyVol * Math.sqrt(252.0);
    const standardError = annualVol / Math.sqrt(years);

    outln('-- o prêmio histórico, na janela da entrada congelada --');
    outln(`  janela                     ${years.toFixed(2)} anos (${points.length} pregões)`);
    outln(`  Ibovespa, CAGR             ${pct(indexCagr)}`);
    outln(`  CDI, CAGR                  ${pct(cdi)}`);
    outln(`  prêmio (Fisher)            ${pct(historicalPremium)}`);
    outln(`  volatilidade anual         ${pct(annualVol)}`);
    outln(`  erro-padrão do prêmio      ${pct(standardError)}`);
    outln(`  intervalo de 95%           ${pct(historicalPremium - 1.96 * standardError)} a ${pct(historicalPremium + 1.96 * standardError)}`);
    outln(`  anos para erro de 1 p.p.   ${((annualVol * annualVol) / 0.0001).toFixed(0)}`);

    // **O encolhimento é a segunda saída que o item B3 nomeia**, e ela se
    // resolve sozinha: o peso do estimador amostral é `τ² ÷ (τ² + σ²)`, e com
    // um erro-padrão de quase 8 p.p. contra uma faixa a priori de meio ponto,
    // esse peso é de alguns por cento. **O encolhimento devolve o parâmetro.**
    outln('');
    outln('-- o encolhimento do histórico para a faixa declarada --');
    const shrunkList: { tau: number; peso: number; premio: number }[] = [];
    for (const tau of [0.0025, 0.005, 0.01, 0.02]) {
      const weight = (tau * tau) / (tau * tau + standardError * standardError);
      const shrunk = weight * historicalPremium + (1 - weight) * reference;
      outln(`  τ = ${pct(tau)}   peso da amostra ${(weight * 100).toFixed(2).padStart(5)}%   prêmio encolhido ${pct(shrunk)}`);
      shrunkList.push({ tau, peso: weight, premio: shrunk });
    }

    // ---------------------------------------------------------------------
    // 2) A varredura do prêmio sobre o universo
    // ---------------------------------------------------------------------
    const readings = new Map<number, Reading>();
    for (let premiumIndex = 0; premiumIndex < premiums.length; premiumIndex++) {
      const premium = premiums[premiumIndex]!;
      const l = new Reading();
      const evaluated = new Map<Ticker, ValuationResult | null>();
      let i = 0;
      for (const t of c.universe) {
        i++;
        if (i % 50 === 0) process.stderr.write(`  prêmio ${pct(premium)}: ${i}/${c.universe.length}   \r`);
        const prep = await c.prepare(t, { premium });
        if (prep.isErr) continue;
        const r = ValuationCascade.evaluate(prep.unwrap());
        if (premiumIndex === referenceIndex) evaluated.set(t, r.valueOrNull);
        if (r.isErr) continue;
        const v = r.unwrap();
        l.fairValueCents.set(t.value, v.fairValue.cents);
        l.upside.set(t.value, v.upside);
      }
      readings.set(premiumIndex, l);

      if (premiumIndex === referenceIndex) {
        const mismatches = await c.checkAgainstAnswerKey(evaluated);
        if (mismatches === null) {
          errln('AVISO: gabarito ausente; montagem não conferida.');
        } else if (mismatches.length > 0) {
          errln(`ERRO: a montagem de referência diverge do gabarito em ${mismatches.length}: ${mismatches.slice(0, 8).join(', ')}`);
          process.exitCode = 1;
          return;
        } else {
          outln('');
          outln(`montagem de ${pct(reference)} conferida contra o gabarito: zero divergências.`);
        }
      }
    }
    process.stderr.write('                                        \r');

    const base = readings.get(referenceIndex)!;
    const rows: Row[] = [];

    outln('');
    outln('-- a varredura do prêmio, sobre a entrada congelada --');
    outln('  prêmio  avaliados   potencial mediano   acima de zero   preço justo vs 5,5%   postos');

    for (let premiumIndex = 0; premiumIndex < premiums.length; premiumIndex++) {
      const premium = premiums[premiumIndex]!;
      const l = readings.get(premiumIndex)!;
      const upsideValues = [...l.upside.values()];
      const medianUpside = median(upsideValues);
      const above = upsideValues.filter((p) => p > 0).length;

      const common = [...l.fairValueCents.keys()].filter((k) => base.fairValueCents.has(k)).sort(compareStr);
      const changeList = common
        .filter((k) => base.fairValueCents.get(k)! !== 0)
        .map((k) => l.fairValueCents.get(k)! / base.fairValueCents.get(k)! - 1);
      const rho =
        common.length < 3
          ? null
          : Regression.spearman(
              common.map((k) => base.upside.get(k)!),
              common.map((k) => l.upside.get(k)!),
            );

      outln(
        `  ${pct(premium)}  ${String(l.fairValueCents.size).padStart(9)}   ${pct(medianUpside).padStart(16)}   ` +
          `${String(above).padStart(9)} de ${upsideValues.length}   ${pct(median(changeList)).padStart(17)}   ` +
          (rho === null ? '  —   ' : rho.toFixed(4)),
      );

      rows.push({
        premio: premium,
        avaliados: l.fairValueCents.size,
        potencialMediano: Number.isFinite(medianUpside) ? medianUpside : null,
        acimaDeZero: above,
        precoJustoMedianoVsReferencia: median(changeList),
        spearmanContraReferencia: rho,
      });
    }

    // ---------------------------------------------------------------------
    // 3) O implícito: onde o agregado cruza zero
    // ---------------------------------------------------------------------
    let implied: number | null = null;
    for (let i = 1; i < rows.length; i++) {
      const a = rows[i - 1]!.potencialMediano;
      const b = rows[i]!.potencialMediano;
      if (a === null || b === null) continue;
      if ((a >= 0 && b <= 0) || (a <= 0 && b >= 0)) {
        const premiumA = rows[i - 1]!.premio;
        const premiumB = rows[i]!.premio;
        // **A guarda é do denominador, e não da igualdade.** Dois potenciais
        // que deveriam ser iguais diferem por epsilon, e `a === b` passaria
        // reto para uma divisão por infinitésimo — o prêmio implícito sairia
        // absurdo sem que nada acusasse. Com o degrau da varredura em 1 p.p.,
        // uma diferença abaixo de `plateau` é platô, e ali o extremo
        // esquerdo é a leitura honesta.
        implied = Math.abs(b - a) < plateau ? premiumA : premiumA + ((premiumB - premiumA) * (0 - a)) / (b - a);
        break;
      }
    }

    outln('');
    if (implied === null) {
      outln(`  o potencial mediano NÃO cruza zero na faixa varrida (${pct(premiums[0]!)} a ${pct(premiums[premiums.length - 1]!)}).`);
    } else {
      outln(`  prêmio implícito (mediana do potencial em zero): ${pct(implied)}`);
    }

    writeText(
      output,
      jsonPretty(
        {
          historico: {
            anos: years,
            pregoes: points.length,
            cagrIbovespa: indexCagr,
            cagrCdi: cdi,
            premio: historicalPremium,
            volatilidadeAnual: annualVol,
            erroPadrao: standardError,
            ic95: [historicalPremium - 1.96 * standardError, historicalPremium + 1.96 * standardError],
          },
          encolhimento: shrunkList,
          referencia: reference,
          varredura: rows,
          premioImplicito: implied,
        },
        '  ',
      ),
    );
    outln('');
    outln(`escrito ${output}`);
  } finally {
    await c.ctx.dispose();
  }
}

const pct = (v: number): string => (Number.isNaN(v) ? '   —  ' : `${(v * 100).toFixed(2).padStart(6)}%`);
