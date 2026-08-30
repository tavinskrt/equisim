/**
 * Contrato de saida do CONSELHEIRO.
 *
 * Deliberadamente diferente do contrato do auditor, e a diferenca e o ponto:
 *
 *   - o auditor devolve `findings[]`, cada um ancorado em `arquivo:linha`.
 *     Serve para defeito pontual, que e o que ele procura.
 *   - o conselheiro devolve inventario, tensoes, alvo e sequencia. O problema
 *     que ele examina nao e defeito pontual, e RELACAO entre coisas: rotulo que
 *     nao descreve a tela, decisao que o codigo contradiz, promessa que
 *     ninguem cumpriu. Nada disso cabe num achado com numero de linha.
 *
 * `propertyOrdering` NAO e cosmetico -- mesma razao do schema do auditor. O
 * modelo gera as propriedades na ordem declarada, entao a ordem e a ordem de
 * raciocinio. `inventory` vem antes de `tensions` para forcar OBSERVAR antes de
 * JULGAR; `proposal` e `sequence` vem por ultimo porque propor sem ter
 * inventariado e como escolher o veredito antes de olhar a evidencia.
 */
import { Type, type Schema } from '@google/genai';

/**
 * Gravidade de uma tensao, da mais grave para a mais leve.
 *
 * Nenhuma bloqueia coisa alguma -- o conselheiro sempre sai com codigo 0. A
 * escala existe para governar ATENCAO: uma rodada endereca so `ESTRUTURAL`, e
 * `POLIMENTO` provavelmente nunca sera endereçado, o que e resultado aceito e
 * nao perda.
 */
export const SEVERIDADES = ['ESTRUTURAL', 'LOCAL', 'POLIMENTO'] as const;
export type Severidade = (typeof SEVERIDADES)[number];

/** Identificadores das lentes. Espelha `LENTES` em `lentes.ts`. */
export const LENTES_IDS = [
  'registro',
  'nucleo',
  'dados',
  'metodo',
  'risco',
  'rumo',
  'tela',
] as const;
export type LenteId = (typeof LENTES_IDS)[number];

/**
 * Um elemento do dominio, descrito ANTES de qualquer juizo.
 *
 * Esta etapa existe para separar "o que esta la" de "o que eu acho disso". Sem
 * ela o modelo abre direto na opiniao, e a opiniao sem inventario e exatamente
 * o backlog generico que este agente precisa nao produzir.
 */
export interface Observacao {
  /** Do que se fala: arquivo, modulo, tela, ou "decisao no 9". */
  subject: string;
  /**
   * Trecho LITERAL do material que sustenta a observacao.
   *
   * E a mesma ancora anti-alucinacao do auditor, pelo mesmo motivo: se nao da
   * para copiar do material, nao esta no material.
   */
  evidence: string;
  /** O que existe ali hoje. Descricao, nao avaliacao. */
  what_exists: string;
  /** Para que esse `subject` existe -- a tarefa que ele serve. */
  purpose: string;
  /** O que disputa, atrapalha ou contradiz esse proposito. Vazio e legitimo. */
  competing: string[];
}

/**
 * Onde o que existe briga com o proposito de existir.
 *
 * `options` e plural por decisao de projeto: o conselheiro propoe caminhos, nao
 * decreta escolha. Quem decide e humano, e uma decisao so e defensavel em banca
 * se as alternativas descartadas forem conhecidas.
 */
export interface Tensao {
  subject: string;
  /** O que se observa. Precisa ser verificavel no material enviado. */
  observation: string;
  /** Trecho literal do material. Sem isso a tensao nao existe. */
  evidence: string;
  /** Por que isso custa caro, ligado explicitamente ao `purpose` do subject. */
  why_it_hurts: string;
  /** Dois a tres caminhos possiveis. Nunca um so. */
  options: string[];
  severity: Severidade;
}

/** Um passo isolavel do caminho ate o alvo. */
export interface Passo {
  order: number;
  /** O que fazer, no imperativo. */
  action: string;
  /** Caminhos do repositorio que o passo toca. */
  touches: string[];
  /** Observacao verificavel que diz que o passo terminou. */
  done_when: string;
}

/** O relatorio completo de uma execucao de lente. */
export interface AdvisorReport {
  lente: LenteId;
  inventory: Observacao[];
  tensions: Tensao[];
  /** O estado-alvo, em prosa curta. Vazio quando nao ha tensao a resolver. */
  proposal: string;
  sequence: Passo[];
  summary: string;
}

const observacaoSchema: Schema = {
  type: Type.OBJECT,
  required: ['subject', 'evidence', 'what_exists', 'purpose', 'competing'],
  propertyOrdering: [
    'subject',
    'evidence',
    'what_exists',
    'purpose',
    'competing',
  ],
  properties: {
    subject: {
      type: Type.STRING,
      description:
        'Do que se fala: caminho de arquivo, modulo, nome de tela, ou ' +
        'identificador de decisao (ex.: "decisao no 9").',
    },
    evidence: {
      type: Type.STRING,
      description:
        'Trecho LITERAL do material recebido, copiado. Se voce nao consegue ' +
        'copiar, o item nao esta no material e nao deve ser inventariado.',
    },
    what_exists: {
      type: Type.STRING,
      description:
        'O que existe ali hoje. Descricao factual, sem avaliacao e sem ' +
        'sugestao -- o juizo vem depois, em tensions.',
    },
    purpose: {
      type: Type.STRING,
      description:
        'Para que esse subject existe: a tarefa que ele serve ou a decisao ' +
        'que ele registra.',
    },
    competing: {
      type: Type.ARRAY,
      description:
        'O que disputa, atrapalha ou contradiz esse proposito. Lista vazia e ' +
        'resposta legitima e frequente.',
      items: { type: Type.STRING },
    },
  },
};

const tensaoSchema: Schema = {
  type: Type.OBJECT,
  required: [
    'subject',
    'observation',
    'evidence',
    'why_it_hurts',
    'options',
    'severity',
  ],
  propertyOrdering: [
    'subject',
    'observation',
    'evidence',
    'why_it_hurts',
    'options',
    'severity',
  ],
  properties: {
    subject: {
      type: Type.STRING,
      description: 'O mesmo vocabulario usado no inventario.',
    },
    observation: {
      type: Type.STRING,
      description:
        'O que se observa, verificavel no material. Nao e recomendacao: e o ' +
        'fato que motiva a tensao.',
    },
    evidence: {
      type: Type.STRING,
      description:
        'Trecho literal do material que sustenta a observacao. Sem ele a ' +
        'tensao NAO EXISTE -- nao a reporte.',
    },
    why_it_hurts: {
      type: Type.STRING,
      description:
        'Por que isso custa caro, ligado EXPLICITAMENTE ao purpose do ' +
        'subject. "Ficaria melhor" nao e resposta valida aqui.',
    },
    options: {
      type: Type.ARRAY,
      description:
        'Dois a tres caminhos possiveis, com o custo de cada um. Nunca um ' +
        'caminho so: quem decide e humano.',
      items: { type: Type.STRING },
    },
    severity: { type: Type.STRING, enum: [...SEVERIDADES] },
  },
};

const passoSchema: Schema = {
  type: Type.OBJECT,
  required: ['order', 'action', 'touches', 'done_when'],
  propertyOrdering: ['order', 'action', 'touches', 'done_when'],
  properties: {
    order: { type: Type.INTEGER, description: 'Posicao na sequencia, a partir de 1.' },
    action: { type: Type.STRING, description: 'O que fazer, no imperativo.' },
    touches: {
      type: Type.ARRAY,
      description: 'Caminhos do repositorio que este passo toca.',
      items: { type: Type.STRING },
    },
    done_when: {
      type: Type.STRING,
      description:
        'Observacao VERIFICAVEL que diz que o passo terminou. Nao vale ' +
        '"melhorar X": precisa ser algo que se possa conferir.',
    },
  },
};

/** Schema completo, no formato do SDK. Convertido por `toJsonSchema` no `agy`. */
export const ADVISOR_RESPONSE_SCHEMA: Schema = {
  type: Type.OBJECT,
  required: ['lente', 'inventory', 'tensions', 'proposal', 'sequence', 'summary'],
  propertyOrdering: [
    'lente',
    'inventory',
    'tensions',
    'proposal',
    'sequence',
    'summary',
  ],
  properties: {
    lente: { type: Type.STRING, enum: [...LENTES_IDS] },
    inventory: {
      type: Type.ARRAY,
      description:
        'O que existe no dominio, descrito antes de julgado. Preencha esta ' +
        'lista ANTES de pensar em tensions.',
      items: observacaoSchema,
    },
    tensions: {
      type: Type.ARRAY,
      description:
        'Onde o que existe briga com o proposito de existir. Lista vazia e ' +
        'resposta legitima: um dominio que cumpre seu proposito esta pronto.',
      items: tensaoSchema,
    },
    proposal: {
      type: Type.STRING,
      description:
        'O estado-alvo, em prosa curta -- no maximo dois paragrafos. String ' +
        'vazia quando nao ha tensao a resolver.',
    },
    sequence: {
      type: Type.ARRAY,
      description:
        'Caminho ate o alvo, cada passo isolavel e verificavel. Lista vazia ' +
        'quando nao ha tensao a resolver.',
      items: passoSchema,
    },
    summary: {
      type: Type.STRING,
      description:
        'Duas a quatro frases: o que foi examinado e o que se conclui. Sem ' +
        'repetir a lista de tensoes.',
    },
  },
};

/**
 * Valida e normaliza a resposta.
 *
 * Normaliza o recuperavel em vez de rejeitar o relatorio inteiro, pela mesma
 * razao do auditor: um agente que quebra por um campo ausente e um agente que
 * sera desligado. A diferenca e que aqui nao ha veredito a recalcular -- o
 * conselheiro nunca bloqueia nada, entao nao ha decisao delegada a proteger.
 */
export function validateAdvisorReport(
  value: unknown,
  lenteEsperada: LenteId,
): AdvisorReport {
  if (typeof value !== 'object' || value === null) {
    throw new Error('A resposta nao e um objeto JSON.');
  }
  const raw = value as Record<string, unknown>;

  const lista = (campo: unknown): Record<string, unknown>[] =>
    Array.isArray(campo)
      ? campo.filter(
          (i): i is Record<string, unknown> => typeof i === 'object' && i !== null,
        )
      : [];

  const texto = (v: unknown, padrao = ''): string =>
    typeof v === 'string' ? v : padrao;

  const textos = (v: unknown): string[] =>
    Array.isArray(v) ? v.map((i) => String(i)).filter((s) => s.trim() !== '') : [];

  const inventory: Observacao[] = lista(raw.inventory).map((o) => ({
    subject: texto(o.subject, '(sem sujeito)'),
    evidence: texto(o.evidence),
    what_exists: texto(o.what_exists),
    purpose: texto(o.purpose),
    competing: textos(o.competing),
  }));

  const tensions: Tensao[] = lista(raw.tensions).map((t) => {
    const sev = texto(t.severity, 'POLIMENTO').toUpperCase();
    return {
      subject: texto(t.subject, '(sem sujeito)'),
      observation: texto(t.observation),
      evidence: texto(t.evidence),
      why_it_hurts: texto(t.why_it_hurts),
      options: textos(t.options),
      // Gravidade desconhecida cai para POLIMENTO: na duvida, NAO compete pela
      // atencao da rodada. O erro barato aqui e adiar, nao inflar a fila.
      severity: (SEVERIDADES as readonly string[]).includes(sev)
        ? (sev as Severidade)
        : 'POLIMENTO',
    };
  });

  const sequence: Passo[] = lista(raw.sequence).map((p, i) => ({
    order: Number.isFinite(Number(p.order)) ? Math.trunc(Number(p.order)) : i + 1,
    action: texto(p.action),
    touches: textos(p.touches),
    done_when: texto(p.done_when),
  }));

  const lenteDita = texto(raw.lente);
  return {
    // A lente do runner prevalece: ele sabe qual executou, o modelo apenas
    // repete. Divergencia aqui e sintoma de prompt trocado, nao de dado novo.
    lente: (LENTES_IDS as readonly string[]).includes(lenteDita)
      ? (lenteDita as LenteId)
      : lenteEsperada,
    inventory,
    tensions,
    proposal: texto(raw.proposal),
    sequence,
    summary: texto(raw.summary, '(sem resumo)'),
  };
}
