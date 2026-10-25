// Item B5 — mede as medianas de múltiplos por grupo de pares e as empacota.
//
// **Por que empacotar.** A mediana é do **universo**, e a cascata avalia um
// ativo por vez: o núcleo não tem como calculá-la sem deixar de ser puro. É o
// mesmo arranjo do prior do beta (decisão 40) e do registro da B3 (decisão 82)
// — um programa varre, grava pacote versionado, e o aplicativo carrega.
//
// **Sobre a entrada congelada do gabarito, por padrão**, como os outros
// pacotes: todos são de 14/09/2026, e gerá-lo contra o dado do dia faria o
// pacote depender do que a fonte devolvesse naquele instante.
//
// **A hierarquia de grupo é declarada.** Subsetor quando há pares bastantes;
// setor quando não; mercado quando nem o setor tem. Cada mediana viaja com o
// grupo que a produziu e com quantos pares entraram, para que a tela possa
// dizer de onde o número saiu.
//
// Uso:
//   npm run tool -- cascade-golden      # congela a entrada
//   npm run tool -- multiples-package
import { compareNum, compareStr, FinancialSectors, MultipleKind, PeerValuation, ValuationCascade } from '../src/core';
import { DomainCopy } from '../src/copy/domain-copy';
import { jsonPretty, outln, writeText } from './lib/files';
import { Frozen, frozenToday } from './validation/frozen';

const output = 'public/assets/mercado/multiplos_setoriais.json';

/**
 * Mínimo de pares para que um grupo produza mediana. O mesmo corte que a
 * cascata cobra em `PeerValuation.minimumPeers` — duas cópias divergiriam.
 */
const minPeers = PeerValuation.minimumPeers;

/** A chave do grupo de mercado, quando nem o setor reúne pares. */
const market = 'mercado';

/** Um par observado: o múltiplo que ele negocia, com o grupo a que pertence. */
interface Peer {
  ticker: string;
  sector: string;
  subsector: string | null;
  priceToEarnings: number | null;
  priceToBook: number | null;
  evToEbitda: number | null;
}

function mult(p: Peer, k: MultipleKind): number | null {
  if (k === MultipleKind.priceToEarnings) return p.priceToEarnings;
  if (k === MultipleKind.priceToBook) return p.priceToBook;
  return p.evToEbitda;
}

function median(v: readonly number[]): number {
  const o = [...v].sort(compareNum);
  const mid = Math.floor(o.length / 2);
  return o.length % 2 === 1 ? o[mid]! : (o[mid - 1]! + o[mid]!) / 2;
}

/** A companhia do papel: as quatro letras que as classes compartilham. */
const company = (ticker: string): string => (ticker.length >= 4 ? ticker.substring(0, 4) : ticker);

/**
 * Os múltiplos do grupo, **um por companhia**, sem a companhia [without].
 *
 * **Par é outra companhia** (item B41). A mediana contava cada classe como um
 * par e incluía o próprio ativo: os sete «pares» de saneamento da SAPR11 eram
 * SAPR3, SAPR4 e SAPR11 e mais quatro, a mediana caía na própria Sanepar, e a
 * leitura de P/VP e a de EV/EBITDA devolviam, as duas, o preço da Sanepar na
 * data do pacote — R$ 38,15 ao centavo. Cada companhia entra com a mediana
 * das classes dela, e a do ativo avaliado não entra.
 */
function values(group: readonly Peer[], k: MultipleKind, without: string | null = null): number[] {
  const byCompany = new Map<string, number[]>();
  for (const p of group) {
    const c = company(p.ticker);
    if (c === without) continue;
    const m = mult(p, k);
    if (m !== null && Number.isFinite(m) && m > 0) {
      if (!byCompany.has(c)) byCompany.set(c, []);
      byCompany.get(c)!.push(m);
    }
  }
  return [...byCompany.values()].map(median);
}

interface GroupMedian {
  mediana: number;
  pares: number;
  grupo: string;
}

export async function main(_args: string[]): Promise<void> {
  const c = await Frozen.build();
  try {
    const pairs: Peer[] = [];
    let i = 0;
    for (const t of c.universe) {
      i++;
      if (i % 50 === 0) process.stderr.write(`  ${i}/${c.universe.length}   \r`);
      const prep = await c.prepare(t);
      if (prep.isErr) continue;
      const inputs = prep.unwrap();
      if (inputs.fundamentals.length === 0) continue;
      const f = inputs.fundamentals[inputs.fundamentals.length - 1]!;
      const sector = inputs.sectorKey;
      if (sector === null) continue;

      // **O divisor da ponte, e não a contagem da fonte.** O múltiplo
      // observado tem de sair da mesma contagem que a cascata usa do outro
      // lado, ou a mediana e a leitura medem pontes diferentes (decisão 83).
      const divisor = ValuationCascade.quotedShares({
        latest: f,
        marketPrice: inputs.marketPrice,
        sharesPerQuote: inputs.declaredSharesPerUnit ?? 1.0,
        published: inputs.fundamentals,
        official: inputs.officialShares,
        asOf: inputs.asOf,
      });
      if (divisor === null || divisor.count <= 0) continue;
      const marketValueOf = divisor.count * inputs.marketPrice;

      const profit = f.netIncome;
      const pl = f.totalStockholderEquity;
      const ebitda = f.ebitda;
      const financial = FinancialSectors.isFinancial({ sectorKey: sector, industry: inputs.industry });

      pairs.push({
        ticker: t.value,
        sector,
        subsector: inputs.industry,
        // Só múltiplo com a grandeza de baixo **positiva** entra na mediana:
        // P/L de prejuízo é negativo e não descreve quanto o mercado paga por
        // lucro — incluí-lo puxaria a mediana do setor para baixo por um
        // motivo que não é preço.
        priceToEarnings: profit !== null && profit > 0 ? marketValueOf / profit : null,
        priceToBook: pl !== null && pl > 0 ? marketValueOf / pl : null,
        // EBITDA de instituição financeira não descreve geração operacional
        // (decisão 102): ela não entra nem como par.
        evToEbitda: !financial && ebitda !== null && ebitda > 0 ? (marketValueOf + f.netDebt) / ebitda : null,
      });
    }
    process.stderr.write('                              \r');

    // ---------------------------------------------------------------------
    // As medianas, por grupo
    // ---------------------------------------------------------------------
    const bySubsector = new Map<string, Peer[]>();
    const bySector = new Map<string, Peer[]>();
    for (const p of pairs) {
      if (!bySector.has(p.sector)) bySector.set(p.sector, []);
      bySector.get(p.sector)!.push(p);
      const sub = p.subsector;
      if (sub !== null && sub !== '') {
        if (!bySubsector.has(sub)) bySubsector.set(sub, []);
        bySubsector.get(sub)!.push(p);
      }
    }

    const medianOf = (group: readonly Peer[], k: MultipleKind, name: string, without: string | null = null): GroupMedian | null => {
      const v = values(group, k, without);
      if (v.length < minPeers) return null;
      return { mediana: median(v), pares: v.length, grupo: name };
    };

    const groups = new Map<string, Record<string, GroupMedian>>();
    const register = (key: string, group: readonly Peer[]): void => {
      const m: Record<string, GroupMedian> = {};
      for (const k of MultipleKind.values) {
        const r = medianOf(group, k, key);
        if (r !== null) m[k.key] = r;
      }
      if (Object.keys(m).length > 0) groups.set(key, m);
    };

    for (const [key, value] of bySubsector) register(key, value);
    for (const [key, value] of bySector) register(key, value);
    register(market, pairs);

    // A ligação de cada ticker ao grupo que vale para ele: subsetor, setor,
    // mercado — na ordem, e **por múltiplo**, porque um subsetor pode ter pares
    // bastantes para P/VP e não para EV/EBITDA. A mediana de cada ticker é a
    // do grupo **sem a companhia dele** (item B41), e o mínimo de pares vale
    // sobre as outras companhias.
    const byTicker = new Map<string, Record<string, GroupMedian>>();
    for (const p of pairs) {
      const chosen: Record<string, GroupMedian> = {};
      const without = company(p.ticker);
      for (const k of MultipleKind.values) {
        const candidates: [string | null, readonly Peer[] | undefined][] = [
          [p.subsector, p.subsector === null ? undefined : bySubsector.get(p.subsector)],
          [p.sector, bySector.get(p.sector)],
          [market, pairs],
        ];
        for (const [key, members] of candidates) {
          if (key === null || members === undefined) continue;
          const m = medianOf(members, k, key, without);
          if (m !== null) {
            chosen[k.key] = m;
            break;
          }
        }
      }
      if (Object.keys(chosen).length > 0) byTicker.set(p.ticker, chosen);
    }

    const json = {
      geradoEm: frozenToday.toIso8601String(),
      minimoDePares: minPeers,
      observados: pairs.length,
      grupos: Object.fromEntries(groups),
      porTicker: Object.fromEntries(byTicker),
    };
    writeText(output, jsonPretty(json, '  '));

    outln('-- múltiplos de pares, sobre a entrada congelada --');
    outln(`  observados                 ${pairs.length}`);
    outln(`  grupos com alguma mediana  ${groups.size}`);
    outln(`  tickers ligados            ${byTicker.size}`);
    outln('');
    outln('  o mercado inteiro:');
    for (const k of MultipleKind.values) {
      const m = groups.get(market)?.[k.key];
      const label = DomainCopy.multiple(k);
      if (m === undefined) outln(`    ${label.padEnd(10)} —`);
      else outln(`    ${label.padEnd(10)} ${m.mediana.toFixed(2).padStart(7)}×   ${m.pares} pares`);
    }
    outln('');
    outln('  por setor econômico:');
    for (const key of [...bySector.keys()].sort(compareStr)) {
      const g = groups.get(key);
      if (g === undefined) continue;
      const row: string[] = [];
      for (const k of MultipleKind.values) {
        const m = g[k.key];
        if (m === undefined) continue;
        row.push(`${DomainCopy.multiple(k)} ${m.mediana.toFixed(1)}× (${m.pares})`);
      }
      outln(`    ${key.padEnd(32)} ${row.join('  ')}`);
    }
    outln('');
    outln(`escrito ${output}`);
  } finally {
    await c.ctx.dispose();
  }
}
