// Item B5 — mede a divergência entre o fluxo descontado e os múltiplos de
// pares, no universo.
//
// **O que a segunda leitura serve para descobrir.** O item pedia «um teste de
// sanidade sobre o nível que hoje só a §2.8 discute em prosa». Esta ferramenta
// faz o teste: para cada avaliado, quanto o DCF diz, quanto os pares dizem, e
// quanto os dois discordam.
//
// **A pergunta que ela decide** é se o desacordo de nível do motor contra o
// mercado (§0: potencial mediano de −38%) aparece também contra os pares. Se o
// DCF ficar abaixo dos múltiplos na mesma proporção em que fica abaixo do
// preço, o desacordo é do modelo; se ficar perto dos múltiplos, ele é do
// mercado.
//
//   npm run tool -- cascade-golden       # congela a entrada
//   npm run tool -- multiples-package    # grava o pacote
//   npm run tool -- multiples            # grava multiplos.json
import { existsSync } from 'node:fs';

import {
  compareNum,
  type JsonObject,
  PeerMultipleCodec,
  PeerValuation,
  type Ticker,
  ValuationCascade,
  type ValuationResult,
} from '../src/core';
import { errln, jsonPretty, outln, readJson, writeText } from './lib/files';
import { pctColumn as pct, truncatedMedian as median, truncatedQuantile as q } from './lib/stats';
import { Frozen } from './validation/frozen';
import { Regression } from './validation/regression';

const packageFile = 'public/assets/mercado/multiplos_setoriais.json';
const output = 'docs/validacao/multiplos.json';

interface Row {
  ticker: string;
  setor: string | null;
  dcf: number;
  preco: number;
  potencial: number;
  multiplos: number | null;
  divergencia: number | null;
  aplicadas: number;
  leituras: Record<string, Record<string, unknown>>;
}

export async function main(_args: string[]): Promise<void> {
  if (!existsSync(packageFile)) {
    errln('pacote ausente: rode npm run tool -- multiples-package antes.');
    process.exitCode = 2;
    return;
  }
  const medians = PeerMultipleCodec.decode(readJson<JsonObject>(packageFile));

  const c = await Frozen.build();
  try {
    const evaluated = new Map<Ticker, ValuationResult | null>();
    const rows: Row[] = [];
    let i = 0;
    for (const t of c.universe) {
      i++;
      if (i % 50 === 0) process.stderr.write(`  ${i}/${c.universe.length}   \r`);
      const prep = await c.prepare(t);
      if (prep.isErr) continue;
      const b = prep.unwrap();
      // A mesma montagem do gabarito, **mais** o pacote de pares: é a única
      // diferença, e é o que se quer medir.
      const r = ValuationCascade.evaluate(b.withPeerMultiples(medians.get(t.value) ?? null));
      if (r.isErr) continue;
      const v = r.unwrap();
      evaluated.set(t, v);
      const tri = v.triangulation;
      const readings: Record<string, Record<string, unknown>> = {};
      for (const reading of tri?.readings ?? []) {
        readings[reading.kind.key] = reading.applied
          ? {
              justo: reading.fairValuePerShare,
              mediana: reading.peer!.median,
              pares: reading.peer!.peers,
              grupo: reading.peer!.group,
            }
          : { recusa: reading.refusal?.key ?? null };
      }
      rows.push({
        ticker: t.value,
        setor: b.sectorKey,
        dcf: v.fairValue.reais,
        preco: v.marketPrice.reais,
        potencial: v.upside,
        multiplos: tri?.consolidated ?? null,
        divergencia: tri?.divergence ?? null,
        aplicadas: tri?.applied ?? 0,
        leituras: readings,
      });
    }
    process.stderr.write('                              \r');

    // **A conferência é do preço justo, e não da triangulação.** A segunda
    // leitura não entra no preço: se o gabarito divergir, foi ela que vazou
    // para o cálculo, e a medição não vale.
    const div = await c.checkAgainstAnswerKey(evaluated);
    if (div === null) {
      errln('AVISO: gabarito ausente; montagem não conferida.');
    } else if (div.length > 0) {
      errln(
        `ERRO: a triangulação mudou o preço justo em ${div.length} ativo(s): ${div.slice(0, 8).join(', ')}. ` +
          'Ela é segunda leitura, e não pode entrar no cálculo.',
      );
      process.exitCode = 1;
      return;
    } else {
      outln('preço justo idêntico ao do gabarito em todos os avaliados: a segunda leitura não entra no cálculo.');
    }

    const withTriangulation = rows.filter((l) => l.multiplos !== null);
    const divergences = withTriangulation.filter((l) => l.divergencia !== null).map((l) => l.divergencia!);
    const aboveLimit = divergences.filter((d) => Math.abs(d) > PeerValuation.divergenceLimit).length;

    // O potencial pelos múltiplos, para comparar com o do DCF: os pares dizem
    // que a ação está cara ou barata?
    const dcfUpside: number[] = [];
    const multiplesUpside: number[] = [];
    for (const l of withTriangulation) {
      if (l.preco <= 0) continue;
      dcfUpside.push(l.potencial);
      multiplesUpside.push(l.multiplos! / l.preco - 1);
    }

    outln('');
    outln('-- a segunda leitura, sobre a entrada congelada --');
    outln(`  avaliados                        ${rows.length}`);
    outln(`  com alguma leitura de pares      ${withTriangulation.length}`);
    outln(`  divergência além de ${(PeerValuation.divergenceLimit * 100).toFixed(0)}%          ${aboveLimit} de ${divergences.length}`);
    outln('');
    outln('  divergência (múltiplos ÷ DCF − 1):');
    outln(
      `    p10 ${pct(q(divergences, 0.1))}   p25 ${pct(q(divergences, 0.25))}   mediana ${pct(median(divergences))}   ` +
        `p75 ${pct(q(divergences, 0.75))}   p90 ${pct(q(divergences, 0.9))}`,
    );
    outln('');
    outln('  potencial mediano:');
    outln(`    pelo fluxo descontado   ${pct(median(dcfUpside))}`);
    outln(`    pelos múltiplos         ${pct(median(multiplesUpside))}`);
    const rho = Regression.spearman(dcfUpside, multiplesUpside);
    outln(`    postos entre os dois    ${rho?.toFixed(4) ?? '—'}`);

    // Quantas leituras se aplicaram, e por que as outras não.
    const byApplied = new Map<number, number>();
    const refusals = new Map<string, number>();
    for (const l of rows) {
      byApplied.set(l.aplicadas, (byApplied.get(l.aplicadas) ?? 0) + 1);
      for (const [kind, m] of Object.entries(l.leituras)) {
        const r = m['recusa'];
        if (r !== null && r !== undefined) {
          const key = `${kind}: ${String(r)}`;
          refusals.set(key, (refusals.get(key) ?? 0) + 1);
        }
      }
    }
    outln('');
    outln('  leituras aplicadas por ativo:');
    const keys = [...byApplied.keys()].sort(compareNum);
    for (const k of keys) outln(`    ${k} de 3   ${byApplied.get(k)}`);
    outln('');
    outln('  por que as outras não entraram:');
    const sorted = [...refusals].sort((a, b) => compareNum(b[1], a[1]));
    for (const [k, v] of sorted) outln(`    ${k.padEnd(48)} ${v}`);

    writeText(
      output,
      jsonPretty(
        {
          avaliados: rows.length,
          comTriangulacao: withTriangulation.length,
          limiteDeDivergencia: PeerValuation.divergenceLimit,
          acimaDoLimite: aboveLimit,
          divergencia: {
            p10: q(divergences, 0.1),
            p25: q(divergences, 0.25),
            mediana: median(divergences),
            p75: q(divergences, 0.75),
            p90: q(divergences, 0.9),
          },
          potencialMedianoDcf: median(dcfUpside),
          potencialMedianoMultiplos: median(multiplesUpside),
          spearmanPotencial: rho,
          leiturasAplicadasPorAtivo: Object.fromEntries(keys.map((k) => [String(k), byApplied.get(k)])),
          recusas: Object.fromEntries(refusals),
          ativos: rows,
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
