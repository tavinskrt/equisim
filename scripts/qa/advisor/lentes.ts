/**
 * REGISTRO DAS LENTES.
 *
 * Uma lente e a unidade de trabalho do conselheiro, e tem sempre tres partes:
 *
 *   material    o que e enviado ao modelo
 *   pergunta    o que ele esta sendo perguntado
 *   disciplina  o que ele precisa DESCARTAR
 *
 * A terceira e a que faz o agente prestar. Um conselheiro sem disciplina
 * responde "proponha melhorias" com backlog plausivel e vazio -- o equivalente,
 * deste lado, do falso positivo que faz um gate ser desligado. As clausulas
 * aqui sao para esta lente; as gerais estao em `rules.ts`.
 *
 * A colecao do material e generica (ver `collect.ts`): uma lente descreve o que
 * quer por descritores, nao por codigo. Acrescentar lente e, na maioria dos
 * casos, acrescentar entrada nesta tabela.
 */
import type { LenteId } from './schema.ts';

/**
 * Descritor de material.
 *
 * `opcional` existe porque diretorio que ainda nao foi criado e estado normal
 * durante a migracao do registro -- e nao motivo para abortar a execucao.
 */
export type Material =
  | { tipo: 'arquivo'; caminho: string; opcional?: boolean }
  | { tipo: 'arvore-completa'; excluirPrefixos?: string[] }
  | {
      tipo: 'diretorio';
      caminho: string;
      extensoes?: string[];
      excluir?: string[];
      opcional?: boolean;
    }
  | { tipo: 'arvore'; raizes: string[] }
  | { tipo: 'git-log'; quantidade: number };

export interface Lente {
  id: LenteId;
  /** Titulo legivel, para o cabecalho do relatorio. */
  titulo: string;
  /** O que o modelo esta sendo perguntado. Vai integral para o prompt. */
  pergunta: string;
  /** Clausulas de descarte especificas desta lente. */
  disciplina: string[];
  materiais: Material[];
  /**
   * Depende de capturas de tela, que so existem a partir da fase 03 e so
   * trafegam pelo backend `api`. O runner recusa com mensagem acionavel.
   */
  precisaDeCapturas?: boolean;
}

/** Artefatos gerados: auditar `.g.dart` so gasta token. Mesmo criterio do auditor. */
const GERADOS = ['*.g.dart', '*.freezed.dart', '*.mocks.dart'];

/**
 * Diretorios de plataforma, gerados pelo `flutter create` e quase nunca
 * tocados a mao. Sao 120 dos 326 arquivos versionados e nao carregam decisao
 * alguma deste projeto.
 */
const PLATAFORMAS = ['android/', 'ios/', 'web/', 'windows/', 'macos/', 'linux/'];

export const LENTES: Record<LenteId, Lente> = {
  // -------------------------------------------------------------------------
  registro: {
    id: 'registro',
    titulo: 'Integridade do registro',
    pergunta: [
      'Onde o REGISTRO do projeto diverge da REALIDADE do repositorio?',
      '',
      'Classifique cada divergencia em uma destas cinco classes, e diga qual',
      'no campo `observation`:',
      '',
      '  DECISAO CONTRARIADA -- o codigo contradiz uma decisao registrada como',
      '    aceita, e nenhuma decisao posterior a substituiu. A mais grave: e o',
      '    caso em que o projeto mudou de rumo sem ninguem ter decidido.',
      '  PROMESSA NAO CUMPRIDA -- o parecer preve algo, o repositorio nao tem,',
      '    e nada revogou a previsao.',
      '  ESTRUTURA SEM REGISTRO -- mudanca arquitetural relevante presente no',
      '    codigo ou no historico, sem decisao que a explique.',
      '  MEDICAO VENCIDA -- numero medido cuja data ja nao sustenta a conclusao',
      '    que dele se tirou.',
      '  DECISAO SEM DEFINICAO -- numero citado como autoridade em algum ponto',
      '    do texto, sem lugar canonico onde esteja definido.',
      '',
      'Alem disso, INVENTARIE toda decisao numerada DECLARADA EM TEXTO, esteja',
      'ela na tabela consolidada ou solta na prosa. Para cada uma, o campo',
      '`evidence` deve trazer o trecho LITERAL onde ela e declarada, incluindo',
      'qualquer citacao entre aspas -- e dela que sai a proveniencia, e',
      'proveniencia perdida nao se recupera.',
      '',
      'DECLARADA EM TEXTO e a condicao inteira. Uma decisao existe quando algum',
      'documento DIZ que ela foi tomada. Comportamento observado no codigo NAO',
      'e decisao: e implementacao. Se o codigo faz X e nenhum texto declara que',
      'se decidiu X, entao nao ha decisao a inventariar -- ha, no maximo, uma',
      'ESTRUTURA SEM REGISTRO a reportar como tensao.',
    ].join('\n'),
    disciplina: [
      'Esta lente e DIFERENCA DE CONJUNTOS, nao opiniao. Toda divergencia',
      '  nomeia os DOIS lados: o que o registro diz e o que o repositorio tem.',
      'PROIBIDO INFERIR DECISAO A PARTIR DE CODIGO. Raciocinar de tras para',
      '  frente -- da implementacao para a decisao que "deve ter" existido --',
      '  FABRICA registro, e registro fabricado e pior que registro ausente,',
      '  porque parece confiavel. Codigo que faz X sem texto que declare X e',
      '  ESTRUTURA SEM REGISTRO, nunca uma decisao a inventariar.',
      'Numero CITADO mas nao DEFINIDO nao entra no inventario. Ele vira tensao',
      '  da classe DECISAO SEM DEFINICAO, e o `evidence` traz o trecho onde o',
      '  numero e citado -- nao uma reconstrucao do que ele diria. Reconstituir',
      '  cabe a quem participou da decisao, nao a quem le o repositorio.',
      'Se voce nao consegue copiar do material a frase que DECLARA a decisao,',
      '  a decisao nao esta declarada. Nao a inventarie.',
      'NAO proponha reescrever o parecer. Ele e documento historico datado; o',
      '  que se propoe e extrair dele o que precisa virar registro enderecavel.',
      'NAO reporte ausencia de documentacao em geral. A pergunta e sobre',
      '  divergencia entre registro e realidade, nao sobre volume de texto.',
    ],
    materiais: [
      { tipo: 'arquivo', caminho: 'PLANO_ARQUITETURA.md' },
      { tipo: 'arquivo', caminho: 'README.md' },
      { tipo: 'arquivo', caminho: 'CLAUDE.md' },
      { tipo: 'diretorio', caminho: 'docs/decisoes', extensoes: ['.md'], opcional: true },
      { tipo: 'diretorio', caminho: 'docs/apontamentos', extensoes: ['.md'], opcional: true },
      // ARVORE COMPLETA, nao um subconjunto. Esta lente pergunta se o registro
      // bate com a realidade; mandar arvore parcial faz o modelo ver ausencia
      // onde ha apenas material nao enviado, e ele reporta "promessa nao
      // cumprida" com toda a razao, sobre um repositorio que nunca viu inteiro.
      // Aconteceu: `tool/` e `functions/` ficaram de fora de uma lista de
      // raizes e viraram duas tensoes ESTRUTURAL falsas.
      { tipo: 'arvore-completa', excluirPrefixos: PLATAFORMAS },
      { tipo: 'git-log', quantidade: 40 },
    ],
  },

  // -------------------------------------------------------------------------
  nucleo: {
    id: 'nucleo',
    titulo: 'Nucleo de dominio',
    pergunta: [
      'As entidades do nucleo sao coesas? Que regra de negocio vazou para a',
      'camada de apresentacao? Que value object falta para eliminar uma classe',
      'de erro por construcao, em vez de por validacao?',
    ].join('\n'),
    disciplina: [
      'PROIBIDO sugerir pacote de terceiros dentro de `equisim_core`. A pureza',
      '  e travada pelo teste `purity_test.dart` e nao esta em negociacao.',
      'Toda proposta cita arquivo e tipo que EXISTEM no material.',
      'NAO proponha renomear por gosto. Nome so entra em tensao quando ele',
      '  descreve coisa diferente do que o tipo faz.',
    ],
    materiais: [
      {
        tipo: 'diretorio',
        caminho: 'packages/equisim_core/lib',
        extensoes: ['.dart'],
        excluir: GERADOS,
      },
      { tipo: 'arquivo', caminho: 'packages/equisim_core/test/purity_test.dart' },
      { tipo: 'diretorio', caminho: 'docs/decisoes', extensoes: ['.md'], opcional: true },
    ],
  },

  // -------------------------------------------------------------------------
  dados: {
    id: 'dados',
    titulo: 'Camada de dados e resiliencia',
    pergunta: [
      'O que acontece quando a API de mercado cai, estoura cota ou devolve',
      'serie incompleta? O cache, o retry e a degradacao entregam a contingencia',
      'que foi decidida -- ou apenas a que foi escrita?',
    ].join('\n'),
    disciplina: [
      'Toda tensao e confrontada com uma DECISAO registrada. Divergencia entre',
      '  decisao e codigo e achado; ausencia de recurso que ninguem decidiu,',
      '  nao e.',
      'NAO proponha trocar de biblioteca de rede ou de banco local. Dio e Drift',
      '  sao decisao registrada.',
      'NAO especule sobre comportamento da API que o material nao demonstre.',
    ],
    materiais: [
      {
        tipo: 'diretorio',
        caminho: 'lib/data',
        extensoes: ['.dart'],
        excluir: GERADOS,
      },
      { tipo: 'arquivo', caminho: 'functions/index.js' },
      { tipo: 'arquivo', caminho: 'firestore.rules', opcional: true },
      { tipo: 'diretorio', caminho: 'docs/decisoes', extensoes: ['.md'], opcional: true },
    ],
  },

  // -------------------------------------------------------------------------
  metodo: {
    id: 'metodo',
    titulo: 'Metodo financeiro',
    pergunta: [
      'A metodologia de DCF e CAPM implementada aqui e defensavel numa banca?',
      'Que premissa esta IMPLICITA no codigo e deveria estar explicita e',
      'justificada? Onde uma escolha metodologica foi feita sem que o codigo',
      'registre por que ela, e nao a alternativa?',
    ].join('\n'),
    disciplina: [
      'Esta lente NAO caca bug -- disso o auditor cuida, e melhor. Aqui se',
      '  questiona PREMISSA. Toda observacao nomeia a premissa e o ponto onde',
      '  ela esta codificada.',
      'NAO reporte erro aritmetico nem falta de guarda numerica: e trabalho do',
      '  auditor, e reporta-lo aqui duplica fila sem acrescentar nada.',
      'NAO proponha metodologia alternativa sem dizer o que ela CUSTA em dado',
      '  de entrada. Metodo que exige serie que o projeto nao tem e proposta',
      '  vazia.',
    ],
    materiais: [
      {
        tipo: 'diretorio',
        caminho: 'packages/equisim_core/lib/src/usecases',
        extensoes: ['.dart'],
      },
      {
        tipo: 'diretorio',
        caminho: 'packages/equisim_core/lib/src/services',
        extensoes: ['.dart'],
      },
      { tipo: 'arquivo', caminho: 'docs/AUDITORIA_DE_CALCULOS.md' },
      {
        tipo: 'diretorio',
        caminho: 'test/qa_fixtures',
        extensoes: ['.json'],
        opcional: true,
      },
    ],
  },

  // -------------------------------------------------------------------------
  risco: {
    id: 'risco',
    titulo: 'Risco nao coberto',
    pergunta: [
      'Que caminho de calculo ou de erro nao tem teste? Onde a suite da FALSA',
      'sensacao de cobertura -- testa o caminho feliz de algo cuja falha e o',
      'que importa?',
    ].join('\n'),
    disciplina: [
      'Esta lente e DIFERENCA DE CONJUNTOS. Toda lacuna nomeia o arquivo que',
      '  esta coberto e o caminho que nao esta.',
      'NAO peca cobertura por cobertura. Codigo trivial sem teste nao e risco;',
      '  caminho de dinheiro ou de erro sem teste, e.',
      'NAO conte testes. Numero de testes nao e medida de risco coberto.',
    ],
    materiais: [
      {
        tipo: 'arvore',
        raizes: ['lib', 'packages/equisim_core/lib', 'test', 'packages/equisim_core/test'],
      },
      { tipo: 'diretorio', caminho: 'test', extensoes: ['.dart'], excluir: GERADOS },
      {
        tipo: 'diretorio',
        caminho: 'packages/equisim_core/test',
        extensoes: ['.dart'],
      },
    ],
  },

  // -------------------------------------------------------------------------
  rumo: {
    id: 'rumo',
    titulo: 'Rumo do projeto',
    pergunta: [
      'O que foi decidido e nao foi entregue? O que e divida assumida e o que',
      'e esquecimento? Qual o proximo passo com maior retorno para o objeto',
      'deste trabalho -- que e o ESTUDO, nao o aplicativo?',
    ].join('\n'),
    disciplina: [
      'Esta e a lente mais propensa a produzir backlog generico, entao a',
      '  disciplina e a mais dura: TODA proposta cita uma DECISAO NUMERADA e um',
      '  ARQUIVO do repositorio. Faltando qualquer um dos dois, descarte.',
      'NAO proponha recurso novo de produto. A pergunta e sobre divida entre o',
      '  decidido e o entregue, nao sobre o que mais o aplicativo poderia fazer.',
      'NAO repita o que outra lente ja cobre melhor. Modelagem e da `nucleo`,',
      '  cobertura e da `risco`, integridade documental e da `registro`.',
    ],
    materiais: [
      { tipo: 'diretorio', caminho: 'docs/decisoes', extensoes: ['.md'], opcional: true },
      { tipo: 'arquivo', caminho: 'docs/estado.md', opcional: true },
      { tipo: 'arquivo', caminho: 'README.md' },
      { tipo: 'arvore', raizes: ['lib', 'packages', 'test'] },
      { tipo: 'git-log', quantidade: 40 },
    ],
  },

  // -------------------------------------------------------------------------
  tela: {
    id: 'tela',
    titulo: 'Direcao visual e arquitetura de informacao',
    precisaDeCapturas: true,
    pergunta: [
      'O que compete por atencao em cada tela? O que a disposicao diz que este',
      'aplicativo E -- e isso bate com o que ele faz? Um usuario que abre a',
      'tela sabe qual e a tarefa principal dela sem ler tudo?',
    ].join('\n'),
    disciplina: [
      'Toda observacao NOMEIA um elemento visivel na captura e o liga a tarefa',
      '  primaria daquela tela.',
      'Sombra, gradiente, animacao e arredondamento sao POLIMENTO, nao direcao.',
      '  Se a tensao e sobre um deles, ela nasce POLIMENTO.',
      'NAO proponha pacote de UI de terceiros. A correcao usa o sistema proprio',
      '  em `lib/presentation/theme/`.',
    ],
    materiais: [
      { tipo: 'arquivo', caminho: 'lib/presentation/shell/app_shell.dart' },
      { tipo: 'arvore', raizes: ['lib/presentation', 'lib/views'] },
    ],
  },
};

/** Lentes utilizaveis agora, na ordem em que fazem sentido rodar. */
export const ORDEM_SUGERIDA: LenteId[] = [
  'registro',
  'nucleo',
  'dados',
  'metodo',
  'risco',
  'rumo',
  'tela',
];

export function resolverLente(nome: string): Lente {
  const lente = (LENTES as Record<string, Lente | undefined>)[nome];
  if (!lente) {
    throw new Error(
      `Lente desconhecida: "${nome}".\n` +
        `Disponiveis: ${ORDEM_SUGERIDA.join(', ')}`,
    );
  }
  return lente;
}
