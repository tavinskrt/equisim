// D1 — gabarito da cascata: a condição para quebrar `evaluateLane`.
//
// Quebrar `evaluateLane` em estágios é refatoração pura: **nenhum número pode
// mudar**. A cascata é determinística — é regra do núcleo —, então isso é
// verificável ao bit: este gabarito grava a saída completa do universo, e o
// modo `--conferir` refaz e compara.
//
// **Nove montagens por ativo**, para que todo caminho do método seja
// exercitado com dado real:
//
//   doisPontos   fonte de mercado, taxa livre de risco de dois pontos
//   curva        mais a curva do Tesouro (decisão 74)
//   aplicativo   contagem oficial, curva, CVM, setor da B3, prazo das outorgas
//                e beta de retorno total — a montagem do aplicativo
//   ancorada     a do aplicativo, com a série de doze meses (decisão 73)
//   prior        a do aplicativo mais o prior do beta: é a única que liga o
//                ponto fixo das taxas, a rota derivada, os passes do veredito e
//                a estrutura recusada — o aplicativo não resolve o prior (B11),
//                e sem esta montagem esses caminhos ficariam fora do gabarito
//   monteCarlo   a do prior com cenários sorteados, que chamam a avaliação por
//                premissa nas duas vias
//   viaFirma     a do prior com a via da firma imposta
//   viaAcionista a do prior com a via do acionista imposta
//   impostos     a do prior com crescimento, fator de base, retorno terminal,
//                freio e convenção de caixa impostos
//
// Cada montagem grava o resultado inteiro **e o rastro de auditoria**: um passo
// fora de ordem ou uma variável trocada no rastro é mudança que o resultado não
// mostra.
//
// **O gabarito congela a entrada junto com a saída.** O cache da validação
// expira e o Ibovespa vem da rede sem cache — em meia hora, 26 ativos mudaram de
// valor sem mudança de código. Por isso a gravação copia o cache para
// `data/gabarito/`, trata toda entrada presente como fresca, grava o Ibovespa
// servido e a conferência repete os dois sem ir à rede. Confira primeiro o
// código intacto, como controle: divergência ali é defeito do congelamento, não
// refatoração.
//
// **Um gabarito gravado pela versão em Dart não confere contra esta.** O
// rastro é impresso pela serialização JSON da linguagem, e o JavaScript
// escreve `1` onde o Dart escrevia `1.0` — a impressão muda sem que número
// algum mude. Depois da migração (decisão 152), grave de novo antes de
// conferir.
//
// Uso:
//   npm run tool -- cascade-golden                # grava o gabarito
//   npm run tool -- cascade-golden --conferir     # compara com o gravado
//   npm run tool -- cascade-golden --regravar --saida <arq>
//                                                 # regrava sem mexer na
//                                                 # entrada congelada
//   npm run tool -- cascade-golden --rastro PETR4 # rastro de um ativo
//   npm run tool -- cascade-golden --monotonia docs/validacao/monotonia_vias.json
//   npm run tool -- cascade-golden --nivel GOAU4  # a grade de um ativo, aberta
//
// **`--monotonia`** usa a mesma entrada congelada para a varredura do item
// B10: desloca o nível da taxa livre de risco — a corrente, a de equilíbrio e a
// curva inteira — de −3 a +3 p.p., de 25 em 25 pontos-base, nas montagens
// `aplicativo` e `prior`, e confere se o preço justo cai quando o capital
// encarece. Conta também o que muda de via e o que alterna entre avaliado e
// recusado no meio da grade.
import { copyFileSync, existsSync, mkdirSync, readFileSync, unlinkSync } from 'node:fs';

import {
  type AuditEvent,
  AuditRecorder,
  type B3Classification,
  type B3Issuer,
  B3RegistryCodec,
  type BenchmarkRepository,
  BetaPriorCodec,
  type CapitalEvents,
  CapitalEventsCodec,
  type CashDividend,
  CashDividendsCodec,
  CapmInputs,
  CashTiming,
  compareStr,
  ConcessionTermsCodec,
  CvmDocumentCodec,
  type DateRange,
  type FundamentalsRepository,
  ImpliedPremiumCodec,
  InsufficientData,
  type JsonObject,
  MarketAnchors,
  MarketPremiumSource,
  OfficialShareCount,
  PrepareValuationInputs,
  type PriceSeries,
  ReinvestmentPolicy,
  ResolveBetaPrior,
  ResolveMarketAnchors,
  type Result,
  ShareholderControl,
  ShareholderControlHistory,
  type ShareholderControlPeriod,
  StochasticScenarios,
  Ticker,
  TreasuryCurve,
  TreasuryQuotesCodec,
  type UnitComposition,
  UnitCompositionCodec,
  ValuationCascade,
  type ValuationInputs,
  ValuationLane,
  type ValuationResult,
  type YieldCurve,
  err,
  ok,
} from '../src/core';
import { OfficialSectorFundamentalsRepository } from '../src/data/repositories/b3-registry-repository';
import { dartString, errln, jsonPretty, outln, readJson, writeText } from './lib/files';
import { ValidationContext } from './validation/context';
import { CvmFundamentals, frozenToday, SavedIbovespa } from './validation/frozen';

const today = frozenToday;
const file = 'docs/validacao/gabarito_cascata.json';
const folder = 'data/gabarito';
const cache = `${folder}/cache.sqlite`;
const ibovespaFile = `${folder}/ibovespa.json`;
const universeFile = `${folder}/universo.json`;

/**
 * O Ibovespa servido, por janela: gravado na primeira execução e repetido nas
 * seguintes. Janela que não foi gravada é recusada, e a divergência aparece.
 */
class FrozenIbovespa implements BenchmarkRepository {
  constructor(
    readonly network: BenchmarkRepository | null,
    readonly saved: Map<string, PriceSeries>,
  ) {}

  private static key(r: DateRange): string {
    return `${r.start.toIso8601String()}|${r.end.toIso8601String()}`;
  }

  async ibovespa(range: DateRange): Promise<Result<PriceSeries>> {
    const k = FrozenIbovespa.key(range);
    const g = this.saved.get(k);
    if (g !== undefined) return ok(g);
    const source = this.network;
    if (source === null) return err(new InsufficientData(`Ibovespa não gravado para ${k}`));
    const r = await source.ibovespa(range);
    if (r.isOk) this.saved.set(k, r.unwrap());
    return r;
  }

  toJson(): Record<string, unknown> {
    const out: Record<string, unknown> = {};
    for (const [k, v] of this.saved) {
      out[k] = {
        ticker: v.ticker.value,
        pontos: v.points.map((p) => [p.date.toIso8601String(), p.close, p.adjustedClose, p.volume]),
      };
    }
    return out;
  }
}

/**
 * O `double.toString()` do Dart: a representação mais curta que volta ao mesmo
 * bit, com `.0` no número inteiro. É o que torna a comparação exata, e mantém
 * o texto gravado igual ao da versão anterior onde o número é o mesmo.
 */
function dbl(x: number): string {
  if (Number.isNaN(x)) return 'NaN';
  if (x === Number.POSITIVE_INFINITY) return 'Infinity';
  if (x === Number.NEGATIVE_INFINITY) return '-Infinity';
  if (Object.is(x, -0)) return '-0.0';
  const s = String(x);
  return Number.isInteger(x) && !s.includes('e') ? `${s}.0` : s;
}

const dblOrNull = (x: number | null | undefined): string | null => (x === null || x === undefined ? null : dbl(x));

const two32 = 4294967296;

/**
 * FNV-1a de 64 bits sobre o texto. O rastro de auditoria do universo inteiro
 * passa de centenas de megabytes; o gabarito guarda a impressão dele, e o
 * modo `--rastro TICKER` mostra o rastro de um ativo para achar a diferença.
 *
 * Em duas metades de 32 bits, e não em `BigInt`: o primo é `2⁴⁰ + 0x1b3`, de
 * modo que `h × primo = h × 0x1b3 + (h ≪ 40)`, e cada parcela cabe exata no
 * `number`.
 */
export function fingerprint(text: string): string {
  let hi = 0xcbf29ce4;
  let lo = 0x84222325;
  for (const u of Buffer.from(text, 'utf8')) {
    lo = (lo ^ u) >>> 0;
    const loProd = lo * 0x1b3;
    const carry = Math.floor(loProd / two32);
    const newLo = loProd - carry * two32;
    const hiProd = hi * 0x1b3 + carry + (lo & 0xffffff) * 256;
    hi = hiProd % two32;
    lo = newLo;
  }
  return hi.toString(16).padStart(8, '0') + lo.toString(16).padStart(8, '0');
}

type Serialized = Record<string, unknown>;

/** Tudo o que o resultado expõe. */
function serialize(r: Result<ValuationResult>): Serialized {
  if (r.isErr) return { recusa: r.failureOrNull!.message };
  const v = r.unwrap();
  const d = v.diagnostics;
  const dist = v.distribution;
  const scenarios: Record<string, number> | null =
    v.discreteScenarios === null ? null : Object.fromEntries([...v.discreteScenarios].map(([k, m]) => [k.name, m.cents]));
  return {
    modelo: v.model.name,
    justoCentavos: v.fairValue.cents,
    precoCentavos: v.marketPrice.cents,
    potencial: dbl(v.upside),
    desconto: dbl(v.discountRate),
    modo: v.mode.name,
    cenarios: scenarios,
    ...(dist !== null
      ? {
          distribuicao: {
            n: dist.sortedValues.length,
            p5: dbl(dist.p5),
            mediana: dbl(dist.median),
            p95: dbl(dist.p95),
            impressao: fingerprint(dist.sortedValues.map(dbl).join(',')),
          },
        }
      : {}),
    avisos: v.warnings,
    ...(d !== null
      ? {
          diagnostico: {
            pesoTerminal: dbl(d.terminalShare),
            excedenteTerminal: dblOrNull(d.terminalExcessShare),
            retornoImplicitoTerminal: dblOrNull(d.impliedTerminalReturn),
            pesoEquityTerminal: dblOrNull(d.terminalEquityShare),
            pesoEquity: dbl(d.equityShare),
            fatorBase: dbl(d.baseFactor),
            crescimentoIdentificado: d.growthIdentified,
            moat: d.moatApplied,
            spreadRetido: dbl(d.terminalRetainedSpread),
            crescimento: dbl(d.growthRate),
            retornoTerminal: dblOrNull(d.terminalReturnOnCapital),
            aliquota: dblOrNull(d.firmTaxRate),
            retorno: dbl(d.returnOnCapital),
            descontoTerminal: dbl(d.terminalDiscountRate),
            keTerminal: dblOrNull(d.terminalCostOfEquity),
            ke: dbl(d.costOfEquity),
            caminhoCrescimento: d.growthPath.map(dbl),
            caminhoRetencao: d.retentionPath.map(dbl),
            ressalvas: d.caveats.map((c) => c.key),
          },
        }
      : {}),
  };
}

/**
 * Os mesmos insumos com as imposições de diagnóstico.
 *
 * **Pela cópia do núcleo** (item B27). A versão à mão perdia a composição
 * declarada da unit, a taxa de referência do crédito, a janela do beta e os
 * múltiplos de pares, e as montagens de diagnóstico rodavam outro divisor nas
 * units.
 */
const impose = (b: ValuationInputs, options: { lane?: ValuationLane; everything?: boolean } = {}): ValuationInputs => {
  const everything = options.everything ?? false;
  return b.withOverrides({
    lane: options.lane ?? null,
    terminalReturn: everything ? 0.13 : null,
    growth: everything ? 0.06 : null,
    baseFactor: everything ? 1.1 : null,
    reinvestment: everything ? ReinvestmentPolicy.realGrowth : null,
    cashTiming: everything ? CashTiming.endOfYear : null,
  });
};

const argAfter = (args: readonly string[], flag: string): string | null => {
  const i = args.indexOf(flag);
  return i >= 0 ? (args[i + 1] ?? null) : null;
};

export async function main(args: string[]): Promise<void> {
  const monotonicityOutput = argAfter(args, '--monotonia');
  const levelOnly = argAfter(args, '--nivel');
  const check = args.includes('--conferir') || monotonicityOutput !== null || levelOnly !== null || args.includes('--regravar');
  const traceOnly = argAfter(args, '--rastro');
  // **Regravar sobre a entrada já congelada.** Medir o efeito de uma mudança
  // pede gravar de novo *sem* atualizar cache, Ibovespa e universo — se a
  // entrada se mover junto com o código, a diferença mistura os dois. É o que
  // o `--conferir` já faz para comparar, e o que faltava para quantificar.
  const outputFile = argAfter(args, '--saida') ?? file;
  const rewrite = args.includes('--regravar');

  // **A entrada sai dos pacotes versionados, e não da base bruta.** Os
  // pacotes são o que o aplicativo lê, e vêm no clone: o gabarito passou a
  // reproduzir-se sem os 750 MB da CVM nem o arquivo do Tesouro, que não
  // sobrevivem a uma máquina nova. Antes a curva vinha do CSV do Tesouro e os
  // documentos, da base ingerida — as duas fontes de que o pacote é gerado.
  const curve = TreasuryCurve.at(TreasuryQuotesCodec.decode(readJson<JsonObject>('public/assets/tesouro/curva.json')), today);
  const registry = B3RegistryCodec.decodePackage(readJson<JsonObject>('public/assets/b3/emissores.json'));
  const docs = CvmDocumentCodec.decodePackage(readJson<JsonObject>('public/assets/cvm/documentos.json'));
  const terms = ConcessionTermsCodec.decode(readJson<JsonObject>('public/assets/cvm/outorgas.json'));
  const dividends = CashDividendsCodec.decode(readJson<JsonObject>('public/assets/b3/proventos.json'));
  // O prior do pacote e a composição declarada das units: são o que o
  // aplicativo lê, e por isso é deles que a montagem `aplicativo` parte
  // (itens B11 e B16). O prior **resolvido** sobre a entrada congelada continua
  // na montagem `prior`, que é o diagnóstico.
  const packagePrior = existsSync('public/assets/mercado/beta_prior.json')
    ? BetaPriorCodec.decode(readJson<JsonObject>('public/assets/mercado/beta_prior.json'))
    : null;
  // O prêmio de mercado do pacote (decisão 142): a média de dez anos do
  // prêmio implícito na data do gabarito, que é o que o aplicativo lê. As
  // montagens `doisPontos` e `curva` ficam com os 5,5% parametrizados — são o
  // registro das montagens antigas, e não o aplicativo.
  const premiumPackage = existsSync('public/assets/mercado/premio_implicito.json')
    ? ImpliedPremiumCodec.decode(readJson<JsonObject>('public/assets/mercado/premio_implicito.json'))
    : null;
  const packagePremium = premiumPackage?.normalizedAt(today) ?? null;
  if (packagePremium === null) {
    errln('sem public/assets/mercado/premio_implicito.json utilizável: rode npm run tool -- implied-premium --so-serie');
    process.exitCode = 2;
    return;
  }
  // Os eventos de capital do pacote (itens B28 e B29): a montagem do
  // aplicativo completa o ajuste da série e soma a emissão declarada.
  const capital = existsSync('public/assets/cvm/capital.json')
    ? CapitalEventsCodec.decodePackage(readJson<JsonObject>('public/assets/cvm/capital.json'))
    : new Map<string, CapitalEvents>();
  const units = existsSync('public/assets/cvm/units.json')
    ? UnitCompositionCodec.decodePackage(readJson<JsonObject>('public/assets/cvm/units.json'))
    : new Map<string, UnitComposition[]>();
  // O controle acionário (item B46): a montagem do aplicativo leva a ressalva.
  const control = existsSync('public/assets/cvm/controle.json')
    ? (ShareholderControlHistory.decode(readJson<JsonObject>('public/assets/cvm/controle.json'))?.byIssuer ??
      new Map<string, ShareholderControlPeriod[]>())
    : new Map<string, ShareholderControlPeriod[]>();
  const stateOwned = (t: Ticker): boolean => {
    const p = control.get(t.value.substring(0, 4));
    return p !== undefined && ShareholderControlHistory.at(p, today) === ShareholderControl.state;
  };

  // O rastro de cada avaliação é capturado no fim da transação dela.
  const captured: { event: AuditEvent | null } = { event: null };
  AuditRecorder.attach((e) => {
    captured.event = e;
  });
  // Lido por função: o TypeScript estreitaria a propriedade para `null` logo
  // depois da limpeza, sem saber que a avaliação a preenche.
  const lastEvent = (): AuditEvent | null => captured.event;

  // A gravação parte de uma cópia do cache da validação; a conferência usa a
  // cópia que a gravação deixou.
  mkdirSync(folder, { recursive: true });
  if (!check && traceOnly === null) {
    const origin = `docs/validacao/${ValidationContext.cacheFileName}`;
    if (existsSync(origin)) copyFileSync(origin, cache);
    if (existsSync(ibovespaFile)) unlinkSync(ibovespaFile);
  } else if (!existsSync(cache) || !existsSync(ibovespaFile)) {
    errln(`sem entrada congelada em ${folder} — grave o gabarito antes`);
    AuditRecorder.detach();
    process.exitCode = 2;
    return;
  }
  const ctx0 = ValidationContext.create({ outputDir: 'docs/validacao', cacheFile: cache, frozenCache: true });
  const frozenRun = check || traceOnly !== null;
  const ibov = new FrozenIbovespa(
    frozenRun ? null : ctx0.benchmark,
    frozenRun ? SavedIbovespa.read(readJson<JsonObject>(ibovespaFile)) : new Map(),
  );
  const ctx = { prices: ctx0.prices, fundamentals: ctx0.fundamentals, macro: ctx0.macro, benchmark: ibov as BenchmarkRepository };
  try {
    const anchors = (await ResolveMarketAnchors.call({ macro: ctx.macro, benchmark: ctx.benchmark, asOf: today })).getOrElse(
      MarketAnchors.fallback2026,
    );
    // **O universo também é entrada**, e vem da rede: em 15/09/2026 a fonte
    // passou a listar a EQPA7 e deixou de listar a COCE3, e as duas apareciam
    // como divergência do gabarito sem que o código tivesse mudado. A gravação
    // guarda a lista, e a conferência a repete.
    let wholeUniverse: Ticker[];
    if (!frozenRun) {
      wholeUniverse = (await ctx.fundamentals.universe()).unwrap();
      writeText(universeFile, JSON.stringify(wholeUniverse.map((t) => t.value)));
    } else if (existsSync(universeFile)) {
      wholeUniverse = (JSON.parse(readFileSync(universeFile, 'utf8')) as string[]).map((s) => Ticker.parse(s));
    } else {
      wholeUniverse = (await ctx.fundamentals.universe()).unwrap();
    }
    let universe = wholeUniverse;
    if (traceOnly !== null) universe = universe.filter((t) => t.value === traceOnly);

    const issuer = (t: Ticker): B3Issuer | null => registry.get(t.value.length >= 4 ? t.value.substring(0, 4) : '') ?? null;
    const shareClass = async (t: Ticker): Promise<B3Classification | null> => issuer(t)?.classification ?? null;
    const fromCvm = new CvmFundamentals(ctx.fundamentals, docs, { today });
    const withSector = new OfficialSectorFundamentalsRepository({ inner: fromCvm, classification: shareClass });
    const anchoredWithSector = new OfficialSectorFundamentalsRepository({
      inner: new CvmFundamentals(ctx.fundamentals, docs, { today, anchored: true }),
      classification: shareClass,
    });
    const dividendsOf = (t: Ticker): CashDividend[] => CashDividendsCodec.forTicker(dividends, t.value);

    // O prior sai do universo inteiro, na montagem do aplicativo.
    const prior = await ResolveBetaPrior.call({
      tickers: wholeUniverse,
      prices: ctx.prices,
      fundamentals: withSector,
      benchmark: ctx.benchmark,
      asOf: today,
      dividendsFor: dividendsOf,
    });
    if (prior === null) {
      errln('sem prior do beta: as montagens com prior não valem');
      process.exitCode = 2;
      return;
    }

    const prepare = (
      t: Ticker,
      options: { fundamentals: FundamentalsRepository; c?: YieldCurve | null; app?: boolean; withPrior?: boolean },
    ): Promise<Result<ValuationInputs>> => {
      const app = options.app ?? false;
      const e = issuer(t);
      return PrepareValuationInputs.call({
        ticker: t,
        prices: ctx.prices,
        fundamentals: options.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today,
        marketPremium: app ? packagePremium : CapmInputs.defaultMarketPremium,
        premiumSource: app ? MarketPremiumSource.impliedNormalized : MarketPremiumSource.parameterized,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        riskFreeCurve: options.c ?? null,
        projectionYears: 10,
        officialShares: app && e?.totalShares != null ? new OfficialShareCount({ total: e.totalShares, asOf: e.consultedOn }) : null,
        concessionEnd: app ? (terms.get(t.value)?.end ?? null) : null,
        dividends: app ? dividendsOf(t) : null,
        // A montagem do aplicativo usa o prior **do pacote**, que é o que ele
        // lê; a montagem `prior` usa o resolvido sobre a entrada congelada.
        betaPrior: (options.withPrior ?? false) ? prior : app ? (packagePrior?.prior ?? null) : null,
        declaredSharesPerUnit: app ? (UnitCompositionCodec.at(units.get(t.value) ?? [], today)?.shares ?? null) : null,
        shareEvents: app ? (capital.get(t.value)?.shareEvents ?? []) : [],
        shareIssues: app ? (capital.get(t.value)?.issues ?? []) : [],
        stateControlled: app && stateOwned(t),
      });
    };

    if (levelOnly !== null) {
      AuditRecorder.detach();
      for (const [name, withPrior] of [
        ['aplicativo', false],
        ['prior', true],
      ] as const) {
        const p = await prepare(Ticker.parse(levelOnly), { fundamentals: withSector, c: curve, app: true, withPrior });
        if (p.isErr) continue;
        outln(`== ${levelOnly}, ${name}`);
        openGrid(p.unwrap());
      }
      return;
    }
    if (monotonicityOutput !== null) {
      AuditRecorder.detach();
      await sweepLevel({
        universe,
        output: monotonicityOutput,
        app: (t) => prepare(t, { fundamentals: withSector, c: curve, app: true }),
        prior: (t) => prepare(t, { fundamentals: withSector, c: curve, app: true, withPrior: true }),
      });
      return;
    }

    const traces: Record<string, unknown> = {};
    const evaluate = (i: ValuationInputs, random = false): Serialized => {
      captured.event = null;
      const r = ValuationCascade.evaluate(i, {
        scenarioBuilder: random ? (b) => StochasticScenarios.around(b) : null,
        monteCarloSamples: 300,
      });
      // Pela serialização segura do evento (item D4): um `NaN` no rastro sai
      // como texto, em vez de derrubar a gravação do gabarito.
      const j = lastEvent()?.toJson() ?? null;
      const trace =
        j === null ? null : JSON.stringify({ entrada: j['inputPayload'], saida: j['outputPayload'], calculos: j['calculations'] });
      if (traceOnly !== null) traces[String(Object.keys(traces).length)] = JSON.parse(trace ?? 'null');
      return { ...serialize(r), rastro: trace === null ? null : fingerprint(trace) };
    };

    const output: Record<string, Record<string, unknown>> = {};
    const coverage = new Map<string, number>();
    const account = (k: string): void => {
      coverage.set(k, (coverage.get(k) ?? 0) + 1);
    };
    let n = 0;
    for (const t of universe) {
      if (++n % 25 === 0) process.stderr.write(`  ${n}/${universe.length}   \r`);
      const row: Record<string, unknown> = {};

      const assembly = async (
        name: string,
        prep: Promise<Result<ValuationInputs>>,
        f: (i: ValuationInputs) => Serialized,
      ): Promise<void> => {
        const p = await prep;
        if (p.isErr) {
          row[name] = { preparo: p.failureOrNull!.message };
          return;
        }
        const s = f(p.unwrap());
        row[name] = s;
        const warnings = (s['avisos'] as readonly string[] | undefined) ?? [];
        const has = (fragment: string): boolean => warnings.some((a) => a.includes(fragment));
        if ('recusa' in s) account(`${name}: recusa`);
        if (has('resolvido ano a ano')) account(`${name}: taxas resolvidas`);
        if (has('não sustenta a via')) account(`${name}: estrutura recusada e migrada`);
        if (has('nenhuma das duas vias domina')) account(`${name}: vias mescladas`);
        if (has('migra para o fluxo do acionista')) account(`${name}: migração`);
        if (has('não se estabilizaram')) account(`${name}: veredito sem ponto fixo`);
        if (has('reconstruído do ciclo')) account(`${name}: base reconstruída`);
        if (has('até o fim do contrato')) account(`${name}: terminal do contrato`);
      };

      await assembly('doisPontos', prepare(t, { fundamentals: ctx.fundamentals }), (i) => evaluate(i));
      await assembly('curva', prepare(t, { fundamentals: ctx.fundamentals, c: curve }), (i) => evaluate(i));
      await assembly('aplicativo', prepare(t, { fundamentals: withSector, c: curve, app: true }), (i) => evaluate(i));
      await assembly('ancorada', prepare(t, { fundamentals: anchoredWithSector, c: curve, app: true }), (i) => evaluate(i));
      const withPrior = prepare(t, { fundamentals: withSector, c: curve, app: true, withPrior: true });
      await assembly('prior', withPrior, (i) => evaluate(i));
      await assembly('monteCarlo', withPrior, (i) => evaluate(i, true));
      await assembly('viaFirma', withPrior, (i) => evaluate(impose(i, { lane: ValuationLane.firm })));
      await assembly('viaAcionista', withPrior, (i) => evaluate(impose(i, { lane: ValuationLane.shareholder })));
      await assembly('impostos', withPrior, (i) => evaluate(impose(i, { everything: true })));
      output[t.value] = row;
    }
    errln('');

    if (traceOnly !== null) {
      outln(jsonPretty(traces, ' '));
      return;
    }

    const keys = [...coverage.keys()].sort(compareStr);
    outln('cobertura dos caminhos (ativos por montagem):');
    for (const k of keys) outln(`  ${k.padEnd(44)} ${coverage.get(k)}`);
    const refusals = new Set<string>();
    for (const l of Object.values(output)) {
      for (const m of Object.values(l)) {
        const refusal = (m as Record<string, unknown> | null)?.['recusa'];
        if (typeof refusal === 'string') refusals.add(refusal.replaceAll(/[\d.,]+/g, '#'));
      }
    }
    outln(`  formas distintas de recusa: ${refusals.size}`);

    const text = jsonPretty(output, ' ');
    if (!check) {
      writeText(ibovespaFile, JSON.stringify(ibov.toJson()));
      writeText(file, text);
      outln(`gabarito gravado: ${Object.keys(output).length} ativos em ${file}`);
      return;
    }
    if (rewrite) {
      writeText(outputFile, text);
      outln(`gabarito regravado sobre a entrada congelada: ${Object.keys(output).length} ativos em ${outputFile}`);
      return;
    }

    const saved = readJson<Record<string, Record<string, unknown> | null>>(file);
    const now = JSON.parse(text) as Record<string, Record<string, unknown> | null>;
    const divergent: string[] = [];
    for (const k of new Set([...Object.keys(saved), ...Object.keys(now)])) {
      const g = saved[k] ?? null;
      const a = now[k] ?? null;
      for (const m of new Set([...Object.keys(g ?? {}), ...Object.keys(a ?? {})])) {
        if (JSON.stringify(g?.[m] ?? null) !== JSON.stringify(a?.[m] ?? null)) divergent.push(`${k}/${m}`);
      }
    }
    divergent.sort(compareStr);
    if (divergent.length === 0) {
      outln(`GABARITO IDÊNTICO: ${Object.keys(now).length} ativos, nove montagens cada, saída completa e rastro bit a bit.`);
    } else {
      outln(`GABARITO DIVERGE em ${divergent.length} montagem(ns):`);
      // Por montagem, primeiro: a entrada da CVM não é congelada, e uma
      // reingestão muda a `ancorada` sem que o código tenha mudado.
      const byAssembly = new Map<string, number>();
      for (const k of divergent) {
        const m = k.substring(k.indexOf('/') + 1);
        byAssembly.set(m, (byAssembly.get(m) ?? 0) + 1);
      }
      outln(`  por montagem: ${dartString(byAssembly)}`);
      for (const k of divergent.filter((k) => !k.endsWith('/ancorada'))) outln(`  ${k}`);
      for (const k of divergent.slice(0, 30)) outln(`  ${k}`);
      process.exitCode = 1;
    }
  } finally {
    AuditRecorder.detach();
    await ctx0.dispose();
  }
}

/** Deslocamentos do nível da taxa livre de risco na varredura do B10. */
const grid = Array.from({ length: 25 }, (_, k) => (k - 12) * 0.0025);

/**
 * A varredura do nível da curva (item B10): em cada ativo e montagem, o preço
 * justo ao longo da grade, e se ele sobe quando o capital encarece.
 *
 * **Tolerância de 0,1% do preço de mercado**, a mesma do `reverse-dcf`:
 * variação abaixo disso é ruído de ponto flutuante, e não direção.
 */
async function sweepLevel(args: {
  universe: readonly Ticker[];
  output: string;
  app: (t: Ticker) => Promise<Result<ValuationInputs>>;
  prior: (t: Ticker) => Promise<Result<ValuationInputs>>;
}): Promise<void> {
  const { universe } = args;
  const rows: Record<string, unknown> = {};
  const summary = new Map<string, Map<string, number>>();
  const account = (assembly: string, k: string): void => {
    let m = summary.get(assembly);
    if (m === undefined) summary.set(assembly, (m = new Map()));
    m.set(k, (m.get(k) ?? 0) + 1);
  };

  const status = (v: ValuationResult): string => {
    const warnings = v.warnings.join(' ');
    if (warnings.includes('nenhuma das duas vias domina')) return 'mescla';
    if (warnings.includes('não sustenta a via')) return 'estruturaRecusada';
    if (warnings.includes('migra para o fluxo do acionista')) return 'migrada';
    return v.model.name;
  };

  let n = 0;
  for (const t of universe) {
    if (++n % 25 === 0) process.stderr.write(`  ${n}/${universe.length}   \r`);
    const row: Record<string, unknown> = {};
    for (const [name, prep] of [
      ['aplicativo', args.app],
      ['prior', args.prior],
    ] as const) {
      const p = await prep(t);
      if (p.isErr) continue;
      const base = p.unwrap();
      const r0 = ValuationCascade.evaluate(base);
      if (r0.isErr) continue;
      account(name, 'avaliados na base');
      const price = base.marketPrice;
      const fairValues: (number | null)[] = [];
      const states: (string | null)[] = [];
      for (const d of grid) {
        const r = ValuationCascade.evaluate(base.withRiskFreeShift(d));
        fairValues.push(r.isOk ? r.unwrap().fairValue.reais : null);
        states.push(r.isOk ? status(r.unwrap()) : null);
      }
      // Sobe quando o capital encarece: entre dois pontos avaliados em
      // sequência, o de taxa maior vale mais.
      const tol = price * 1e-3;
      let rises = 0;
      let largestRise = 0.0;
      let previous: number | null = null;
      for (const j of fairValues) {
        if (j === null) {
          previous = null;
          continue;
        }
        if (previous !== null && j - previous > tol) {
          rises++;
          const rel = previous > 0 ? (j - previous) / previous : Number.POSITIVE_INFINITY;
          if (rel > largestRise) largestRise = rel;
        }
        previous = j;
      }
      const evaluated = fairValues.flatMap((v, i) => (v !== null ? [i] : []));
      let gaps = 0;
      if (evaluated.length > 0) {
        for (let i = evaluated[0]!; i <= evaluated[evaluated.length - 1]!; i++) if (fairValues[i] === null) gaps++;
      }
      const lanes = new Set(states.filter((s): s is string => s !== null));
      if (rises > 0) account(name, 'não monótonos');
      if (rises > 0 && lanes.size > 1) account(name, 'não monótonos com troca de via');
      if (lanes.size > 1) account(name, 'trocam de via na grade');
      if (gaps > 0) account(name, 'recusados no meio da grade');
      row[name] = {
        estadoNaBase: status(r0.unwrap()),
        justoNaBase: r0.unwrap().fairValue.reais,
        preco: price,
        subidas: rises,
        maiorSubidaRelativa: Number.isFinite(largestRise) ? largestRise : null,
        lacunas: gaps,
        vias: [...lanes].sort(compareStr),
        justos: fairValues,
      };
    }
    if (Object.keys(row).length > 0) rows[t.value] = row;
  }
  errln('');
  const summaryJson = Object.fromEntries([...summary].map(([k, v]) => [k, Object.fromEntries(v)]));
  writeText(
    args.output,
    jsonPretty({ hoje: today.toIso8601String().substring(0, 10), grade: grid, resumo: summaryJson, ativos: rows }, ' '),
  );
  outln('varredura do nível da curva, de −3 a +3 p.p.:');
  for (const [k, v] of summary) outln(`  ${k}: ${dartString(v)}`);
  outln(`gravado ${args.output}`);
}

/** A grade de um ativo, aberta: o que muda no diagnóstico a cada ponto. */
function openGrid(base: ValuationInputs): void {
  const pc = (x: number | null | undefined): string => (x === null || x === undefined ? '—' : `${(x * 100).toFixed(2)}%`);
  const cut = (a: string): string => (a.length > 150 ? a.substring(0, 150) : a);
  let previousWarnings: string[] | null = null;
  for (const d of grid) {
    const r = ValuationCascade.evaluate(base.withRiskFreeShift(d));
    if (r.isErr) {
      outln(`${pc(d).padStart(7)}  recusa: ${r.failureOrNull!.message}`);
      previousWarnings = null;
      continue;
    }
    const v = r.unwrap();
    const g = v.diagnostics;
    outln(
      `${pc(d).padStart(7)}  R$ ${v.fairValue.reais.toFixed(2).padStart(8)}` +
        `  ${v.model.name.padEnd(12)} desc ${pc(v.discountRate)}` +
        `  g ${pc(g?.growthRate)}  base ${g === null ? 'null' : g.baseFactor.toFixed(3)}` +
        `  moat ${g === null ? 'null' : g.moatApplied}  retido ${pc(g?.terminalRetainedSpread)}` +
        `  rTerm ${pc(g?.terminalReturnOnCapital)}  equity ${pc(g?.equityShare)}` +
        `  ressalvas ${g === null ? 'null' : g.caveats.map((c) => c.key).join(',')}`,
    );
    // Os avisos que entram ou saem de um ponto para o outro: é onde está o
    // degrau, quando há um.
    const warnings = v.warnings.map((a) => a.replaceAll(/[\d.,]+/g, '#'));
    if (previousWarnings !== null) {
      const before = previousWarnings;
      for (const a of warnings.filter((a) => !before.includes(a))) outln(`           + ${cut(a)}`);
      for (const a of before.filter((a) => !warnings.includes(a))) outln(`           - ${cut(a)}`);
    }
    previousWarnings = warnings;
  }
}
