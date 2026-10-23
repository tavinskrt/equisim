import {
  Asset,
  DateTime,
  FundamentalsSnapshot,
  isJsonObject,
  type JsonObject,
  PricePoint,
  Sector,
  type Ticker,
  tryParseDouble,
} from '../../core';

/**
 * Utilitários de extração tolerante do JSON da brapi.
 *
 * A API varia a forma da resposta entre endpoints — `results` na maioria,
 * `data` aninhado ou plano, ora objeto ora lista. Toda essa irregularidade
 * fica confinada aqui: nada dela atravessa para o domínio.
 */
export const BrapiJson = {
  /** Lista `results` da resposta padrão. */
  results(body: unknown): unknown[] {
    if (isJsonObject(body)) {
      const value = body['results'];
      if (Array.isArray(value)) return value;
    }
    return [];
  },

  /** Primeiro `results[0].data`, aceitando `data` ausente (payload plano). */
  firstData(body: unknown): JsonObject | null {
    const list = BrapiJson.results(body);
    if (list.length === 0) return null;
    const first = list[0];
    if (!isJsonObject(first)) return null;
    const data = first['data'];
    if (isJsonObject(data)) return data;
    return first;
  },

  /** `results[0].data` quando ele é uma **lista** — caso de `mode=history`. */
  firstDataList(body: unknown): unknown[] {
    const list = BrapiJson.results(body);
    if (list.length === 0) return [];
    const first = list[0];
    if (!isJsonObject(first)) return [];
    const data = first['data'];
    return Array.isArray(data) ? data : [];
  },

  /**
   * Extrai um número, aceitando número ou texto.
   *
   * Troca vírgula por ponto antes de converter, porque a fonte alterna entre
   * as duas convenções decimais. Devolve `null` para qualquer outra coisa —
   * **inclusive texto não numérico**, que não lança.
   */
  asDouble(value: unknown): number | null {
    if (typeof value === 'number') return value;
    if (typeof value === 'string') return tryParseDouble(value.replaceAll(',', '.'));
    return null;
  },

  /**
   * Extrai um texto não vazio, já aparado.
   *
   * Devolve `null` para valor ausente, de outro tipo, ou composto só de
   * espaços — o que trata string vazia e ausência como a mesma coisa.
   */
  asString(value: unknown): string | null {
    if (typeof value === 'string' && value.trim().length > 0) return value.trim();
    return null;
  },

  /**
   * Converte epoch em segundos ou string ISO para data sem horário.
   *
   * Aceita inteiro (epoch em **segundos**, não milissegundos) e texto ISO, com
   * ou sem componente de hora. O resultado é sempre truncado para o dia.
   *
   * **O epoch é interpretado como UTC.** Um instante logo após a meia-noite UTC
   * vira o dia anterior em Brasília. É aceitável porque a fonte publica as
   * datas ao meio-dia UTC, longe da virada.
   *
   * Devolve `null` para valor ausente, de outro tipo ou não parseável.
   */
  asDate(value: unknown): DateTime | null {
    if (typeof value === 'number' && Number.isInteger(value)) {
      const dt = DateTime.fromMillisecondsSinceEpoch(value * 1000, { isUtc: true });
      return DateTime.local(dt.year, dt.month, dt.day);
    }
    if (typeof value === 'string' && value.length > 0) {
      const iso = value.includes('T') ? value.split('T')[0]! : value;
      const parsed = DateTime.tryParse(iso);
      if (parsed === null) return null;
      return DateTime.local(parsed.year, parsed.month, parsed.day);
    }
    return null;
  },

  /** Formata a data como `AAAA-MM-DD`, para chave de cache e identidade. */
  isoDay(date: DateTime): string {
    return (
      `${String(date.year).padStart(4, '0')}-` +
      `${String(date.month).padStart(2, '0')}-` +
      `${String(date.day).padStart(2, '0')}`
    );
  },
} as const;

/** Cotação diária vinda de `/v2/stocks/historical`. */
export class BrapiPriceDto {
  /** Dia do pregão, truncado. */
  readonly date: DateTime;
  /** Fechamento ajustado por desdobramento e grupamento. */
  readonly close: number;
  /**
   * Fechamento ajustado também por proventos, como a fonte o publica.
   * **Não usar em cálculo** — o domínio calcula sobre `close`.
   */
  readonly adjustedClose: number | null;
  /** Volume negociado, em quantidade de papéis. Alimenta a Porta 0 (decisão 25). */
  readonly volume: number | null;

  constructor(args: { date: DateTime; close: number; adjustedClose?: number | null; volume?: number | null }) {
    this.date = args.date;
    this.close = args.close;
    this.adjustedClose = args.adjustedClose ?? null;
    this.volume = args.volume ?? null;
  }

  static fromJson(json: JsonObject): BrapiPriceDto | null {
    const date = BrapiJson.asDate(json['date']);
    const close = BrapiJson.asDouble(json['close']);
    if (date === null || close === null || close <= 0) return null;
    return new BrapiPriceDto({
      date,
      close,
      adjustedClose: BrapiJson.asDouble(json['adjustedClose']),
      volume: BrapiJson.asDouble(json['volume']),
    });
  }

  toDomain(): PricePoint {
    return new PricePoint({ date: this.date, close: this.close, adjustedClose: this.adjustedClose, volume: this.volume });
  }
}

/**
 * Fundamentos consolidados de um exercício, montados a partir de quatro
 * endpoints distintos que compartilham a chave `endDate`.
 */
export class BrapiFundamentalsDto {
  /** Encerramento do exercício a que os números se referem. */
  readonly fiscalPeriodEnd: DateTime;

  /**
   * Campos crus do exercício, mesclados dos quatro endpoints da fonte.
   *
   * Mantidos como mapa de propósito: a fonte acrescenta e renomeia campos, e
   * tipar cada um aqui obrigaria a alterar o DTO a cada mudança dela. A
   * tipagem acontece na conversão para o domínio.
   */
  readonly fields: JsonObject;

  constructor(args: { fiscalPeriodEnd: DateTime; fields: JsonObject }) {
    this.fiscalPeriodEnd = args.fiscalPeriodEnd;
    this.fields = args.fields;
  }

  private num(key: string): number | null {
    return BrapiJson.asDouble(this.fields[key]);
  }

  /**
   * A fonte não entrega D&A nem alíquota efetiva; ambas são derivadas no
   * domínio a partir de EBITDA/EBIT e imposto/lucro antes de impostos.
   */
  toDomain(ticker: Ticker): FundamentalsSnapshot {
    const n = (key: string): number | null => this.num(key);
    return new FundamentalsSnapshot({
      ticker,
      fiscalPeriodEnd: this.fiscalPeriodEnd,
      totalRevenue: n('totalRevenue'),
      ebit: n('cleanEbit') ?? n('ebit'),
      ebitda: n('cleanEbitda'),
      netIncome: n('cleanNetIncome') ?? n('netIncome'),
      incomeBeforeTax: n('incomeBeforeTax'),
      incomeTaxExpense: n('incomeTaxExpense'),
      interestExpense: n('interestExpense') ?? n('financialExpenses'),
      earningsPerShare: n('earningsPerShare') ?? n('trailingEps') ?? n('basicEarningsPerShare'),
      cash: n('cash'),
      shortTermInvestments: n('shortTermInvestments'),
      shortTermDebt: n('shortLongTermDebt') ?? n('loansAndFinancing'),
      longTermDebt: n('longTermDebt') ?? n('longTermLoansAndFinancing'),
      totalStockholderEquity: n('totalStockholderEquity') ?? n('shareholdersEquity'),
      bookValuePerShare: n('bookValue'),
      operatingCashFlow: n('operatingCashFlow'),
      investmentCashFlow: n('investmentCashFlow'),
      freeCashFlow: n('freeCashFlow'),
      // A fonte publica NOPAT pronto em 16 dos 18 ativos medidos; ausente só
      // em banco, que não tem EBIT publicado e não chega à via da firma.
      nopat: n('cleanNopat'),
      propertyPlantEquipment: n('propertyPlantEquipment'),
      intangibleAssets: n('intangibleAsset') ?? n('intangibleAssets'),
      // `totalCurrentLiabilities` vem nulo na fonte; o campo preenchido é
      // `currentLiabilities`. Verificado em 16 de 16 exercícios.
      totalCurrentAssets: n('totalCurrentAssets'),
      currentLiabilities: n('currentLiabilities'),
      realizedShareCapital: n('realizedShareCapital') ?? n('commonStock'),
      profitReserves: n('profitReserves'),
      sharesOutstanding: n('sharesOutstanding'),
      sharesOutstandingAsOf: n('sharesOutstandingAsOf'),
      marketCap: n('marketCap'),
      enterpriseToEbitda: n('enterpriseToEbitda'),
      // Os dois termos da ponte (decisão 49). `minorityInterest` é a
      // participação dos não controladores **dentro** do patrimônio
      // consolidado; `equityIncomeResult` é a equivalência patrimonial, que
      // na DRE brasileira entra **acima** do EBIT.
      minorityInterest: n('minorityInterest') ?? n('nonControllingShareholdersEquity'),
      equityIncomeResult: n('equityIncomeResult'),
    });
  }
}

/** Perfil cadastral vindo de `/v2/stocks/profile`. */
export class BrapiProfileDto {
  /** Razão social ou nome de pregão. `null` quando a fonte não o traz. */
  readonly name: string | null;
  /** Chave estável do setor, para agrupar. */
  readonly sectorKey: string | null;
  /** Rótulo de exibição do setor. */
  readonly sectorLabel: string | null;
  /** Subsetor. Não participa de cálculo algum. */
  readonly industry: string | null;

  constructor(
    args: { name?: string | null; sectorKey?: string | null; sectorLabel?: string | null; industry?: string | null } = {},
  ) {
    this.name = args.name ?? null;
    this.sectorKey = args.sectorKey ?? null;
    this.sectorLabel = args.sectorLabel ?? null;
    this.industry = args.industry ?? null;
  }

  static fromJson(json: JsonObject): BrapiProfileDto {
    return new BrapiProfileDto({
      name: BrapiJson.asString(json['longBusinessSummaryName']) ?? BrapiJson.asString(json['name']),
      sectorKey: BrapiJson.asString(json['sectorKey']),
      sectorLabel: BrapiJson.asString(json['sector']) ?? BrapiJson.asString(json['sectorDisp']),
      industry: BrapiJson.asString(json['industry']) ?? BrapiJson.asString(json['industryDisp']),
    });
  }

  /**
   * A taxonomia é própria da brapi, em português — **não é GICS nem a
   * classificação setorial oficial da B3**. Declarar na metodologia.
   */
  toDomain(ticker: Ticker, options: { fallbackName?: string | null } = {}): Asset {
    const key = this.sectorKey;
    return new Asset({
      ticker,
      name: this.name ?? options.fallbackName ?? ticker.value,
      sector: key === null ? Sector.unknown : Sector.fromKey(key, { label: this.sectorLabel ?? key }),
      industry: this.industry,
    });
  }
}
