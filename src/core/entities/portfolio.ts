import { DartEnum, type WireKeyed } from '../lang/dart-enum';
import { InvalidInput } from '../failures/failure';
import { err, ok, type Result } from '../failures/result';
import type { Ticker } from '../value-objects/ticker';
import { Weight, Weights } from '../value-objects/weight';
import type { Asset, Sector } from './asset';

/** Papel da carteira na dupla gestão. */
export class PortfolioKind extends DartEnum implements WireKeyed {
  readonly wireKeyed = true as const;

  /** Portfólio vigente. */
  static readonly principal = new PortfolioKind('principal', 0, 'principal');

  /** Candidatos a substituição. */
  static readonly reserve = new PortfolioKind('reserve', 1, 'reserva');

  static readonly values: readonly PortfolioKind[] = [PortfolioKind.principal, PortfolioKind.reserve];

  /**
   * Chave gravada nas saídas — pacote de dados, rastro de auditoria,
   * relatório. É dado, e não nome de código: renomear o valor não a muda.
   */
  readonly key: string;

  private constructor(name: string, index: number, key: string) {
    super(name, index);
    this.key = key;
  }

  protected get typeName(): string {
    return 'PortfolioKind';
  }
}

/**
 * Posição de um ativo dentro da carteira.
 *
 * A carteira é definida por **pesos**, não por lotes: o peso é o que o
 * usuário estipula, e a contagem de ações é resultado da simulação, não
 * entrada dela — `PortfolioBacktest` converte cada fatia de aporte em ações
 * inteiras ao preço do dia.
 */
export class PortfolioEntry {
  /** Ativo posicionado. */
  readonly asset: Asset;

  /**
   * Peso **estipulado** na constituição, não o peso corrente de mercado. A
   * deriva entre os dois é apurada pelo backtest, não guardada aqui.
   */
  readonly weight: Weight;

  constructor(args: { asset: Asset; weight: Weight }) {
    this.asset = args.asset;
    this.weight = args.weight;
  }

  /** Atalho para `asset.ticker` — é por ele que a carteira indexa. */
  get ticker(): Ticker {
    return this.asset.ticker;
  }

  /** Atalho para `asset.sector`, usado pela análise de concentração. */
  get sector(): Sector {
    return this.asset.sector;
  }

  /** Devolve uma cópia com outro peso, preservando o ativo. */
  withWeight(w: Weight): PortfolioEntry {
    return new PortfolioEntry({ asset: this.asset, weight: w });
  }
}

/**
 * Carteira de ações com pesos estipulados.
 *
 * **Não há rebalanceamento**: os pesos definem a alocação de cada aporte, mas
 * nunca são restaurados depois. Os pesos correntes derivam com o mercado, e
 * essa deriva é informação útil — não defeito a corrigir.
 */
export class Portfolio {
  /** Identificador estável, usado para persistir e correlacionar. */
  readonly id: string;

  /** Nome de exibição, editável pelo usuário. */
  readonly name: string;

  /** Papel na dupla gestão: Principal ou Reserva. */
  readonly kind: PortfolioKind;

  /**
   * Posições indexadas por ativo. **Imutável** — todo método de alteração
   * devolve uma carteira nova.
   */
  readonly entries: ReadonlyMap<Ticker, PortfolioEntry>;

  /**
   * Teto de ativos por carteira.
   *
   * **É regra de produto, e por isso mora aqui** (decisão 59). A ferramenta
   * estuda carteira concentrada: acima de quinze ativos o alerta de
   * concentração setorial deixa de discriminar e a comparação entre Principal
   * e Reserva perde o sentido de "duas teses". **A interface só exibe o
   * contador**, e quem recusa o décimo sexto ativo são as fábricas daqui.
   */
  static readonly maxAssets = 15;

  /**
   * Constrói a carteira congelando o mapa de posições.
   *
   * **Não valida** teto de ativos nem soma de pesos — quem valida são as
   * fábricas [Portfolio.equalWeighted], que devolvem [Result].
   */
  constructor(args: {
    id: string;
    name: string;
    kind: PortfolioKind;
    entries: ReadonlyMap<Ticker, PortfolioEntry>;
  }) {
    this.id = args.id;
    this.name = args.name;
    this.kind = args.kind;
    this.entries = new Map(args.entries);
  }

  /** `true` quando não há nenhum ativo. */
  get isEmpty(): boolean {
    return this.entries.size === 0;
  }

  /** Quantidade de ativos. Limitada a [maxAssets] pelas fábricas. */
  get length(): number {
    return this.entries.size;
  }

  /**
   * Ativos em ordem alfabética.
   *
   * A ordenação é o que torna determinístico o resultado de [Weights.equal],
   * que absorve o resíduo no primeiro elemento.
   */
  get tickers(): Ticker[] {
    return [...this.entries.keys()].sort((a, b) => a.compareTo(b));
  }

  /** Pesos estipulados, em ordem de iteração do mapa. */
  get weights(): Weight[] {
    return [...this.entries.values()].map((e) => e.weight);
  }

  /**
   * `true` quando os pesos somam 100% dentro da tolerância de
   * [Weights.sumsToOne]. Uma carteira vazia é inválida por este critério.
   */
  get hasValidWeights(): boolean {
    return Weights.sumsToOne(this.weights);
  }

  /**
   * Cria uma carteira equiponderada, validando o teto de ativos.
   *
   * Devolve [InvalidInput] para lista vazia, para mais de [maxAssets] ativos,
   * ou quando dois ativos compartilham o mesmo ticker.
   */
  static equalWeighted(args: {
    id: string;
    name: string;
    kind: PortfolioKind;
    assets: readonly Asset[];
  }): Result<Portfolio> {
    const { assets } = args;
    if (assets.length === 0) {
      return err(new InvalidInput('A carteira precisa de ao menos um ativo.'));
    }
    if (assets.length > Portfolio.maxAssets) {
      return err(
        new InvalidInput(
          `Limite de ${Portfolio.maxAssets} ativos por carteira excedido ` + `(${assets.length} informados).`,
        ),
      );
    }
    const duplicates = new Set<Ticker>();
    for (const a of assets) {
      if (duplicates.has(a.ticker)) {
        return err(new InvalidInput(`Ativo duplicado: ${a.ticker.toString()}`));
      }
      duplicates.add(a.ticker);
    }

    const byTicker = new Map<Ticker, Asset>();
    for (const a of assets) byTicker.set(a.ticker, a);
    const weights = Weights.equal(assets.map((a) => a.ticker));
    const entries = new Map<Ticker, PortfolioEntry>();
    for (const [key, value] of weights) {
      entries.set(key, new PortfolioEntry({ asset: byTicker.get(key)!, weight: value }));
    }
    return ok(new Portfolio({ id: args.id, name: args.name, kind: args.kind, entries }));
  }

  /**
   * Redistribui os pesos igualmente entre os ativos atuais. Devolve uma
   * carteira nova; a original permanece intacta.
   */
  equalize(): Portfolio {
    const weights = Weights.equal(this.tickers);
    const entries = new Map<Ticker, PortfolioEntry>();
    for (const [key, value] of this.entries) entries.set(key, value.withWeight(weights.get(key)!));
    return new Portfolio({ id: this.id, name: this.name, kind: this.kind, entries });
  }

  /**
   * Remove um ativo e reequipondera o restante.
   *
   * Devolve [InvalidInput] se o ativo não estiver na carteira. Remover o
   * último ativo devolve uma carteira **vazia**, não uma falha. A
   * reequiponderação **descarta os pesos customizados**.
   */
  remove(ticker: Ticker): Result<Portfolio> {
    if (!this.entries.has(ticker)) {
      return err(new InvalidInput(`Ativo ${ticker.toString()} não está na carteira.`));
    }
    const remaining = new Map(this.entries);
    remaining.delete(ticker);
    if (remaining.size === 0) {
      return ok(new Portfolio({ id: this.id, name: this.name, kind: this.kind, entries: new Map() }));
    }
    const weights = Weights.equal([...remaining.keys()].sort((a, b) => a.compareTo(b)));
    const entries = new Map<Ticker, PortfolioEntry>();
    for (const [key, value] of remaining) entries.set(key, value.withWeight(weights.get(key)!));
    return ok(new Portfolio({ id: this.id, name: this.name, kind: this.kind, entries }));
  }

  /**
   * Adiciona um ativo e reequipondera.
   *
   * Devolve [InvalidInput] se o ativo já estiver presente ou se a carteira já
   * tiver [maxAssets] ativos. Como [remove], **descarta pesos customizados**.
   */
  add(asset: Asset): Result<Portfolio> {
    if (this.entries.has(asset.ticker)) {
      return err(new InvalidInput(`${asset.ticker.toString()} já está na carteira.`));
    }
    if (this.entries.size >= Portfolio.maxAssets) {
      return err(new InvalidInput(`Limite de ${Portfolio.maxAssets} ativos por carteira atingido.`));
    }
    const updated = new Map(this.entries);
    updated.set(asset.ticker, new PortfolioEntry({ asset, weight: Weight.zero }));
    const weights = Weights.equal([...updated.keys()].sort((a, b) => a.compareTo(b)));
    const entries = new Map<Ticker, PortfolioEntry>();
    for (const [key, value] of updated) entries.set(key, value.withWeight(weights.get(key)!));
    return ok(new Portfolio({ id: this.id, name: this.name, kind: this.kind, entries }));
  }
}
