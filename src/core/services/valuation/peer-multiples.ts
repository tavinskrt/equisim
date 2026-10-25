/** Triangulação por múltiplos de pares, ao lado do fluxo descontado. */

import type { FundamentalsSnapshot } from '../../entities/fundamentals';
import { DartEnum, type WireKeyed } from '../../lang/dart-enum';
import { DateTime } from '../../lang/date-time';
import { sortedNums } from '../../lang/iter';
import { asDouble, asInt, asString, isJsonObject, type JsonObject } from '../../lang/json';
import { FinancialSectors } from './financial-sectors';

/** Qual múltiplo produziu uma leitura. */
export class MultipleKind extends DartEnum implements WireKeyed {
  readonly wireKeyed = true as const;

  /** Preço sobre lucro por ação. */
  static readonly priceToEarnings = new MultipleKind('priceToEarnings', 0, 'precoLucro');

  /** Preço sobre valor patrimonial por ação. */
  static readonly priceToBook = new MultipleKind('priceToBook', 1, 'precoPatrimonio');

  /** Valor da firma sobre EBITDA. */
  static readonly evToEbitda = new MultipleKind('evToEbitda', 2, 'firmaEbitda');

  static readonly values: readonly MultipleKind[] = [
    MultipleKind.priceToEarnings,
    MultipleKind.priceToBook,
    MultipleKind.evToEbitda,
  ];

  /** Chave gravada nas saídas. É dado, e não nome de código. */
  readonly key: string;

  private constructor(name: string, index: number, key: string) {
    super(name, index);
    this.key = key;
  }

  protected get typeName(): string {
    return 'MultipleKind';
  }
}

/** Por que um múltiplo não se aplicou a um ativo. */
export class MultipleRefusal extends DartEnum implements WireKeyed {
  readonly wireKeyed = true as const;

  /** O grupo de pares não tem observações suficientes. */
  static readonly insufficientPeers = new MultipleRefusal('insufficientPeers', 0, 'paresInsuficientes');

  /** A grandeza de baixo não é positiva — lucro, patrimônio ou EBITDA. */
  static readonly nonPositiveBase = new MultipleRefusal('nonPositiveBase', 1, 'baseNaoPositiva');

  /** A grandeza de baixo não está publicada. */
  static readonly missingBase = new MultipleRefusal('missingBase', 2, 'baseAusente');

  /** EBITDA de instituição financeira não descreve geração operacional. */
  static readonly financialInstitution = new MultipleRefusal('financialInstitution', 3, 'instituicaoFinanceira');

  /** A ponte de dívida líquida não fecha em valor positivo do acionista. */
  static readonly nonPositiveBridge = new MultipleRefusal('nonPositiveBridge', 4, 'ponteNaoPositiva');

  static readonly values: readonly MultipleRefusal[] = [
    MultipleRefusal.insufficientPeers,
    MultipleRefusal.nonPositiveBase,
    MultipleRefusal.missingBase,
    MultipleRefusal.financialInstitution,
    MultipleRefusal.nonPositiveBridge,
  ];

  /** Chave gravada nas saídas. É dado, e não nome de código. */
  readonly key: string;

  private constructor(name: string, index: number, key: string) {
    super(name, index);
    this.key = key;
  }

  protected get typeName(): string {
    return 'MultipleRefusal';
  }
}

/** A mediana de um múltiplo num grupo de pares, com o tamanho do grupo. */
export class PeerMultiple {
  /** Mediana do múltiplo entre os pares. */
  readonly median: number;

  /** Quantos pares entraram na mediana. */
  readonly peers: number;

  /** Chave do grupo que produziu a mediana — subsetor, setor ou `mercado`. */
  readonly group: string;

  constructor(args: { median: number; peers: number; group: string }) {
    this.median = args.median;
    this.peers = args.peers;
    this.group = args.group;
  }
}

/**
 * O conjunto de medianas setoriais que a triangulação consome. **O núcleo não
 * sabe calcular isto**, e é deliberado: a mediana é do universo, e o núcleo
 * avalia um ativo por vez.
 */
export class PeerMultipleSet {
  /** Medianas por múltiplo. */
  readonly byKind: ReadonlyMap<MultipleKind, PeerMultiple>;

  /** Data em que as medianas foram apuradas. */
  readonly asOf: DateTime;

  constructor(args: { byKind: ReadonlyMap<MultipleKind, PeerMultiple>; asOf: DateTime }) {
    this.byKind = args.byKind;
    this.asOf = args.asOf;
  }

  /** `true` quando não há múltiplo algum a aplicar. */
  get isEmpty(): boolean {
    return this.byKind.size === 0;
  }
}

/** Uma leitura por múltiplo: o preço justo que ela implica, ou a recusa. */
export class MultipleReading {
  /** Qual múltiplo. */
  readonly kind: MultipleKind;

  /** Preço justo por papel implicado, em reais. `null` quando recusado. */
  readonly fairValuePerShare: number | null;

  /** A mediana usada. `null` quando não havia grupo. */
  readonly peer: PeerMultiple | null;

  /** Por que não se aplicou. `null` quando se aplicou. */
  readonly refusal: MultipleRefusal | null;

  constructor(args: {
    kind: MultipleKind;
    fairValuePerShare?: number | null;
    peer?: PeerMultiple | null;
    refusal?: MultipleRefusal | null;
  }) {
    this.kind = args.kind;
    this.fairValuePerShare = args.fairValuePerShare ?? null;
    this.peer = args.peer ?? null;
    this.refusal = args.refusal ?? null;
  }

  /** `true` quando a leitura produziu preço. */
  get applied(): boolean {
    return this.fairValuePerShare !== null;
  }
}

interface ReadingArgs {
  latest: FundamentalsSnapshot;
  shares: number;
  peers: PeerMultipleSet;
  sectorKey?: string | null;
  industry?: string | null;
}

function single(kind: MultipleKind, args: ReadingArgs): MultipleReading {
  const { latest, shares, peers } = args;
  const refusal = (r: MultipleRefusal, p: PeerMultiple | null = null): MultipleReading =>
    new MultipleReading({ kind, refusal: r, peer: p });

  const financial = FinancialSectors.isFinancial({ sectorKey: args.sectorKey ?? null, industry: args.industry ?? null });
  if (kind === MultipleKind.evToEbitda && financial) {
    return refusal(MultipleRefusal.financialInstitution);
  }

  const p = peers.byKind.get(kind) ?? null;
  if (p === null || p.peers < PeerValuation.minimumPeers || !Number.isFinite(p.median)) {
    return refusal(MultipleRefusal.insufficientPeers, p);
  }
  if (p.median <= 0) return refusal(MultipleRefusal.nonPositiveBase, p);
  if (shares <= 0 || !Number.isFinite(shares)) {
    return refusal(MultipleRefusal.missingBase, p);
  }

  if (kind === MultipleKind.priceToEarnings) {
    const profit = latest.netIncome;
    if (profit === null) return refusal(MultipleRefusal.missingBase, p);
    if (profit <= 0) return refusal(MultipleRefusal.nonPositiveBase, p);
    // **Pelo lucro total dividido pelo divisor**, e não pelo `LPA` da fonte:
    // o `LPA` publicado usa a contagem da companhia, e a ponte já arbitrou
    // outra.
    return new MultipleReading({ kind, fairValuePerShare: (p.median * profit) / shares, peer: p });
  }
  if (kind === MultipleKind.priceToBook) {
    const pl = latest.totalStockholderEquity;
    if (pl === null) return refusal(MultipleRefusal.missingBase, p);
    if (pl <= 0) return refusal(MultipleRefusal.nonPositiveBase, p);
    return new MultipleReading({ kind, fairValuePerShare: (p.median * pl) / shares, peer: p });
  }
  const ebitda = latest.ebitda;
  if (ebitda === null) return refusal(MultipleRefusal.missingBase, p);
  if (ebitda <= 0) return refusal(MultipleRefusal.nonPositiveBase, p);
  // O valor da firma vira valor do acionista pela **mesma ponte** do DCF:
  // menos a dívida líquida. Caixa líquido soma, e é legítimo.
  const equity = p.median * ebitda - latest.netDebt;
  if (equity <= 0) {
    return refusal(MultipleRefusal.nonPositiveBridge, p);
  }
  return new MultipleReading({ kind, fairValuePerShare: equity / shares, peer: p });
}

/**
 * A triangulação por múltiplos de pares. **É segunda leitura, e não é preço**
 * (decisão 103): a divergência é declarada, e não reconciliada.
 */
export const PeerValuation = {
  /** Distância a partir da qual a divergência vira ressalva. **Meia ordem de grandeza.** */
  divergenceLimit: 0.5,

  /** Mínimo de pares — outras companhias (item B41) — para a mediana ser usável. */
  minimumPeers: 5,

  /**
   * As três leituras. [shares] é o **divisor da ponte** (decisão 83);
   * [sectorKey] e [industry] desligam `EV/EBITDA` em instituição financeira.
   */
  readings(args: ReadingArgs): MultipleReading[] {
    const out: MultipleReading[] = [];
    for (const kind of MultipleKind.values) out.push(single(kind, args));
    return out;
  },

  /** A leitura consolidada: a **mediana** das que se aplicaram. */
  consolidated(readings: readonly MultipleReading[]): number | null {
    const v = sortedNums(readings.filter((r) => r.fairValuePerShare !== null).map((r) => r.fairValuePerShare!));
    if (v.length === 0) return null;
    const mid = Math.floor(v.length / 2);
    return v.length % 2 === 1 ? v[mid]! : (v[mid - 1]! + v[mid]!) / 2;
  },

  /** `múltiplos ÷ DCF − 1`, ou `null` sem leitura aplicável ou com DCF não positivo. */
  divergence(args: { readings: readonly MultipleReading[]; dcfFairValue: number }): number | null {
    const m = PeerValuation.consolidated(args.readings);
    if (m === null || args.dcfFairValue <= 0 || !Number.isFinite(args.dcfFairValue)) return null;
    return m / args.dcfFairValue - 1;
  },
};

/** A triangulação inteira, como ela chega ao resultado da avaliação. */
export class PeerTriangulation {
  /** As três leituras, aplicadas ou recusadas. */
  readonly readings: readonly MultipleReading[];

  /** A mediana das aplicadas, em reais por papel. */
  readonly consolidated: number | null;

  /** `múltiplos ÷ DCF − 1`. */
  readonly divergence: number | null;

  /** Data em que as medianas de pares foram apuradas. */
  readonly asOf: DateTime;

  constructor(args: {
    readings: readonly MultipleReading[];
    consolidated: number | null;
    divergence: number | null;
    asOf: DateTime;
  }) {
    this.readings = args.readings;
    this.consolidated = args.consolidated;
    this.divergence = args.divergence;
    this.asOf = args.asOf;
  }

  /** Quantas leituras produziram preço. */
  get applied(): number {
    return this.readings.filter((r) => r.applied).length;
  }

  /** `true` quando a divergência passa do limite declarado. */
  get diverges(): boolean {
    return this.divergence !== null && Math.abs(this.divergence) > PeerValuation.divergenceLimit;
  }

  /** Monta a triangulação, ou devolve `null` quando não há pacote de pares. */
  static build(args: {
    latest: FundamentalsSnapshot;
    shares: number;
    peers: PeerMultipleSet | null;
    dcfFairValue: number;
    sectorKey?: string | null;
    industry?: string | null;
  }): PeerTriangulation | null {
    const peers = args.peers;
    if (peers === null || peers.isEmpty) return null;
    const rs = PeerValuation.readings({
      latest: args.latest,
      shares: args.shares,
      peers,
      sectorKey: args.sectorKey ?? null,
      industry: args.industry ?? null,
    });
    return new PeerTriangulation({
      readings: rs,
      consolidated: PeerValuation.consolidated(rs),
      divergence: PeerValuation.divergence({ readings: rs, dcfFairValue: args.dcfFairValue }),
      asOf: peers.asOf,
    });
  }
}

/**
 * Leitura do pacote versionado de medianas setoriais. **Fica no núcleo**
 * porque o formato é do contrato entre quem grava e quem lê.
 */
export const PeerMultipleCodec = {
  /** O pacote inteiro, indexado por ticker. Pacote ilegível devolve mapa vazio. */
  decode(json: JsonObject): Map<string, PeerMultipleSet> {
    const byTicker = json['porTicker'];
    if (!isJsonObject(byTicker)) return new Map();
    const date = DateTime.tryParse(asString(json['geradoEm']) ?? '');
    if (date === null) return new Map();

    const out = new Map<string, PeerMultipleSet>();
    for (const [ticker, v] of Object.entries(byTicker)) {
      if (!isJsonObject(v)) continue;
      const byKind = new Map<MultipleKind, PeerMultiple>();
      for (const k of MultipleKind.values) {
        const m = v[k.key];
        if (!isJsonObject(m)) continue;
        const median = asDouble(m['mediana']);
        const pairs = asInt(m['pares']);
        const group = asString(m['grupo']);
        if (median === null || pairs === null || group === null) continue;
        if (!Number.isFinite(median) || median <= 0) continue;
        byKind.set(k, new PeerMultiple({ median, peers: pairs, group }));
      }
      if (byKind.size > 0) {
        out.set(ticker, new PeerMultipleSet({ byKind, asOf: date }));
      }
    }
    return out;
  },
};
