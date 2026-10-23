// A1.7 e A1.8 — a ingestão da CVM ligada ao motor, em três montagens.
//
//   mercado   só a fonte de mercado — o motor de antes
//   anual     CVM mesclada, série de DFPs                     (A1.7)
//   ancorada  CVM mesclada, doze meses no trimestre mais novo (A1.8)
//
// **Por que refazer o A1.7.** A primeira medição tratava como anual todo
// exercício terminado em dezembro. Cinco companhias do universo têm exercício
// social fora do calendário — AGRO3, SMTO3, CAML3, JALL3, RAIZ4 —, e para elas o
// ITR de dezembro é um acumulado parcial que entrava como ano cheio. O SMTO3
// (−45,2 p.p.) e o AGRO3 (−5,6 p.p.) estavam na lista de movimentos daquela
// medição, e eram artefato. Aqui a série anual é **a DFP**, pelo tipo de
// documento, e não pelo mês.
//
// **Sem olhar para a frente na mescla.** Um ponto da CVM terminado em junho só
// pode ser completado com o exercício de mercado que terminou **antes** dele. O
// de dezembro do mesmo ano ainda não existia.
//
// Uso:
//   npm run tool -- cvm-ingest data/cvm
//   npm run tool -- cvm-link
import {
  type Asset,
  compareNum,
  type CvmPeriodDocument,
  CvmSeries,
  DateTime,
  type FieldSource,
  type FundamentalsRepository,
  type FundamentalsSnapshot,
  intDiv,
  MarketAnchors,
  ok,
  PointInTimeView,
  PrepareValuationInputs,
  ResolveMarketAnchors,
  type Result,
  type Ticker,
  ValuationCascade,
  type ValuationResult,
} from '../src/core';
import { loadDocuments } from './cvm/documents';
import { jsonPretty, outln, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

/**
 * Repositório que monta a série pelo `CvmSeries` do núcleo — a mesma
 * montagem que o aplicativo usa (A1.9), e não uma cópia dela.
 */
class FromCvm implements FundamentalsRepository {
  readonly provenance = new Map<FieldSource, number>();

  /**
   * Tickers cuja série terminou ancorada em trimestre. Conjunto, e não
   * contador: `history` é chamado mais de uma vez por ativo.
   */
  readonly quarterAnchoredSet = new Set<string>();

  constructor(
    readonly market: FundamentalsRepository,
    readonly docs: Map<string, CvmPeriodDocument[]>,
    readonly today: DateTime,
    readonly anchored: boolean,
  ) {}

  async history(t: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    const base = await this.market.history(t);
    if (base.isErr) return base;
    const ownDocs = this.docs.get(t.value);
    if (ownDocs === undefined || ownDocs.length === 0) return base;
    const view = new PointInTimeView(this.today);
    const r = CvmSeries.build({
      documents: ownDocs,
      market: base.unwrap(),
      published: (s) => view.isPublished(s),
      anchored: this.anchored,
    });
    if (r.anchoredOnQuarter) this.quarterAnchoredSet.add(t.value);
    for (const [k, v] of r.provenance) this.provenance.set(k, (this.provenance.get(k) ?? 0) + v);
    return ok([...r.series]);
  }

  profile(t: Ticker): Promise<Result<Asset>> {
    return this.market.profile(t);
  }

  universe(): Promise<Result<Ticker[]>> {
    return this.market.universe();
  }
}

const pc = (v: number | null): string => (v === null ? '—' : `${(v * 100).toFixed(1)}%`);

function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = intDiv(s.length, 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

type Mount = 'mercado' | 'anual' | 'ancorada';

interface Row {
  ticker: string;
  mercado: number | null;
  anual: number | null;
  ancorada: number | null;
  fimAncora: string | null;
}

function compare(title: string, rows: readonly Row[], fromKey: Mount, toKey: Mount): void {
  const both = rows.filter((l) => l[fromKey] !== null && l[toKey] !== null);
  const gains = rows.filter((l) => l[fromKey] === null && l[toKey] !== null).map((l) => l.ticker);
  const lost = rows.filter((l) => l[fromKey] !== null && l[toKey] === null).map((l) => l.ticker);
  const move = (l: Row) => Math.abs(l[toKey]! - l[fromKey]!);
  const diff = both.map(move);
  outln(`\n== ${title} ==`);
  outln(`  avaliados: ${rows.filter((l) => l[fromKey] !== null).length} → ${rows.filter((l) => l[toKey] !== null).length}`);
  outln(`  ganhos  (${gains.length}): ${gains.slice(0, 14).join(' ')}`);
  outln(`  perdidos (${lost.length}): ${lost.slice(0, 14).join(' ')}`);
  outln(`  mediana do |Δ potencial|: ${pc(median(diff))}`);
  outln(`  |Δ| > 1 p.p.: ${diff.filter((d) => d > 0.01).length}   |Δ| > 10 p.p.: ${diff.filter((d) => d > 0.1).length}`);
  both.sort((a, b) => compareNum(move(b), move(a)));
  outln('  os que mais se moveram:');
  for (const l of both.slice(0, 12)) {
    const a = l[fromKey]!;
    const d = l[toKey]!;
    outln(`    ${l.ticker.padEnd(8)} ${pc(a).padStart(9)} → ${pc(d).padStart(9)}  (${pc(d - a)})  ${l.fimAncora ?? ''}`);
  }
}

export async function main(args: string[]): Promise<void> {
  /** Data da avaliação. Primeiro argumento, `AAAA-MM-DD`; padrão 04/09/2026. */
  const today = args.length === 0 ? DateTime.local(2026, 9, 4) : DateTime.parse(args[0]!);
  outln(`== avaliação em ${today.toIso8601String().slice(0, 10)} ==`);
  const docs = loadDocuments('data/cvm_exercicios.json');
  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark, asOf: today })).getOrElse(
      MarketAnchors.fallback2026,
    );
    const universe = (await ctx.fundamentals.universe()).unwrap();
    const annual = new FromCvm(ctx.fundamentals, docs, today, false);
    const anchored = new FromCvm(ctx.fundamentals, docs, today, true);

    const evaluate = async (t: Ticker, f: FundamentalsRepository): Promise<ValuationResult | null> => {
      const prep = await PrepareValuationInputs.call({
        ticker: t,
        prices: ctx.prices,
        fundamentals: f,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        projectionYears: 10,
      });
      if (prep.isErr) return null;
      const r = ValuationCascade.evaluate(prep.unwrap());
      return r.isOk ? r.unwrap() : null;
    };

    const rows: Row[] = [];
    let i = 0;
    const view = new PointInTimeView(today);
    for (const t of universe) {
      if (++i % 25 === 0) process.stderr.write(`  ${i}/${universe.length}   \r`);
      const m = await evaluate(t, ctx.fundamentals);
      const a = await evaluate(t, annual);
      const h = await anchored.history(t);
      const z = await evaluate(t, anchored);
      // O fim do último ponto **publicado** na data: a série montada traz
      // todos os exercícios, e o recorte é da cascata.
      const published = h.isOk ? h.unwrap().filter((s) => view.isPublished(s)) : [];
      rows.push({
        ticker: t.value,
        mercado: m?.upside ?? null,
        anual: a?.upside ?? null,
        ancorada: z?.upside ?? null,
        fimAncora: published.length === 0 ? null : published[published.length - 1]!.fiscalPeriodEnd.toIso8601String().slice(0, 10),
      });
    }
    process.stderr.write('\n');

    outln(`  documentos da CVM por ticker: ${docs.size}`);
    outln(`  avaliações com série ancorada em trimestre: ${anchored.quarterAnchoredSet.size}`);

    compare('A1.7 refeito — mercado → CVM anual', rows, 'mercado', 'anual');
    compare('A1.8 — CVM anual → CVM ancorada', rows, 'anual', 'ancorada');

    outln(`\n  procedência na montagem ancorada: {${[...anchored.provenance].map(([k, v]) => `${k}: ${v}`).join(', ')}}`);
    // Com data explícita, o arquivo leva a data: sem isso, a medição de
    // outra data sobrescrevia a da data padrão.
    const output = args.length === 0 ? 'docs/validacao/cvm_ligacao.json' : `docs/validacao/cvm_ligacao_${args[0]}.json`;
    writeText(output, jsonPretty(rows));
    outln(`  gravado ${output}`);
  } finally {
    await ctx.dispose();
  }
}
