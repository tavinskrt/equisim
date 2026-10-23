import type { Ticker } from '../value-objects/ticker';

/**
 * Setor econômico conforme a taxonomia da fonte de dados.
 *
 * Não é GICS nem a classificação setorial oficial da B3 — é a taxonomia
 * própria do provedor, em português. Deve ser declarado na metodologia.
 */
export class Sector {
  /** Chave estável (ex.: `energia`), usada para agrupar. */
  readonly key: string;

  /** Rótulo de exibição (ex.: `Energia`). */
  readonly label: string;

  /** Declara o setor sem normalizar. Prefira [Sector.fromKey]. */
  constructor(args: { key: string; label: string }) {
    this.key = args.key;
    this.label = args.label;
  }

  /**
   * Normaliza a chave para minúsculas sem espaços nas pontas. Sem [label],
   * usa a chave original aparada — preservando as maiúsculas.
   */
  static fromKey(key: string, options: { label?: string | null } = {}): Sector {
    return new Sector({ key: key.trim().toLowerCase(), label: options.label ?? key.trim() });
  }

  /**
   * Setor ausente. Ativos assim entram na carteira mas ficam **fora** da
   * análise de concentração.
   */
  static readonly unknown = new Sector({ key: '', label: 'Não classificado' });

  /** `true` para [Sector.unknown] e para qualquer setor de chave vazia. */
  get isUnknown(): boolean {
    return this.key.length === 0;
  }

  /** Ordena por [label] — ordem de exibição —, enquanto [equals] compara por [key]. */
  compareTo(other: Sector): number {
    return this.label === other.label ? 0 : this.label < other.label ? -1 : 1;
  }

  equals(other: unknown): boolean {
    return other instanceof Sector && other.key === this.key;
  }

  toString(): string {
    return this.label;
  }
}

/**
 * Ação negociada na B3.
 *
 * **Identidade é o ticker.** Dois `Asset` com o mesmo ticker são o mesmo
 * ativo, ainda que nome e setor divirjam.
 */
export class Asset {
  /** Código de negociação. Identidade da entidade. */
  readonly ticker: Ticker;

  /** Razão social ou nome de pregão, como a fonte informa. */
  readonly name: string;

  /**
   * Setor econômico. Padrão [Sector.unknown] quando o perfil não pôde ser
   * resolvido — o ativo participa da carteira, mas não do alerta de
   * concentração.
   */
  readonly sector: Sector;

  /** Subsetor, quando a fonte o informa. Não participa de cálculo algum. */
  readonly industry: string | null;

  constructor(args: { ticker: Ticker; name: string; sector?: Sector; industry?: string | null }) {
    this.ticker = args.ticker;
    this.name = args.name;
    this.sector = args.sector ?? Sector.unknown;
    this.industry = args.industry ?? null;
  }

  equals(other: unknown): boolean {
    return other instanceof Asset && other.ticker === this.ticker;
  }

  toString(): string {
    return `${this.ticker.value} (${this.name})`;
  }
}
