/**
 * Contrato de saida do auditor (Structured Output do Gemini).
 *
 * `propertyOrdering` NAO e cosmetico: o modelo gera as propriedades na ordem
 * declarada, entao a ordem define a ordem de raciocinio. Cada achado e forcado
 * a produzir evidencia -> justificativa -> cenario de falha ANTES de atribuir a
 * severidade. Se a severidade viesse primeiro, o modelo escolheria o veredito e
 * so depois racionalizaria -- e a taxa de falso positivo sobe.
 * Pelo mesmo motivo, `status` e `summary` vem depois de `findings`.
 */
import { Type, type Schema } from '@google/genai';

/**
 * Severidades, da mais grave para a mais leve.
 *
 * So `FAIL` bloqueia -- e o runner sai com codigo 1. `WARN` e divida em codigo
 * preexistente e `INFO` e observacao; ambos saem com 0.
 */
export const SEVERITIES = ['FAIL', 'WARN', 'INFO'] as const;

/** Severidade de um achado. */
export type Severity = (typeof SEVERITIES)[number];

/**
 * Categorias de achado, em tres grupos.
 *
 * A lista e **fechada**: o modelo precisa encaixar todo achado em uma delas, e
 * `OTHER` existe para que ele nao invente rotulo novo quando nao couber. Uma
 * categoria acrescentada aqui entra sozinha no schema enviado ao modelo.
 */
export const CATEGORIES = [
  // --- Financeiro ---
  'MONETARY_PRECISION', // ponto flutuante binario em caminho monetario
  'ROUNDING', // arredondamento ausente, implicito ou com modo errado
  'CENT_RESIDUE', // resto de divisao de centavos nao distribuido
  'INTEREST_RATE', // conversao/composicao de taxa incorreta
  'AMORTIZATION', // PRICE/SAC, saldo devedor, fechamento de parcelas
  'DAYCOUNT', // base 252/360/365, ano bissexto, fuso
  'FLOAT_EQUALITY', // == / != entre doubles
  'NAN_GUARD', // divisao por zero, log(<=0), sqrt(<0), overflow
  'UNIT_MISMATCH', // fracao vs percentual, centavos vs reais
  // --- Responsividade ---
  'RESPONSIVE_LAYOUT', // ausencia de adaptacao por breakpoint
  'OVERFLOW_RISK', // estouro horizontal/vertical previsivel
  'FIXED_DIMENSION', // largura/altura fixa que quebra em telas estreitas
  'TEXT_TRUNCATION', // texto sem maxLines/overflow/escala
  'TOUCH_TARGET', // alvo de toque abaixo do minimo
  // --- Sistema de design (ver RULES R17-R24 em rules.ts) ---
  'DESIGN_TOKEN', // cor/tipografia/espacamento literal onde ha token
  'TEXT_SCALE', // quebra sob MediaQuery.textScalerOf, nao sob largura
  'NUMERIC_ALIGNMENT', // valor monetario sem cifra tabular em coluna
  'COLOR_CONTRAST', // par cor/superficie sem contraste medido
  'SEMANTIC_STATE', // estado so por cor, ou valor mascarado sem semantics
  'LOADING_STATE', // indicador cuja geometria difere do conteudo final
  'REPAINT_SCOPE', // camada cara sem RepaintBoundary
  // --- Outros ---
  'OTHER',
] as const;
/** Categoria de um achado. */
export type Category = (typeof CATEGORIES)[number];

/**
 * Um achado da auditoria.
 *
 * A ordem dos campos aqui espelha `propertyOrdering` do schema, e ela e a ordem
 * em que o modelo os gera -- ver o cabecalho do arquivo.
 */
export interface QaFinding {
  /** Caminho relativo a raiz do repositorio. */
  file: string;
  /** Linha citada. Vem da numeracao que `collectFiles` injeta. */
  line: number;
  /** Classificacao do defeito. */
  category: Category;
  /** Titulo curto, uma linha. */
  title: string;
  /** Trecho do codigo que sustenta o achado. */
  evidence: string;
  /**
   * `true` quando o defeito esta em linha **adicionada** pelo diff.
   *
   * E o campo que governa a calibragem: em modo `diff`, so achado com este
   * campo verdadeiro pode ser `FAIL`; o resto vira `WARN`.
   */
  introduced_by_change: boolean;
  /** Por que e defeito. */
  rationale: string;
  /** Entrada concreta que produz saida errada ou excecao. */
  failure_scenario: string;
  /** Correcao proposta. */
  suggested_fix: string;
  /** Gravidade, decidida depois da evidencia. */
  severity: Severity;
}

/** O relatorio completo de uma auditoria. */
export interface QaReport {
  /** Achados, em qualquer ordem. Vazio significa nada a reportar. */
  findings: QaFinding[];
  /**
   * Veredito. `FAIL` sai com codigo 1 e bloqueia.
   *
   * Gerado **depois** de `findings`, para que o veredito decorra da evidencia
   * em vez de anteceder e enviesa-la.
   */
  status: 'PASS' | 'FAIL';
  /** Resumo em uma frase, para o cabecalho. */
  summary: string;
}

const findingSchema: Schema = {
  type: Type.OBJECT,
  required: [
    'file',
    'line',
    'category',
    'title',
    'evidence',
    'introduced_by_change',
    'rationale',
    'failure_scenario',
    'suggested_fix',
    'severity',
  ],
  propertyOrdering: [
    'file',
    'line',
    'category',
    'title',
    'evidence',
    'introduced_by_change',
    'rationale',
    'failure_scenario',
    'suggested_fix',
    'severity',
  ],
  properties: {
    file: {
      type: Type.STRING,
      description: 'Caminho do arquivo relativo a raiz do repositorio.',
    },
    line: {
      type: Type.INTEGER,
      description:
        'Linha do arquivo APOS a alteracao. Use 0 apenas se for genuinamente ' +
        'impossivel determinar. Nunca invente um numero plausivel.',
    },
    category: { type: Type.STRING, enum: [...CATEGORIES] },
    title: {
      type: Type.STRING,
      description: 'Uma frase objetiva descrevendo o defeito. Sem preambulo.',
    },
    evidence: {
      type: Type.STRING,
      description:
        'O trecho de codigo literal que sustenta o achado, copiado do material ' +
        'auditado. Se voce nao consegue copiar o trecho, o achado nao existe.',
    },
    introduced_by_change: {
      type: Type.BOOLEAN,
      description:
        'true se o defeito esta em linha ADICIONADA pelo diff (prefixo "+"). ' +
        'false se esta em codigo preexistente (contexto, linha sem prefixo).',
    },
    rationale: {
      type: Type.STRING,
      description: 'Por que isso e defeito. Cite a regra do rulebook (ex.: R3).',
    },
    failure_scenario: {
      type: Type.STRING,
      description:
        'Entradas concretas -> saida errada. Com numeros reais, nao hipoteses ' +
        'vagas. Ex.: "R$ 0,01 dividido em 3 parcelas produz 3x R$ 0,00; ' +
        'R$ 0,01 desaparece do total". Para responsividade, cite a largura ' +
        'exata em que quebra (320, 375, 768, 1024 ou 1440 dp).',
    },
    suggested_fix: {
      type: Type.STRING,
      description:
        'Correcao concreta, compativel com as restricoes de arquitetura do ' +
        'projeto declaradas no rulebook.',
    },
    severity: { type: Type.STRING, enum: [...SEVERITIES] },
  },
};

/**
 * Schema completo da resposta, enviado ao modelo como Structured Output.
 *
 * `propertyOrdering` coloca `findings` antes de `status` e `summary` de
 * proposito: o veredito precisa decorrer dos achados, e nao anteceder e
 * enviesa-los. Ver o cabecalho do arquivo.
 *
 * O backend `api` forca este schema no servidor; o `agy` nao o forca, entao
 * la ele serve de contrato a validar depois.
 */
export const QA_RESPONSE_SCHEMA: Schema = {
  type: Type.OBJECT,
  required: ['findings', 'status', 'summary'],
  propertyOrdering: ['findings', 'status', 'summary'],
  properties: {
    findings: {
      type: Type.ARRAY,
      description:
        'Todos os achados. Lista vazia se o material auditado esta correto. ' +
        'Nao invente achados para parecer produtivo.',
      items: findingSchema,
    },
    status: {
      type: Type.STRING,
      enum: ['PASS', 'FAIL'],
      description:
        'FAIL se e somente se houver ao menos um achado com severity=FAIL. ' +
        'Achados WARN e INFO nao reprovam.',
    },
    summary: {
      type: Type.STRING,
      description:
        'Duas a quatro frases: o que foi auditado e o veredito. Sem repetir a ' +
        'lista de achados.',
    },
  },
};

/**
 * Valida e normaliza a resposta.
 *
 * O schema e forcado pelo servidor, mas a validacao local permanece por dois
 * motivos: ela recalcula o veredito a partir dos achados, em vez de confiar no
 * campo `status` autodeclarado; e normaliza o recuperavel em vez de rejeitar o
 * relatorio inteiro -- um gate que quebra por um campo ausente e um gate que
 * sera desligado.
 */
export function validateReport(value: unknown): QaReport {
  if (typeof value !== 'object' || value === null) {
    throw new Error('A resposta nao e um objeto JSON.');
  }
  const raw = value as Record<string, unknown>;
  if (!Array.isArray(raw.findings)) {
    throw new Error('A resposta nao tem o campo `findings` como lista.');
  }

  const findings: QaFinding[] = raw.findings.map((item, index) => {
    if (typeof item !== 'object' || item === null) {
      throw new Error(`findings[${index}] nao e um objeto.`);
    }
    const f = item as Record<string, unknown>;

    const severity = String(f.severity ?? 'INFO').toUpperCase();
    const category = String(f.category ?? 'OTHER').toUpperCase();

    return {
      file: String(f.file ?? '(arquivo nao informado)'),
      line: Number.isFinite(Number(f.line)) ? Math.trunc(Number(f.line)) : 0,
      // Categoria desconhecida vira OTHER em vez de derrubar o relatorio.
      category: (CATEGORIES as readonly string[]).includes(category)
        ? (category as Category)
        : 'OTHER',
      title: String(f.title ?? '(sem titulo)'),
      evidence: String(f.evidence ?? ''),
      introduced_by_change: f.introduced_by_change === true,
      rationale: String(f.rationale ?? ''),
      failure_scenario: String(f.failure_scenario ?? ''),
      suggested_fix: String(f.suggested_fix ?? ''),
      // Severidade desconhecida vira INFO: na duvida, NAO bloqueia o commit.
      // O erro barato aqui e deixar passar, nao travar o time por ruido.
      severity: (SEVERITIES as readonly string[]).includes(severity)
        ? (severity as Severity)
        : 'INFO',
    };
  });

  // O veredito e recalculado a partir dos achados. O `status` do modelo e
  // apenas corroborativo: um gate nao delega a decisao a um campo
  // autodeclarado.
  const hasFail = findings.some((f) => f.severity === 'FAIL');
  return {
    findings,
    status: hasFail ? 'FAIL' : 'PASS',
    summary: typeof raw.summary === 'string' ? raw.summary : '(sem resumo)',
  };
}

// ---------------------------------------------------------------------------
// Conversao para JSON Schema padrao (backend `agy`)
// ---------------------------------------------------------------------------

/**
 * Converte o schema do formato do SDK do Gemini para JSON Schema padrao.
 *
 * NAO e cosmetico e nao da para pular: o SDK usa o enum `Type`, que serializa
 * em MAIUSCULAS ("OBJECT", "STRING"), enquanto JSON Schema exige minusculas
 * ("object", "string"). Passar o schema do SDK direto para `agy --json-schema`
 * seria aceito na leitura e falharia na validacao, ou pior, seria ignorado em
 * silencio -- e a saida voltaria sem estrutura.
 *
 * Tambem descarta `propertyOrdering`, que e extensao do Gemini e nao existe no
 * JSON Schema. A ordem de raciocinio que ela garantia no backend `api` passa a
 * depender da ordem em `required` e das descricoes de cada campo.
 */
export function toJsonSchema(schema: Schema): Record<string, unknown> {
  const out: Record<string, unknown> = {};

  if (schema.type) out.type = String(schema.type).toLowerCase();
  if (schema.description) out.description = schema.description;
  if (schema.enum) out.enum = schema.enum;
  if (schema.required) out.required = schema.required;
  // `minItems`/`maxItems` sao string no SDK e number no JSON Schema.
  if (schema.minItems !== undefined) out.minItems = Number(schema.minItems);
  if (schema.maxItems !== undefined) out.maxItems = Number(schema.maxItems);
  if (schema.items) out.items = toJsonSchema(schema.items);

  if (schema.properties) {
    const props: Record<string, unknown> = {};
    // Preserva a ordem de declaracao: e a unica pista de ordem que sobrevive
    // a perda de `propertyOrdering`.
    for (const [key, value] of Object.entries(schema.properties)) {
      props[key] = toJsonSchema(value);
    }
    out.properties = props;
  }
  return out;
}
