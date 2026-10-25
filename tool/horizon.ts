// Item B6 — a varredura do horizonte de projeção.
//
// **A pergunta.** O horizonte explícito é fixo em dez anos para todo ativo,
// independentemente de ciclo, setor ou maturidade, e nunca foi medido se dez é
// melhor que sete ou quinze.
//
// **O que esta ferramenta mede.** Sobre a entrada congelada do gabarito, o
// universo inteiro reavaliado em cada horizonte de 5 a 20 anos:
//
//   1. quantos ativos o motor avalia em cada horizonte;
//   2. quanto o preço justo se move contra o horizonte de dez;
//   3. quanto do valor vem do terminal em cada horizonte;
//   4. **a correlação de postos do potencial contra o horizonte de dez** — que
//      é o que decide se o horizonte pode mudar a medição de habilidade.
//
// O item pede a varredura "sobre o universo e sobre a habilidade". A perna da
// habilidade exige reexecutar as coortes, o que depende da base bruta (item
// C5); a correlação de postos é o que se pode afirmar sem ela, e ela responde a
// pergunta pelo lado forte: uma ordenação que não se move não pode mudar um
// `t`.
//
//   npm run tool -- cascade-golden   # congela a entrada
//   npm run tool -- horizon          # grava horizonte.json
import { compareStr, type Ticker, ValuationCascade, type ValuationResult } from '../src/core';
import { errln, jsonPretty, outln, writeText } from './lib/files';
import { pctColumn as pct, truncatedMedian as median, truncatedQuantile as q } from './lib/stats';
import { Frozen } from './validation/frozen';
import { Regression } from './validation/regression';

const horizons = [5, 6, 7, 8, 9, 10, 12, 15, 20];
const reference = 10;
const output = 'docs/validacao/horizonte.json';

class Reading {
  readonly fairValueCents = new Map<string, number>();
  readonly upside = new Map<string, number>();
  readonly terminalWeight = new Map<string, number>();
  readonly refusal = new Map<string, string>();
}

export async function main(_args: string[]): Promise<void> {
  const c = await Frozen.build();
  try {
    const readings = new Map<number, Reading>();

    for (const years of horizons) {
      const reading = new Reading();
      const evaluated = new Map<Ticker, ValuationResult | null>();
      let i = 0;
      for (const t of c.universe) {
        i++;
        if (i % 50 === 0) process.stderr.write(`  ${years} anos: ${i}/${c.universe.length}   \r`);
        const prep = await c.prepare(t, { years });
        if (prep.isErr) continue;
        const r = ValuationCascade.evaluate(prep.unwrap());
        if (years === reference) evaluated.set(t, r.valueOrNull);
        if (r.isErr) {
          reading.refusal.set(t.value, r.failureOrNull!.message);
          continue;
        }
        const v = r.unwrap();
        reading.fairValueCents.set(t.value, v.fairValue.cents);
        reading.upside.set(t.value, v.upside);
        const weight = v.diagnostics?.terminalShare ?? null;
        if (weight !== null) reading.terminalWeight.set(t.value, weight);
      }
      readings.set(years, reading);

      // **A conferência é do horizonte de referência, e só dele.** Os outros
      // são, por construção, outra montagem: conferi-los contra o gabarito
      // acusaria divergência que é o próprio objeto da medição.
      if (years === reference) {
        const div = await c.checkAgainstAnswerKey(evaluated);
        if (div === null) {
          errln('AVISO: gabarito ausente; a montagem não foi conferida.');
        } else if (div.length > 0) {
          errln(`ERRO: a montagem de ${years} anos diverge do gabarito em ${div.length} ativo(s): ${div.slice(0, 8).join(', ')}`);
          process.exitCode = 1;
          return;
        } else {
          outln(`montagem de ${reference} anos conferida contra o gabarito: zero divergências.`);
        }
      }
    }
    process.stderr.write('                                        \r');

    const base = readings.get(reference)!;
    const rows: Record<string, unknown>[] = [];

    outln('');
    outln('-- a varredura do horizonte, sobre a entrada congelada --');
    outln('  anos  avaliados  entram  saem   preço justo vs 10        peso do terminal   postos vs 10');

    for (const years of horizons) {
      const l = readings.get(years)!;
      const common = [...l.fairValueCents.keys()].filter((k) => base.fairValueCents.has(k)).sort(compareStr);

      const changeList = common
        .filter((k) => base.fairValueCents.get(k)! !== 0)
        .map((k) => l.fairValueCents.get(k)! / base.fairValueCents.get(k)! - 1);
      const included = [...l.fairValueCents.keys()].filter((k) => !base.fairValueCents.has(k)).sort(compareStr);
      const leaving = [...base.fairValueCents.keys()].filter((k) => !l.fairValueCents.has(k)).sort(compareStr);

      const rho =
        common.length < 3
          ? null
          : Regression.spearman(
              common.map((k) => base.upside.get(k)!),
              common.map((k) => l.upside.get(k)!),
            );

      const weights = [...l.terminalWeight.values()];

      outln(
        `  ${String(years).padStart(4)}  ${String(l.fairValueCents.size).padStart(9)}  ${String(included.length).padStart(6)}  ` +
          `${String(leaving.length).padStart(4)}   p25 ${pct(q(changeList, 0.25))}  med ${pct(median(changeList))}  ` +
          `p75 ${pct(q(changeList, 0.75))}   ${(median(weights) * 100).toFixed(1).padStart(6)}%   ` +
          (rho === null ? '   —  ' : rho.toFixed(4)),
      );

      rows.push({
        anos: years,
        avaliados: l.fairValueCents.size,
        comuns: common.length,
        entram: included,
        saem: leaving,
        precoJusto: {
          p10: q(changeList, 0.1),
          p25: q(changeList, 0.25),
          mediana: median(changeList),
          p75: q(changeList, 0.75),
          p90: q(changeList, 0.9),
          sobem: changeList.filter((v) => v > 0).length,
        },
        pesoTerminalMediano: median(weights),
        spearmanPotencialContra10: rho,
        formasDeRecusa: new Set(l.refusal.values()).size,
      });
    }

    // O par mais distante da varredura: se nem ele move a ordenação, nenhum
    // move.
    const first = readings.get(horizons[0]!)!;
    const last = readings.get(horizons[horizons.length - 1]!)!;
    const extremes = [...first.upside.keys()].filter((k) => last.upside.has(k)).sort(compareStr);
    const extremeRho =
      extremes.length < 3
        ? null
        : Regression.spearman(
            extremes.map((k) => first.upside.get(k)!),
            extremes.map((k) => last.upside.get(k)!),
          );
    outln('');
    outln(
      `  ${horizons[0]} contra ${horizons[horizons.length - 1]} anos, nos ${extremes.length} que os dois avaliam: ` +
        `postos ${extremeRho?.toFixed(4) ?? '—'}`,
    );

    writeText(
      output,
      jsonPretty(
        { referencia: reference, horizontes: rows, spearmanExtremos: extremeRho, ativosNosExtremos: extremes.length },
        '  ',
      ),
    );
    outln('');
    outln(`escrito ${output}`);
  } finally {
    await c.ctx.dispose();
  }
}
