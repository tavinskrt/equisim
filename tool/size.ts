// Item B4 — o ajuste por tamanho no custo de capital.
//
// **A pergunta.** O CAPM do motor é de fator único: não há prêmio por tamanho,
// e um pequeno e um grande de mesmo beta pagam o mesmo custo de capital. A
// literatura de fatores diz que pequenos rendem mais; a pergunta desta medição
// é se, **neste universo e neste motor**, o tamanho ainda carrega algo que o
// beta não carrega.
//
// **O que esta ferramenta mede.**
//
//   1. **Se o beta já cobra o tamanho**: a relação de postos entre valor de
//      mercado, beta, taxa de desconto e potencial no universo avaliado.
//   2. **O perfil por tercil de tamanho**: beta, desconto e potencial medianos.
//   3. **O efeito de um prêmio explícito** de 2 p.p. no tercil menor — sobre
//      nível, cobertura e ordenação.
//
// A medição **não** é de retorno realizado: isso é coorte, e depende da base
// bruta (item C5). É sobre o que o motor de hoje já cobra, e sobre o que um
// ajuste mudaria.
//
//   npm run tool -- cascade-golden   # congela a entrada
//   npm run tool -- size             # grava tamanho.json
import { compareNum, compareStr, intDiv, type Ticker, ValuationCascade, type ValuationResult } from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { truncatedMedian as median, truncatedQuantile as q } from './lib/stats';
import { Frozen } from './validation/frozen';
import { Regression } from './validation/regression';

const reference = 0.055;

/**
 * O prêmio a somar no tercil menor, na medição do efeito. Dois pontos é a
 * ordem de grandeza do prêmio por tamanho na literatura de fatores — e é
 * grande o bastante para que, se nada se mover aqui, nada se mova nunca.
 */
const sizePremium = 0.02;
const output = 'docs/validacao/tamanho.json';

interface SizedAsset {
  ticker: string;
  marketValueOf: number;
  beta: number;
  discount: number;
  upside: number;
  fairValueCents: number;
}

const f = (v: number | null): string => (v === null ? '—' : v.toFixed(4));
const pct = (v: number): string => (Number.isNaN(v) ? '  —  ' : `${(v * 100).toFixed(2)}%`);
const billions = (v: number): string => (Number.isFinite(v) ? `R$ ${(v / 1e9).toFixed(2)} bi` : '   —  ');

export async function main(_args: string[]): Promise<void> {
  const c = await Frozen.build();
  try {
    const assets: SizedAsset[] = [];
    const evaluated = new Map<Ticker, ValuationResult | null>();
    let i = 0;
    for (const t of c.universe) {
      i++;
      if (i % 50 === 0) process.stderr.write(`  ${i}/${c.universe.length}   \r`);
      const prep = await c.prepare(t);
      if (prep.isErr) continue;
      const inputs = prep.unwrap();
      const r = ValuationCascade.evaluate(inputs);
      evaluated.set(t, r.valueOrNull);
      if (r.isErr) continue;
      const v = r.unwrap();
      // O valor de mercado da fonte, que é o que existe na data congelada. Ele
      // erra em alguns tickers (decisão 83) e por isso **não entra em conta de
      // dinheiro** aqui: entra só na **ordenação** por tamanho, onde um erro de
      // escala não troca tercil.
      const marketValue = inputs.fundamentals.length === 0 ? null : inputs.fundamentals[inputs.fundamentals.length - 1]!.marketCap;
      if (marketValue === null || marketValue <= 0) continue;
      assets.push({
        ticker: t.value,
        marketValueOf: marketValue,
        beta: inputs.capm.beta,
        discount: v.discountRate,
        upside: v.upside,
        fairValueCents: v.fairValue.cents,
      });
    }
    process.stderr.write('                              \r');

    const div = await c.checkAgainstAnswerKey(evaluated);
    if (div === null) {
      errln('AVISO: gabarito ausente; montagem não conferida.');
    } else if (div.length > 0) {
      errln(`ERRO: montagem diverge do gabarito em ${div.length}: ${div.slice(0, 8).join(', ')}`);
      process.exitCode = 1;
      return;
    } else {
      outln('montagem conferida contra o gabarito: zero divergências.');
    }

    assets.sort((a, b) => compareNum(a.marketValueOf, b.marketValueOf));
    const n = assets.length;
    const logMarketValue = assets.map((a) => Math.log(a.marketValueOf));

    outln('');
    outln(`-- o tamanho contra o que o motor já cobra (${n} avaliados) --`);
    const rhoBeta = Regression.spearman(
      logMarketValue,
      assets.map((a) => a.beta),
    );
    const rhoDiscount = Regression.spearman(
      logMarketValue,
      assets.map((a) => a.discount),
    );
    const rhoUpside = Regression.spearman(
      logMarketValue,
      assets.map((a) => a.upside),
    );
    outln('  postos de log(valor de mercado) contra');
    outln(`    beta                ${f(rhoBeta)}`);
    outln(`    taxa de desconto    ${f(rhoDiscount)}`);
    outln(`    potencial           ${f(rhoUpside)}`);

    // Tercis, do menor para o maior.
    const cut = [0, intDiv(n, 3), intDiv(2 * n, 3), n];
    const names = ['menor', 'meio', 'maior'];
    const terciles: Record<string, unknown>[] = [];
    outln('');
    outln('-- o perfil por tercil de tamanho --');
    outln('  tercil   n   valor de mercado mediano   beta   desconto   potencial');
    for (let k = 0; k < 3; k++) {
      const band = assets.slice(cut[k], cut[k + 1]);
      const medianMarketValue = median(band.map((a) => a.marketValueOf));
      const betaMed = median(band.map((a) => a.beta));
      const descMed = median(band.map((a) => a.discount));
      const medianUpside = median(band.map((a) => a.upside));
      outln(
        `  ${names[k]!.padEnd(6)} ${String(band.length).padStart(3)}   ${billions(medianMarketValue).padStart(22)}   ` +
          `${betaMed.toFixed(3)}   ${pct(descMed).padStart(7)}   ${pct(medianUpside).padStart(8)}`,
      );
      terciles.push({
        tercil: names[k],
        n: band.length,
        valorDeMercadoMediano: medianMarketValue,
        betaMediano: betaMed,
        descontoMediano: descMed,
        potencialMediano: medianUpside,
        tickers: band.map((a) => a.ticker),
      });
    }

    // ---------------------------------------------------------------------
    // O efeito de um prêmio explícito de tamanho no tercil menor
    // ---------------------------------------------------------------------
    const smallest = new Set(assets.slice(0, cut[1]).map((a) => a.ticker));
    const withPremium = new Map<string, number>();
    const upsideWithPremium = new Map<string, number>();
    i = 0;
    for (const t of c.universe) {
      i++;
      if (i % 50 === 0) process.stderr.write(`  com prêmio: ${i}/${c.universe.length}   \r`);
      const premium = smallest.has(t.value) ? reference + sizePremium : reference;
      const prep = await c.prepare(t, { premium });
      if (prep.isErr) continue;
      const r = ValuationCascade.evaluate(prep.unwrap());
      if (r.isErr) continue;
      withPremium.set(t.value, r.unwrap().fairValue.cents);
      upsideWithPremium.set(t.value, r.unwrap().upside);
    }
    process.stderr.write('                                   \r');

    const before = new Map(assets.map((a) => [a.ticker, a] as const));
    const common = [...withPremium.keys()].filter((k) => before.has(k)).sort(compareStr);
    const changeList = common
      .filter((k) => before.get(k)!.fairValueCents !== 0)
      .map((k) => withPremium.get(k)! / before.get(k)!.fairValueCents - 1);
    const smallestChange = common
      .filter((k) => smallest.has(k) && before.get(k)!.fairValueCents !== 0)
      .map((k) => withPremium.get(k)! / before.get(k)!.fairValueCents - 1);
    const rhoWithPremium = Regression.spearman(
      common.map((k) => before.get(k)!.upside),
      common.map((k) => upsideWithPremium.get(k)!),
    );
    const leaving = [...before.keys()].filter((k) => !withPremium.has(k)).sort(compareStr);

    outln('');
    outln(`-- o efeito de ${pct(sizePremium)} no tercil menor --`);
    outln(
      `  preço justo, no tercil menor   mediana ${pct(median(smallestChange))}  ` +
        `(p25 ${pct(q(smallestChange, 0.25))}, p75 ${pct(q(smallestChange, 0.75))})`,
    );
    outln(`  preço justo, no universo       mediana ${pct(median(changeList))}`);
    outln(`  postos do potencial            ${f(rhoWithPremium)}`);
    outln(`  deixam de ser avaliáveis       ${leaving.length}${leaving.length === 0 ? '' : ` (${leaving.slice(0, 6).join(', ')})`}`);

    writeText(
      output,
      jsonPretty(
        {
          avaliados: n,
          spearmanLogValorDeMercado: { beta: rhoBeta, desconto: rhoDiscount, potencial: rhoUpside },
          tercis: terciles,
          premioDeTamanho: {
            premio: sizePremium,
            aplicadoEm: smallest.size,
            precoJustoMedianoNoTercilMenor: median(smallestChange),
            precoJustoMedianoNoUniverso: median(changeList),
            spearmanPotencial: rhoWithPremium,
            saem: leaving,
          },
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
