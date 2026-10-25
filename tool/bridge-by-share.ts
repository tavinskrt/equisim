// A ponte por papel nas coortes — item C3.
//
// A limitação §3.5 dizia que nenhuma coorte exercitava a ponte por papel: com o
// valor de mercado reconstruído pela contagem do exercício, a razão de unidade
// saía 1 e as duas candidatas a divisor, iguais, por construção. Com a montagem
// na base da data (`tool/cohorts/as-of-base.ts`), esta ferramenta mede o que
// passou a acontecer, na mesma execução do backtest:
//
// 1. **o fator de base** — quanto o preço da fonte estava fora da base da data;
// 2. **de onde saiu o valor de mercado** — espécie a espécie, ou recuo;
// 3. **a razão de unidade contra a composição declarada na FCA** — a verdade
//    que a decisão 61 não tinha fora da amostra;
// 4. **a origem do divisor e a divergência** entre as candidatas;
// 5. **a coerência entre a unit e as espécies** da mesma companhia na mesma
//    coorte, que a §3 de `unidade.md` mediu num dia só.
//
// Entrada: `docs/validacao/backtest_trimestral.json`. Saída:
// `docs/validacao/ponte_por_papel.json`. Não vai à rede.
//
// Uso:
//   npm run tool -- bridge-by-share
import { existsSync } from 'node:fs';

import { compareNum, compareStr, intDiv, min, round, ValuationCascade } from '../src/core';
import { FcaCodes } from './cvm/fca-codes';
import { dartString, errln, fail, jsonPretty, outln, readJson, writeText } from './lib/files';

type Obs = Record<string, unknown>;

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);

function median(v: readonly number[]): number {
  const s = [...v].sort(compareNum);
  const m = intDiv(s.length, 2);
  return s.length === 0 ? Number.NaN : s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

export function main(_args: string[]): void {
  const source = 'docs/validacao/backtest_trimestral.json';
  if (!existsSync(source)) {
    fail(
      `Falta ${source}. Rode antes: npm run tool -- backtest-valuation ` +
        '--montagem aplicativo --com-deslistadas --trimestral --contrafactual-base',
    );
  }
  const rows = readJson<Obs[]>(source);
  const listed = rows.filter((l) => l['deslistada'] !== true);
  const output: Record<string, unknown> = { fonte: source, observacoes: rows.length };

  // ---- 1. O fator de base -------------------------------------------------
  const bands = new Map<string, number>();
  const byCohort = new Map<string, [number, number]>();
  let otherCode = 0;
  for (const l of listed) {
    const k = num(l['fatorDeBase']);
    if (k === null || k <= 0) continue;
    const d = Math.abs(Math.log(k));
    const band =
      d < Math.log(1.02) ? 'ate2pct' : d < Math.log(1.1) ? 'de2a10pct' : d < Math.log(1.5) ? 'de10a50pct' : 'acimaDe1vezEMeia';
    bands.set(band, (bands.get(band) ?? 0) + 1);
    const key = dartString(l['coorte']);
    let c = byCohort.get(key);
    if (c === undefined) byCohort.set(key, (c = [0, 0]));
    c[1]++;
    if (d >= Math.log(1.02)) c[0]++;
    if (l['pregaoDeOutroCodigo'] === true) otherCode++;
  }
  output['fatorDeBase'] = {
    observacoesDasListadas: listed.length,
    faixas: Object.fromEntries(bands),
    pregaoDeCodigoAnterior: otherCode,
    foraDe2pctPorCoorte: Object.fromEntries(
      [...byCohort].sort((a, b) => compareStr(a[0], b[0])).map(([k, v]) => [k, `${v[0]}/${v[1]}`]),
    ),
  };
  outln('== 1. Fator de base (listadas) ==');
  outln(`  ${dartString(bands)}; pregão de código anterior: ${otherCode}`);

  // ---- 2. De onde saiu o valor de mercado ---------------------------------
  const origin = new Map<string, number>();
  for (const l of rows) {
    const o = `${l['deslistada'] === true ? 'deslistada' : 'listada'}:${dartString(l['origemDoValorDeMercado'])}`;
    origin.set(o, (origin.get(o) ?? 0) + 1);
  }
  output['origemDoValorDeMercado'] = Object.fromEntries(origin);
  outln(`\n== 2. Valor de mercado ==\n  ${dartString(origin)}`);

  // ---- 3. A razão de unidade contra a composição declarada ----------------
  const fca = FcaCodes.read();
  const byUnit = new Map<string, { declarada: number; coortes: number; iguais: number; brutaMediana: number[] | number | null }>();
  let equalUnits = 0;
  let measuredUnits = 0;
  const unitDistances: number[] = [];
  let falsePositiveCount = 0;
  let nonUnitsMeasured = 0;
  for (const l of listed) {
    const u = num(l['razaoDeUnidade']);
    const shares = num(l['acoesNaData']);
    const marketValue = num(l['valorDeMercado']);
    const price = num(l['preco']);
    if (u === null) continue;
    const t = l['ticker'] as string;
    const declared = fca.sharesPerUnit.get(t);
    if (t.endsWith('11') && declared !== undefined) {
      measuredUnits++;
      if (Math.abs(u - declared) < 1e-9) equalUnits++;
      const raw = shares !== null && marketValue !== null && marketValue > 0 && price !== null ? (shares * price) / marketValue : null;
      if (raw !== null) unitDistances.push(Math.abs(raw / declared - 1));
      let r = byUnit.get(t);
      if (r === undefined) byUnit.set(t, (r = { declarada: declared, coortes: 0, iguais: 0, brutaMediana: [] }));
      r.coortes++;
      if (Math.abs(u - declared) < 1e-9) r.iguais++;
      if (raw !== null) (r.brutaMediana as number[]).push(raw);
    } else if (!t.endsWith('11')) {
      nonUnitsMeasured++;
      if (u > 1) falsePositiveCount++;
    }
  }
  for (const r of byUnit.values()) {
    const b = r.brutaMediana as number[];
    r.brutaMediana = b.length === 0 ? null : median(b);
  }
  unitDistances.sort(compareNum);
  const distanceQuantile = (p: number): number =>
    unitDistances.length === 0 ? Number.NaN : unitDistances[round((unitDistances.length - 1) * p)]!;
  output['razaoDeUnidade'] = {
    unitsComComposicaoDeclarada: measuredUnits,
    iguaisADeclarada: equalUnits,
    distanciaRelativaDaDeclarada: {
      mediana: distanceQuantile(0.5),
      p75: distanceQuantile(0.75),
      p90: distanceQuantile(0.9),
    },
    folgaDaDecisao61: ValuationCascade.unitRatioTolerance,
    porUnit: Object.fromEntries(byUnit),
    naoUnitsComRazaoMaiorQueUm: falsePositiveCount,
    naoUnitsMedidas: nonUnitsMeasured,
  };
  outln('\n== 3. Razão de unidade ==');
  outln(`  units com composição declarada: ${equalUnits} de ${measuredUnits} coortes com a razão igual à declarada`);
  outln(
    `  distância relativa da declarada: mediana ${distanceQuantile(0.5).toFixed(3)}, ` +
      `p75 ${distanceQuantile(0.75).toFixed(3)}, p90 ${distanceQuantile(0.9).toFixed(3)}`,
  );
  for (const [t, r] of byUnit) outln(`    ${t}: ${dartString(r)}`);
  outln(`  não units com razão > 1: ${falsePositiveCount} de ${nonUnitsMeasured}`);

  // ---- 4. A origem do divisor ---------------------------------------------
  const divisor = new Map<string, number>();
  let diverge = 0;
  let measuredCount = 0;
  for (const l of rows) {
    const o = l['origemDoDivisor'];
    if (o === null || o === undefined) continue;
    measuredCount++;
    const key = dartString(o);
    divisor.set(key, (divisor.get(key) ?? 0) + 1);
    if (l['divisorDiverge'] === true) diverge++;
  }
  output['divisor'] = { origem: Object.fromEntries(divisor), candidatasDivergem: diverge, medidos: measuredCount };
  outln(`\n== 4. Divisor ==\n  ${dartString(divisor)}; candidatas divergem em ${diverge} de ${measuredCount}`);

  // ---- 5. A unit contra as espécies da mesma companhia --------------------
  // Na mesma coorte, o potencial da unit e o da espécie mais próxima dela
  // descrevem o mesmo negócio; o que sobra é o ágio entre espécies.
  const byKey = new Map<string, Map<string, number>>();
  for (const l of listed) {
    const up = num(l['upside']);
    if (up === null) continue;
    const t = l['ticker'] as string;
    const key = `${dartString(l['coorte'])}|${t.slice(0, 4)}`;
    let m = byKey.get(key);
    if (m === undefined) byKey.set(key, (m = new Map()));
    m.set(t, up);
  }
  const differences: number[] = [];
  const oldVersions: number[] = [];
  for (const m of byKey.values()) {
    const unit = [...m].filter(([k]) => k.endsWith('11'));
    const kinds = [...m].filter(([k]) => !k.endsWith('11'));
    if (unit.length === 0 || kinds.length === 0) continue;
    for (const [, uv] of unit) {
      differences.push(kinds.map(([, x]) => Math.abs((1 + uv) / (1 + x) - 1)).reduce(min));
    }
  }
  for (const l of listed) {
    // A mesma distância na montagem antiga, quando a coorte de 30/09 a mediu.
    const t = l['ticker'] as string;
    if (!t.endsWith('11')) continue;
    const oldUpside = num(l['upsideBaseAntiga']);
    if (oldUpside === null) continue;
    const pairs = listed.filter(
      (x) =>
        x['coorte'] === l['coorte'] &&
        (x['ticker'] as string).startsWith(t.slice(0, 4)) &&
        !(x['ticker'] as string).endsWith('11') &&
        num(x['upsideBaseAntiga']) !== null,
    );
    if (pairs.length === 0) continue;
    oldVersions.push(pairs.map((x) => Math.abs((1 + oldUpside) / (1 + num(x['upsideBaseAntiga'])!) - 1)).reduce(min));
  }
  output['unitContraEspecie'] = {
    pares: differences.length,
    distanciaMediana: differences.length === 0 ? null : median(differences),
    paresNaBaseAntiga: oldVersions.length,
    distanciaMedianaNaBaseAntiga: oldVersions.length === 0 ? null : median(oldVersions),
  };
  outln(`\n== 5. Unit contra espécie ==\n  ${dartString(output['unitContraEspecie'])}`);

  writeText('docs/validacao/ponte_por_papel.json', jsonPretty(output));
  errln('\nescrito docs/validacao/ponte_por_papel.json');
}
