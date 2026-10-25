import type { DateTime } from '../core';

/**
 * Formatadores compartilhados, na convenção brasileira.
 *
 * **Livres de React**: as ferramentas de `tool/` que escrevem relatório usam
 * os mesmos formatos, e rodam no Node.
 *
 * Existe porque `Number.prototype.toFixed` **ignora o idioma**: ele sempre
 * emite ponto como separador decimal, e a convenção brasileira pede vírgula —
 * `14,41%`, e não `14.41%`. `Intl.NumberFormat` resolve o separador e o
 * agrupamento de milhar pela especificação ECMA-402.
 */

const decimalFormats = new Map<number, Intl.NumberFormat>();

/** O formatador decimal de [digits] casas, construído uma vez. */
function decimal(digits: number): Intl.NumberFormat {
  let f = decimalFormats.get(digits);
  if (f === undefined) {
    f = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: digits, maximumFractionDigits: digits });
    decimalFormats.set(digits, f);
  }
  return f;
}

const currency = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });

const pad = (n: number, width = 2) => String(n).padStart(width, '0');

export const Fmt = {
  /**
   * Formata um valor **em reais** — não em centavos: `R$ 1.234,56`.
   *
   * Converta com `Money.reais` antes de chamar; passar centavos produz um
   * número cem vezes maior sem qualquer aviso. Valor não finito vira `—`.
   */
  money(value: number): string {
    return Number.isFinite(value) ? currency.format(value) : '—';
  },

  /**
   * Percentual a partir de fração, com sinal explícito quando pedido.
   *
   * - [fraction]: valor em fração (`0.155` vira `15,50%`).
   * - [decimals]: casas decimais. Padrão `2`.
   * - [signed]: prefixa `+` nos positivos. Negativos já trazem o próprio
   *   sinal; o zero nunca recebe prefixo.
   *
   * Valor não finito vira `—`: exibir `NaN` ou `∞` ao investidor é pior que
   * admitir a ausência do dado.
   */
  percent(fraction: number, options: { decimals?: number; signed?: boolean } = {}): string {
    const value = fraction * 100;
    if (!Number.isFinite(value)) return '—';
    const sign = options.signed === true && value > 0 ? '+' : '';
    return `${sign}${decimal(options.decimals ?? 2).format(value)}%`;
  },

  /** Peso de carteira: percentual com duas casas (`0.25` vira `25,00%`). */
  weight(fraction: number): string {
    return Fmt.percent(fraction, { decimals: 2 });
  },

  /** Número adimensional — múltiplo, beta, índice de Sharpe. */
  ratio(value: number, decimals = 2): string {
    return Number.isFinite(value) ? decimal(decimals).format(value) : '—';
  },

  /**
   * Diferença entre duas taxas, em **pontos percentuais**, com sinal.
   * [points] já chega na unidade final: `3.5` vira `+3,5 p.p.`.
   */
  points(points: number, decimals = 1): string {
    if (!Number.isFinite(points)) return '—';
    const sign = points >= 0 ? '+' : '';
    return `${sign}${Fmt.ratio(points, decimals)} p.p.`;
  },

  /** Prazo em meses, por extenso: `120` vira `10 anos e 0 meses`. */
  months(months: number): string {
    return `${Math.trunc(months / 12)} anos e ${months % 12} meses`;
  },

  /** Data por extenso: `31/12/2026`. */
  date(d: DateTime): string {
    return `${pad(d.day)}/${pad(d.month)}/${d.year}`;
  },

  /** Data curta para eixo temporal: `12/26`. */
  shortDate(d: DateTime): string {
    return `${pad(d.month)}/${pad(d.year % 100)}`;
  },

  /** Data e hora: `31/12/2026 14:05`. */
  dateTime(d: DateTime): string {
    return `${Fmt.date(d)} ${pad(d.hour)}:${pad(d.minute)}`;
  },

  /** Hora: `14:05`. */
  time(d: DateTime): string {
    return `${pad(d.hour)}:${pad(d.minute)}`;
  },

  /** Reais em milhões, com o sinal tipográfico: `−R$ 1.234,5 mi`. */
  millions(v: number): string {
    return `${v < 0 ? '−' : ''}R$ ${Fmt.ratio(Math.abs(v) / 1e6, 1)} mi`;
  },

  /** Valor compacto para eixo: `R$ 1,2 mi`, `R$ 350 mil`. */
  compactMoney(v: number): string {
    const abs = Math.abs(v);
    const sign = v < 0 ? '−' : '';
    if (abs >= 1e9) return `${sign}R$ ${Fmt.ratio(abs / 1e9, 1)} bi`;
    if (abs >= 1e6) return `${sign}R$ ${Fmt.ratio(abs / 1e6, 1)} mi`;
    if (abs >= 1e3) return `${sign}R$ ${Fmt.ratio(abs / 1e3, 0)} mil`;
    return `${sign}R$ ${Fmt.ratio(abs, 0)}`;
  },
} as const;

/**
 * Vocabulário das grandezas que atravessam mais de uma tela.
 *
 * Existe porque **rótulo é contrato com o leitor**: a mesma rentabilidade
 * exigida com dois nomes em duas telas vira, para quem lê, duas grandezas.
 */
export const Lexicon = {
  /** Rentabilidade que o plano patrimonial exige, ao ano. */
  required: 'Exigido',
  /** Ressalva de [required]: a taxa sem a base é ambígua. */
  requiredPerYear: 'ao ano',
  /** Retorno que a avaliação implica — projeção, não evidência. */
  expected: 'Esperado da carteira',
  /** Retorno que o histórico entregou — evidência, não projeção. */
  realized: 'Realizado',
  /** Ressalva de [realized]: nomeia o indicador do painel. */
  realizedXirr: 'XIRR, ao ano',
  /** Distância entre o que se espera (ou se obteve) e o que se exige. */
  margin: 'Folga',
} as const;

/** Sentido de um número para a cor: ganho, perda, alerta ou neutro. */
export type Trend = 'positive' | 'negative' | 'caution' | 'neutral';

/** O sentido de um valor com sinal: positivo é ganho, negativo é perda. */
export function trendOf(value: number | null | undefined): Trend {
  if (value === null || value === undefined || !Number.isFinite(value) || value === 0) return 'neutral';
  return value > 0 ? 'positive' : 'negative';
}
