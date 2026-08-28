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

export const SEVERITIES = ['FAIL', 'WARN', 'INFO'] as const;
export type Severity = (typeof SEVERITIES)[number];

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
  // --- Outros ---
  'OTHER',
] as const;
export type Category = (typeof CATEGORIES)[number];

export interface QaFinding {
  file: string;
  line: number;
  category: Category;
  title: string;
  evidence: string;
  introduced_by_change: boolean;
  rationale: string;
  failure_scenario: string;
  suggested_fix: string;
  severity: Severity;
}

export interface QaReport {
  findings: QaFinding[];
  status: 'PASS' | 'FAIL';
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

// ---------------------------------------------------------------------------
// Suporte ao backend CLI
// ---------------------------------------------------------------------------

/**
 * O mesmo contrato, em texto.
 *
 * O backend de API key envia `QA_RESPONSE_SCHEMA` e o servidor FORCA o formato.
 * O Gemini CLI nao aceita `responseSchema`, entao la o contrato precisa viajar
 * dentro do prompt. Manter as duas formas no mesmo arquivo e proposital: se uma
 * mudar sem a outra, os dois backends divergem silenciosamente.
 */
export function schemaAsText(): string {
  return [
    'Responda com UM objeto JSON exatamente nesta forma:',
    '',
    '{',
    '  "findings": [',
    '    {',
    '      "file": string,                      // caminho relativo a raiz',
    '      "line": number,                      // inteiro; 0 se indeterminavel',
    '      "category": string,                  // um dos valores da lista abaixo',
    '      "title": string,',
    '      "evidence": string,                  // trecho literal do material',
    '      "introduced_by_change": boolean,     // true se em linha "+" do diff',
    '      "rationale": string,                 // cite a regra (ex.: R3)',
    '      "failure_scenario": string,          // entradas concretas -> saida errada',
    '      "suggested_fix": string,',
    '      "severity": string                   // "FAIL" | "WARN" | "INFO"',
    '    }',
    '  ],',
    '  "status": string,                        // "PASS" | "FAIL"',
    '  "summary": string',
    '}',
    '',
    'Valores validos de "category":',
    CATEGORIES.map((c) => `  ${c}`).join('\n'),
    '',
    'Ordem obrigatoria das chaves de cada achado: file, line, category, title,',
    'evidence, introduced_by_change, rationale, failure_scenario, suggested_fix,',
    'severity. Escreva os campos nessa ordem -- ela existe para que voce reuna a',
    'evidencia e o cenario de falha ANTES de decidir a severidade.',
    '',
    'Todos os dez campos sao obrigatorios em todo achado. "findings" pode ser uma',
    'lista vazia. Nao emita nenhum texto fora do objeto JSON, nem cerca de codigo.',
  ].join('\n');
}

/**
 * Valida e normaliza a resposta.
 *
 * Necessario porque o backend CLI nao tem schema forcado pelo servidor: ali o
 * modelo pode omitir campo, trocar tipo ou inventar categoria. Preferimos
 * normalizar o recuperavel a rejeitar o relatorio inteiro -- um gate que quebra
 * por um campo ausente e um gate que sera desligado.
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
