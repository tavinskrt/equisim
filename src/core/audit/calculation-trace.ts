import { DartEnum, isWireKeyed } from '../lang/dart-enum';
import { DateTime } from '../lang/date-time';
import { str } from '../lang/num';

/** Mapa de chaves texto — o `Map<String, dynamic>` do Dart. */
export type JsonMap = Record<string, unknown>;

/**
 * O que o JSON não representa, convertido em algo que ele representa.
 *
 * **Por que existe** (item D4). O rastro é serializado em dois lugares — a
 * mensagem entre janelas do painel e o arquivo exportado —, e a serialização
 * **lança** diante de `NaN`, de infinito e de qualquer objeto que não seja
 * mapa, lista, texto, número ou booleano. Aqui ele vira texto legível, e o
 * resto passa intacto — o JSON de um rastro sem valor degenerado não muda um
 * byte.
 */
export const AuditJson = {
  /**
   * Cópia de [value] que a serialização aceita sempre.
   *
   * - `NaN`, `Infinity` e `-Infinity` viram os textos de mesmo nome;
   * - data vira ISO-8601, enum vira a chave gravada ou o nome, e qualquer
   *   outro objeto vira o `toString()` dele;
   * - mapas e listas são percorridos, com as chaves convertidas em texto.
   */
  safe(value: unknown): unknown {
    if (value === null || value === undefined) return null;
    if (typeof value === 'boolean' || typeof value === 'string') return value;
    if (typeof value === 'number') {
      if (Number.isFinite(value)) return value;
      if (Number.isNaN(value)) return 'NaN';
      return value > 0 ? 'Infinity' : '-Infinity';
    }
    if (value instanceof Map) {
      const out: JsonMap = {};
      for (const [k, v] of value) out[keyText(k)] = AuditJson.safe(v);
      return out;
    }
    if (Array.isArray(value) || value instanceof Set) {
      return [...(value as Iterable<unknown>)].map((v) => AuditJson.safe(v));
    }
    if (value instanceof DateTime) return value.toIso8601String();
    if (isWireKeyed(value)) return value.key;
    if (value instanceof DartEnum) return value.name;
    if (isPlainObject(value)) {
      const out: JsonMap = {};
      for (const [k, v] of Object.entries(value)) out[k] = AuditJson.safe(v);
      return out;
    }
    return String(value);
  },

  /** Mapa de chaves texto, pela mesma regra de [safe]. */
  safeMap(value: JsonMap): JsonMap {
    return AuditJson.safe(value) as JsonMap;
  },

  /**
   * Número de um campo do JSON, aceitando os textos que [safe] produz.
   * Devolve `null` para ausente e para o que não é número.
   */
  number(value: unknown): number | null {
    if (typeof value === 'number') return value;
    switch (value) {
      case 'NaN':
        return NaN;
      case 'Infinity':
        return Infinity;
      case '-Infinity':
        return -Infinity;
      default:
        return null;
    }
  },
};

function keyText(k: unknown): string {
  if (typeof k === 'string') return k;
  if (typeof k === 'number') return str(k);
  return String(k);
}

function isPlainObject(value: unknown): value is JsonMap {
  if (typeof value !== 'object' || value === null) return false;
  const proto = Object.getPrototypeOf(value) as unknown;
  return proto === Object.prototype || proto === null;
}

/** Leitura tolerante de texto: o `as String?` do Dart, que vira `null` se não for texto. */
function asString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

/** Leitura tolerante de booleano. */
function asBool(value: unknown): boolean | null {
  return typeof value === 'boolean' ? value : null;
}

/** Leitura tolerante de mapa, com as chaves convertidas em texto. */
function asMap(value: unknown): JsonMap | null {
  if (value instanceof Map) {
    const out: JsonMap = {};
    for (const [k, v] of value) out[keyText(k)] = v;
    return out;
  }
  if (typeof value === 'object' && value !== null && !Array.isArray(value)) return value as JsonMap;
  return null;
}

/** Interpolação `'$x'` do Dart para um valor qualquer vindo do JSON. */
function interpolate(value: unknown): string {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'number') return str(value);
  if (typeof value === 'string') return value;
  if (Array.isArray(value)) return `[${value.map(interpolate).join(', ')}]`;
  if (typeof value === 'object') {
    const entries = Object.entries(value as JsonMap).map(([k, v]) => `${k}: ${interpolate(v)}`);
    return `{${entries.join(', ')}}`;
  }
  return String(value);
}

/** Um ponto da amostra que sustenta um cálculo agregado. */
export class TraceSamplePoint {
  /** Rótulo do período — o ano fiscal, tipicamente. */
  readonly label: string;

  /** Valor do período, na unidade do cálculo que a amostra sustenta. */
  readonly value: number;

  /**
   * `true` quando o ponto é um dos que **definem** a estatística resumo:
   * o central numa mediana de amostra ímpar, os dois centrais numa par.
   */
  readonly definesResult: boolean;

  /** `true` para o período observado, o que a fórmula trata. */
  readonly isObserved: boolean;

  constructor(args: { label: string; value: number; definesResult?: boolean; isObserved?: boolean }) {
    this.label = args.label;
    this.value = args.value;
    this.definesResult = args.definesResult ?? false;
    this.isObserved = args.isObserved ?? false;
  }

  /** Serializa para o formato consumido pela página de logs e pela exportação. */
  toJson(): JsonMap {
    return {
      label: this.label,
      value: AuditJson.safe(this.value),
      definesResult: this.definesResult,
      isObserved: this.isObserved,
    };
  }

  /**
   * Reconstrói a partir de JSON, **tolerante a payload malformado**: rótulo
   * vira `'—'`, valor vira `0` e os sinalizadores viram `false`.
   */
  static fromJson(json: JsonMap): TraceSamplePoint {
    return new TraceSamplePoint({
      label: asString(json['label']) ?? '—',
      value: AuditJson.number(json['value']) ?? 0,
      definesResult: asBool(json['definesResult']) ?? false,
      isObserved: asBool(json['isObserved']) ?? false,
    });
  }
}

/**
 * A amostra por trás de um cálculo que resume vários períodos num só número.
 *
 * Uma mediana apresentada sozinha é indistinguível de um chute: quem confere
 * a conta não consegue dizer quais exercícios entraram nela, qual ficou no
 * meio, nem se a janela pegou os anos que deveria. Este é o material que o
 * painel de auditoria desenha, e é o mesmo que o algoritmo usou.
 */
export class TraceSample {
  /** O que a amostra mede, para o cabeçalho do gráfico. */
  readonly title: string;

  /** Em ordem cronológica. */
  readonly points: readonly TraceSamplePoint[];

  /** Estatística resumo da amostra — a mediana, no fluxo-base. */
  readonly summary: number | null;

  /** Como chamar [summary] na legenda. */
  readonly summaryLabel: string;

  /** Borda inferior da banda de aceitação, quando o cálculo define uma. */
  readonly lowerBound: number | null;

  /** Borda superior da banda de aceitação, quando o cálculo define uma. */
  readonly upperBound: number | null;

  /** Valor efetivamente adotado depois do tratamento. */
  readonly selected: number | null;

  /** Unidade dos valores, para o eixo do gráfico. Vazio para adimensional. */
  readonly unit: string;

  constructor(args: {
    title: string;
    points: readonly TraceSamplePoint[];
    summary?: number | null;
    summaryLabel?: string;
    lowerBound?: number | null;
    upperBound?: number | null;
    selected?: number | null;
    unit?: string;
  }) {
    this.title = args.title;
    this.points = args.points;
    this.summary = args.summary ?? null;
    this.summaryLabel = args.summaryLabel ?? 'mediana';
    this.lowerBound = args.lowerBound ?? null;
    this.upperBound = args.upperBound ?? null;
    this.selected = args.selected ?? null;
    this.unit = args.unit ?? '';
  }

  /** Serializa a amostra e todos os seus pontos. */
  toJson(): JsonMap {
    return {
      title: this.title,
      points: this.points.map((p) => p.toJson()),
      summary: AuditJson.safe(this.summary),
      summaryLabel: this.summaryLabel,
      lowerBound: AuditJson.safe(this.lowerBound),
      upperBound: AuditJson.safe(this.upperBound),
      selected: AuditJson.safe(this.selected),
      unit: this.unit,
    };
  }

  /**
   * Reconstrói a amostra, com a mesma tolerância de
   * [TraceSamplePoint.fromJson]. Entradas de `points` que não sejam mapas são
   * **descartadas em silêncio**.
   */
  static fromJson(json: JsonMap): TraceSample {
    const rawPoints = Array.isArray(json['points']) ? (json['points'] as unknown[]) : [];
    const points: TraceSamplePoint[] = [];
    for (const p of rawPoints) {
      const m = asMap(p);
      if (m !== null) points.push(TraceSamplePoint.fromJson(m));
    }
    return new TraceSample({
      title: asString(json['title']) ?? '',
      points,
      summary: AuditJson.number(json['summary']),
      summaryLabel: asString(json['summaryLabel']) ?? 'mediana',
      lowerBound: AuditJson.number(json['lowerBound']),
      upperBound: AuditJson.number(json['upperBound']),
      selected: AuditJson.number(json['selected']),
      unit: asString(json['unit']) ?? '',
    });
  }
}

/**
 * Rastro de **um** cálculo: a fórmula, os valores que entraram nela e a
 * aritmética passo a passo até o resultado.
 *
 * Existe para auditoria acadêmica. A defesa de um trabalho que produz números
 * exige demonstrar que o número apresentado na tela é o número que a fórmula
 * da metodologia produz — e a única forma honesta de demonstrar isso é expor
 * a substituição de variáveis feita pelo código que roda de verdade.
 *
 * Por isso o rastro é **capturado no ponto do cálculo**, a partir dos mesmos
 * objetos que alimentam o resultado apresentado. Nada aqui recalcula nada.
 */
export class CalculationTrace {
  /** Nome do cálculo, como aparece na metodologia. */
  readonly formulaName: string;

  /** A fórmula em LaTeX, para renderização em formatação acadêmica. */
  readonly latexRepresentation: string;

  /**
   * Símbolo → valor atribuído. As chaves usam o mesmo símbolo do LaTeX,
   * sem a barra invertida, para que a tabela case com a fórmula renderizada.
   */
  readonly mappedVariables: JsonMap;

  /** Decomposição da aritmética, uma linha por etapa. */
  readonly intermediateSteps: readonly string[];

  /** Resultado do cálculo. `null` para rastros que só registram substituição. */
  readonly finalValue: number | null;

  /** Unidade do resultado: `R$`, `%`, `×`, `anos`, ou vazio para adimensional. */
  readonly unit: string;

  /** A amostra por trás do cálculo, quando ele resume vários períodos. */
  readonly sample: TraceSample | null;

  /**
   * **Por que** o cálculo deu o que deu, em linguagem corrente, um parágrafo
   * por linha. Nasceu do pedido do orientador, em 14/10/2026, de entender por
   * que a base foi normalizada e em que direção. Omitido do JSON quando vazio.
   */
  readonly explanation: readonly string[];

  constructor(args: {
    formulaName: string;
    latexRepresentation: string;
    mappedVariables?: JsonMap;
    intermediateSteps?: readonly string[];
    finalValue?: number | null;
    unit?: string;
    sample?: TraceSample | null;
    explanation?: readonly string[];
  }) {
    this.formulaName = args.formulaName;
    this.latexRepresentation = args.latexRepresentation;
    this.mappedVariables = args.mappedVariables ?? {};
    this.intermediateSteps = args.intermediateSteps ?? [];
    this.finalValue = args.finalValue ?? null;
    this.unit = args.unit ?? '';
    this.sample = args.sample ?? null;
    this.explanation = args.explanation ?? [];
  }

  /**
   * Serializa o rastro. A chave `sample` é **omitida** quando não há amostra,
   * em vez de emitida como `null`.
   */
  toJson(): JsonMap {
    const out: JsonMap = {
      formulaName: this.formulaName,
      latexRepresentation: this.latexRepresentation,
      mappedVariables: AuditJson.safe(this.mappedVariables),
      intermediateSteps: [...this.intermediateSteps],
      finalValue: AuditJson.safe(this.finalValue),
      unit: this.unit,
    };
    if (this.sample !== null) out['sample'] = this.sample.toJson();
    if (this.explanation.length > 0) out['explanation'] = [...this.explanation];
    return out;
  }

  /**
   * Reconstrói o rastro, tolerante a payload malformado. Passos de tipo
   * inesperado são convertidos por interpolação em vez de descartados.
   */
  static fromJson(json: JsonMap): CalculationTrace {
    const steps = Array.isArray(json['intermediateSteps']) ? (json['intermediateSteps'] as unknown[]) : [];
    const rows = Array.isArray(json['explanation']) ? (json['explanation'] as unknown[]) : [];
    const sample = asMap(json['sample']);
    return new CalculationTrace({
      formulaName: asString(json['formulaName']) ?? '—',
      latexRepresentation: asString(json['latexRepresentation']) ?? '',
      mappedVariables: asMap(json['mappedVariables']) ?? {},
      intermediateSteps: steps.map(interpolate),
      finalValue: AuditJson.number(json['finalValue']),
      unit: asString(json['unit']) ?? '',
      sample: sample !== null ? TraceSample.fromJson(sample) : null,
      explanation: rows.map(interpolate),
    });
  }
}

/**
 * Uma execução completa, do payload de entrada ao payload de saída.
 *
 * O contrato de campos é fixo: é o que a página de logs consome e o que sai
 * no arquivo de exportação da auditoria.
 */
export class AuditEvent {
  /** UUID v4 que correlaciona o evento com sua transação. */
  readonly transactionId: string;

  /**
   * Início da execução, em hora **local**. Serializa como UTC ISO-8601 e
   * volta convertido para local em [AuditEvent.fromJson].
   */
  readonly timestamp: DateTime;

  /**
   * Origem da execução. Chamadas de rede trazem o caminho da API; cálculos do
   * núcleo trazem o caminho interno do serviço — `/core/valuation/PETR4`, por
   * exemplo. É o campo que separa os dois tipos de evento na interface.
   */
  readonly endpoint: string;

  /** O que entrou na execução. */
  readonly inputPayload: JsonMap;

  /** O que saiu. Em falha traz `status: 'falha'` e `motivo`. */
  readonly outputPayload: JsonMap;

  /** Duração medida, em milissegundos. */
  readonly executionTimeMs: number;

  /**
   * Rastros de cálculo, na ordem em que foram registrados. Vazio nos eventos
   * de rede, que medem a requisição inteira e não têm conta a decompor.
   */
  readonly calculations: readonly CalculationTrace[];

  constructor(args: {
    transactionId: string;
    timestamp: DateTime;
    endpoint: string;
    inputPayload: JsonMap;
    outputPayload: JsonMap;
    executionTimeMs: number;
    calculations?: readonly CalculationTrace[];
  }) {
    this.transactionId = args.transactionId;
    this.timestamp = args.timestamp;
    this.endpoint = args.endpoint;
    this.inputPayload = args.inputPayload;
    this.outputPayload = args.outputPayload;
    this.executionTimeMs = args.executionTimeMs;
    this.calculations = args.calculations ?? [];
  }

  /** Serializa o evento inteiro, com [timestamp] normalizado para UTC. */
  toJson(): JsonMap {
    return {
      transactionId: this.transactionId,
      timestamp: this.timestamp.toUtc().toIso8601String(),
      endpoint: this.endpoint,
      inputPayload: AuditJson.safeMap(this.inputPayload),
      outputPayload: AuditJson.safeMap(this.outputPayload),
      executionTimeMs: this.executionTimeMs,
      calculations: this.calculations.map((c) => c.toJson()),
    };
  }

  /**
   * Reconstrói o evento, tolerante a payload malformado.
   *
   * **Ressalva:** um `timestamp` ausente ou inválido cai para o instante da
   * leitura. É aceitável na interface de diagnóstico, mas não trate o campo
   * como confiável em evento reidratado.
   */
  static fromJson(json: JsonMap): AuditEvent {
    const calculations: CalculationTrace[] = [];
    const raw = Array.isArray(json['calculations']) ? (json['calculations'] as unknown[]) : [];
    for (const c of raw) {
      const m = asMap(c);
      if (m !== null) calculations.push(CalculationTrace.fromJson(m));
    }
    const ms = json['executionTimeMs'];
    return new AuditEvent({
      transactionId: asString(json['transactionId']) ?? '—',
      timestamp: DateTime.tryParse(asString(json['timestamp']) ?? '')?.toLocal() ?? DateTime.now(),
      endpoint: asString(json['endpoint']) ?? '—',
      inputPayload: asMap(json['inputPayload']) ?? {},
      outputPayload: asMap(json['outputPayload']) ?? {},
      executionTimeMs: typeof ms === 'number' ? Math.trunc(ms) : 0,
      calculations,
    });
  }
}

/**
 * Identificadores de transação.
 *
 * Gerador próprio em vez de dependência, porque o núcleo é declaradamente sem
 * dependências de runtime.
 */
export const AuditIds = {
  /** UUID v4 conforme a RFC 4122: 122 bits sorteados, versão 4 e variante 10. */
  uuidV4(): string {
    const bytes = new Uint8Array(16);
    const crypto = (globalThis as { crypto?: { getRandomValues?: (a: Uint8Array) => Uint8Array } }).crypto;
    if (crypto?.getRandomValues !== undefined) {
      crypto.getRandomValues(bytes);
    } else {
      for (let i = 0; i < 16; i++) bytes[i] = Math.floor(Math.random() * 256);
    }
    bytes[6] = (bytes[6]! & 0x0f) | 0x40;
    bytes[8] = (bytes[8]! & 0x3f) | 0x80;
    const hex = [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
    return (
      `${hex.substring(0, 8)}-${hex.substring(8, 12)}-` +
      `${hex.substring(12, 16)}-${hex.substring(16, 20)}-` +
      `${hex.substring(20)}`
    );
  },
};
