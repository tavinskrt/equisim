// Fase 1 — o que cada peça do eixo A move, somadas uma a uma, na mesma execução.
//
// Quatro montagens por ativo, na mesma data e com os mesmos dados — comparar
// execuções diferentes mistura o efeito do código com a deriva do dado de
// mercado, que já contaminou 26 ativos entre duas execuções com meia hora de
// intervalo (cvm_trimestral.md §3.5):
//
//   mercado    fonte de preços, dois pontos do CDI, divisor da fonte (antes)
//   +oficial   mais a contagem oficial da B3 no divisor        (A3.3, dec. 83)
//   +curva     mais a curva do Tesouro                         (A2.1, dec. 84)
//   padrão     mais a CVM anual — a configuração do aplicativo até A3
//   +setor     mais a classificação setorial oficial da B3     (A5, dec. 87)
//   +prazo     mais o prazo das outorgas do FRE                (A6, dec. 88)
//   +proventos mais o beta sobre retorno total, com a B3       (A4, dec. 89)
//
// `+proventos` é a configuração do aplicativo ao fim da Fase 1.
//
// A data é a da consulta ao registro da B3: registro consultado depois da
// avaliação não entra nela, pela regra de nunca olhar para a frente.
//
// Uso:
//   npm run tool -- default-link [AAAA-MM-DD]
import {
  type Asset,
  type B3Issuer,
  B3RegistryCodec,
  CashDividendsCodec,
  compareNum,
  ConcessionSectors,
  ConcessionTermsCodec,
  type CvmPeriodDocument,
  CvmSeries,
  CyclicalSectors,
  DateTime,
  FinancialSectors,
  type FundamentalsRepository,
  type FundamentalsSnapshot,
  type JsonObject,
  MarketAnchors,
  ok,
  OfficialShareCount,
  PointInTimeView,
  PrepareValuationInputs,
  ResolveMarketAnchors,
  type Result,
  type Ticker,
  TreasuryCurve,
  ValuationCascade,
  type ValuationResult,
} from '../src/core';
import { OfficialSectorFundamentalsRepository } from '../src/data/repositories/b3-registry-repository';
import { readTreasury } from './curve-link';
import { loadDocuments } from './cvm/documents';
import { errln, jsonPretty, outln, readJson, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

/** A série montada pelo `CvmSeries` do núcleo, sobre a da fonte de mercado. */
class FromCvm implements FundamentalsRepository {
  constructor(
    readonly market: FundamentalsRepository,
    readonly docs: Map<string, CvmPeriodDocument[]>,
    readonly today: DateTime,
  ) {}

  async history(t: Ticker): Promise<Result<FundamentalsSnapshot[]>> {
    const base = await this.market.history(t);
    if (base.isErr) return base;
    const ownDocs = this.docs.get(t.value);
    if (ownDocs === undefined || ownDocs.length === 0) return base;
    const view = new PointInTimeView(this.today);
    return ok([
      ...CvmSeries.build({
        documents: ownDocs,
        market: base.unwrap(),
        published: (s) => view.isPublished(s),
        anchored: false,
      }).series,
    ]);
  }

  profile(t: Ticker): Promise<Result<Asset>> {
    return this.market.profile(t);
  }

  universe(): Promise<Result<Ticker[]>> {
    return this.market.universe();
  }
}

/** Mediana com média dos dois centrais quando o tamanho é par. */
function median(v: readonly number[]): number | null {
  if (v.length === 0) return null;
  const s = [...v].sort(compareNum);
  const m = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

function spearman(a: readonly number[], b: readonly number[]): number {
  const ranks = (v: readonly number[]): number[] => {
    const idx = v.map((_, i) => i).sort((x, y) => compareNum(v[x]!, v[y]!));
    const r = new Array<number>(v.length).fill(0);
    let k = 0;
    while (k < idx.length) {
      let j = k;
      // Empate a um trilionésimo: dois potenciais iguais podem diferir no
      // último dígito binário, e `double` não se compara por igualdade.
      while (j + 1 < idx.length && Math.abs(v[idx[j + 1]!]! - v[idx[k]!]!) < 1e-12) j++;
      for (let m = k; m <= j; m++) r[idx[m]!] = (k + j) / 2 + 1;
      k = j + 1;
    }
    return r;
  };

  const ranksA = ranks(a);
  const ranksB = ranks(b);
  const meanA = ranksA.reduce((x, y) => x + y) / ranksA.length;
  const meanB = ranksB.reduce((x, y) => x + y) / ranksB.length;
  let n = 0.0;
  let sumSqA = 0.0;
  let sumSqB = 0.0;
  for (let i = 0; i < ranksA.length; i++) {
    n += (ranksA[i]! - meanA) * (ranksB[i]! - meanB);
    sumSqA += (ranksA[i]! - meanA) * (ranksA[i]! - meanA);
    sumSqB += (ranksB[i]! - meanB) * (ranksB[i]! - meanB);
  }
  // Sem variância numa das duas não há correlação a medir.
  if (!(sumSqA > 0 && sumSqB > 0)) return 0;
  return n / Math.sqrt(sumSqA * sumSqB);
}

const pc = (v: number | null): string => (v === null ? '—' : `${(v * 100).toFixed(1)}%`);

type Assembly = 'mercado' | 'oficial' | 'curva' | 'padrao' | 'setor' | 'prazo' | 'proventos';

interface Row extends Record<Assembly, number | null> {
  ticker: string;
  fimDoContrato: string | null;
  fonteDoDivisor: string | null;
  avisosPadrao: readonly string[] | null;
}

export async function main(args: string[]): Promise<void> {
  const today = args.length === 0 ? DateTime.local(2026, 9, 14) : DateTime.parse(args[0]!);
  const registry = B3RegistryCodec.decodePackage(readJson<JsonObject>('public/assets/b3/emissores.json'));
  const curve = TreasuryCurve.at(readTreasury('data/tesouro/precotaxatesourodireto.csv'), today);
  const docs = loadDocuments('data/cvm_exercicios.json');
  const terms = ConcessionTermsCodec.decode(readJson<JsonObject>('public/assets/cvm/outorgas.json'));
  const dividends = CashDividendsCodec.decode(readJson<JsonObject>('public/assets/b3/proventos.json'));

  const ctx = ValidationContext.create({ outputDir: 'docs/validacao' });
  try {
    const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark, asOf: today })).getOrElse(
      MarketAnchors.fallback2026,
    );
    const universe = (await ctx.fundamentals.universe()).unwrap();
    const fromCvm = new FromCvm(ctx.fundamentals, docs, today);
    const issuer = (t: Ticker): B3Issuer | null => registry.get(t.value.length >= 4 ? t.value.substring(0, 4) : '') ?? null;
    const withSector = new OfficialSectorFundamentalsRepository({
      inner: fromCvm,
      classification: async (t) => issuer(t)?.classification ?? null,
    });

    const evaluate = async (
      t: Ticker,
      opts: { official: boolean; withCurve: boolean; cvm: boolean; sector?: boolean; term?: boolean; withDividends?: boolean },
    ): Promise<ValuationResult | null> => {
      const e = issuer(t);
      const prep = await PrepareValuationInputs.call({
        ticker: t,
        prices: ctx.prices,
        fundamentals: opts.sector === true ? withSector : opts.cvm ? fromCvm : ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        riskFreeCurve: opts.withCurve ? curve : null,
        officialShares:
          opts.official && e !== null && e.totalShares !== null ? new OfficialShareCount({ total: e.totalShares, asOf: e.consultedOn }) : null,
        projectionYears: 10,
        concessionEnd: opts.term === true ? (terms.get(t.value)?.end ?? null) : null,
        dividends: opts.withDividends === true ? CashDividendsCodec.forTicker(dividends, t.value) : null,
      });
      if (prep.isErr) return null;
      const r = ValuationCascade.evaluate(prep.unwrap());
      return r.isOk ? r.unwrap() : null;
    };

    // A5 antes de avaliar: o que muda de porta pela classificação oficial.
    const changes: string[] = [];
    for (const t of universe) {
      const source = await ctx.fundamentals.profile(t);
      const official = issuer(t)?.classification ?? null;
      if (official === null) continue;
      const sk = source.isOk ? source.unwrap().sector.key : null;
      const ind = source.isOk ? source.unwrap().industry : null;
      const gates = (key: string | null, sub: string | null): string =>
        [
          ...(FinancialSectors.isFinancial({ sectorKey: key, industry: sub }) ? ['financeira'] : []),
          ...(CyclicalSectors.hasCyclePrecedence({ sectorKey: key, industry: sub }) ? ['cíclica'] : []),
          ...(ConcessionSectors.hasFiniteTerm({ sectorKey: key, industry: sub }) ? ['concessão'] : []),
        ].join('+');
      const before = gates(sk, ind);
      const after = gates(official.sectorKey, official.industry);
      if (before !== after) {
        changes.push(
          `    ${t.value.padEnd(7)} ${before === '' ? '—' : before} → ${after === '' ? '—' : after}   (${sk ?? 'sem setor'} | ${official.label})`,
        );
      }
    }

    const rows: Row[] = [];
    let i = 0;
    for (const t of universe) {
      if (++i % 25 === 0) process.stderr.write(`  ${i}/${universe.length}   \r`);
      const m = await evaluate(t, { official: false, withCurve: false, cvm: false });
      const o = await evaluate(t, { official: true, withCurve: false, cvm: false });
      const c = await evaluate(t, { official: true, withCurve: true, cvm: false });
      const p = await evaluate(t, { official: true, withCurve: true, cvm: true });
      const st = await evaluate(t, { official: true, withCurve: true, cvm: true, sector: true });
      const pz = await evaluate(t, { official: true, withCurve: true, cvm: true, sector: true, term: true });
      const pv = await evaluate(t, { official: true, withCurve: true, cvm: true, sector: true, term: true, withDividends: true });
      const end = terms.get(t.value)?.end ?? null;
      rows.push({
        ticker: t.value,
        mercado: m?.upside ?? null,
        oficial: o?.upside ?? null,
        curva: c?.upside ?? null,
        padrao: p?.upside ?? null,
        setor: st?.upside ?? null,
        prazo: pz?.upside ?? null,
        proventos: pv?.upside ?? null,
        fimDoContrato: end === null ? null : end.toIso8601String().substring(0, 10),
        fonteDoDivisor: o?.warnings.some((w) => w.includes('contagem oficial da B3')) === true ? 'oficial-divergente' : null,
        avisosPadrao: p?.warnings ?? null,
      });
    }
    errln('');

    outln(`== Fase 1 somada, em ${today.toIso8601String().substring(0, 10)} ==`);
    outln(
      `  curva: ${curve === null ? 'AUSENTE — a montagem +curva repete a anterior' : `data-base ${curve.referenceDate.toIso8601String().substring(0, 10)}`}`,
    );
    const compare = (title: string, fromKey: Assembly, toKey: Assembly): void => {
      const both = rows.filter((l) => l[fromKey] !== null && l[toKey] !== null);
      const delta = (l: Row): number => Math.abs(l[toKey]! - l[fromKey]!);
      const diff = both.map(delta);
      const medianFrom = median(both.map((l) => l[fromKey]!));
      const medianTo = median(both.map((l) => l[toKey]!));
      outln(`\n== ${title} ==`);
      outln(`  avaliados: ${rows.filter((l) => l[fromKey] !== null).length} → ${rows.filter((l) => l[toKey] !== null).length}`);
      outln(`  ganhos: ${rows.filter((l) => l[fromKey] === null && l[toKey] !== null).map((l) => l.ticker).join(' ')}`);
      outln(`  perdidos: ${rows.filter((l) => l[fromKey] !== null && l[toKey] === null).map((l) => l.ticker).join(' ')}`);
      outln(`  potencial mediano: ${pc(medianFrom)} → ${pc(medianTo)}`);
      outln(`  mediana do |Δ|: ${pc(median(diff))}   |Δ| > 10 p.p.: ${diff.filter((d) => d > 0.1).length}`);
      if (both.length > 2) {
        outln(`  correlação de postos: ${spearman(both.map((l) => l[fromKey]!), both.map((l) => l[toKey]!)).toFixed(4)}`);
      }
      both.sort((a, b) => compareNum(delta(b), delta(a)));
      outln('  os que mais se moveram:');
      for (const l of both.slice(0, 12)) {
        outln(`    ${l.ticker.padEnd(8)} ${pc(l[fromKey]).padStart(9)} → ${pc(l[toKey]).padStart(9)}`);
      }
    };

    compare('A3.3 — contagem oficial no divisor', 'mercado', 'oficial');
    compare('A2.1 — curva do Tesouro', 'oficial', 'curva');
    compare('A1.7 a A1.11 — CVM anual', 'curva', 'padrao');
    outln(`\n== A5 — portas que mudam pela classificação oficial (${changes.length}) ==`);
    for (const line of changes) outln(line);
    compare('A5 — classificação setorial oficial', 'padrao', 'setor');
    compare('A6 — prazo das outorgas', 'setor', 'prazo');
    compare('A4 — beta sobre retorno total', 'prazo', 'proventos');
    compare('Fase 1 inteira — antes → padrão do aplicativo', 'mercado', 'proventos');

    const output = `docs/validacao/padrao_ligacao_${today.toIso8601String().substring(0, 10)}.json`;
    writeText(output, jsonPretty(rows, ' '));
    outln(`\n  gravado ${output}`);
  } finally {
    await ctx.dispose();
  }
}
