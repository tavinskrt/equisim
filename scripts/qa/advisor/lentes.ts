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
import type { LensId } from './schema.ts';

/**
 * Descritor de material.
 *
 * `optional` existe porque diretorio que ainda nao foi criado e estado normal
 * -- e nao motivo para abortar a execucao.
 */
export type Material =
  | { kind: 'arquivo'; filePath: string; optional?: boolean }
  | { kind: 'arvore-completa'; excludePrefixes?: string[] }
  | {
      kind: 'diretorio';
      filePath: string;
      extensions?: string[];
      exclude?: string[];
      optional?: boolean;
      /**
       * Do mais recente ao mais antigo, pela ordem inversa do nome. Serve a
       * pastas de arquivos datados ou numerados em sequencia: quando o payload
       * bate no teto, o corte leva os antigos, e nao os que acabaram de ser
       * escritos.
       */
      newestFirst?: boolean;
    }
  | { kind: 'arvore'; roots: string[] }
  /**
   * O que mudou contra o ultimo commit, e o novo ainda sem commit, sob
   * [roots]. Posto primeiro, garante que a lente leia o que a rodada mexeu
   * antes do corte do teto -- que e onde o codigo e o teste novos se perdiam.
   */
  | {
      kind: 'alterados';
      roots: string[];
      extensions?: string[];
      exclude?: string[];
    }
  | { kind: 'git-log'; count: number };

export interface Lens {
  id: LensId;
  /** Titulo legivel, para o cabecalho do relatorio. */
  title: string;
  /** O que o modelo esta sendo perguntado. Vai integral para o prompt. */
  question: string;
  /** Clausulas de descarte especificas desta lente. */
  discipline: string[];
  materials: Material[];
  /**
   * Depende de capturas de tela.
   *
   * Duas consequencias no runner: ele exige que `docs/telas/` exista (gere com
   * `npm run ui:capturar`) e FORCA o backend `api`, porque o `agy` recusa
   * imagem explicitamente -- ver `agy.ts`.
   */
  needsScreenshots?: boolean;
}

/**
 * Artefatos gerados: auditar declaracao de tipo gerada so gasta token. Mesmo
 * criterio do auditor. O TypeScript nao tem o `build_runner` do Dart, entao
 * sobra so o `.d.ts`.
 */
const GENERATED = ['*.d.ts'];

/** Codigo TypeScript, com e sem JSX. */
const TS = ['.ts', '.tsx'];

/**
 * O que a lente `metodo` le antes de tudo, na ordem do que mais pesa no preco
 * justo: a cascata, o custo de capital, o premio de mercado, a realavancagem,
 * o DCF e as guardas do crescimento, e so depois o resto.
 */
const METHOD_FIRST = [
  'src/core/usecases/compute-valuation.ts',
  'src/core/services/valuation/cost-of-capital.ts',
  'src/core/services/valuation/implied-premium.ts',
  'src/core/services/valuation/levered-rates.ts',
  'src/core/services/valuation/dcf.ts',
  'src/core/services/valuation/growth-guards.ts',
  'src/core/usecases/prepare-valuation-inputs.ts',
  'src/core/services/valuation/yield-curve.ts',
  'src/core/services/valuation/growth-estimator.ts',
  'src/core/services/valuation/capital-base.ts',
  'src/core/services/valuation/moat-fixed-point.ts',
  'src/core/services/valuation/scenario-engine.ts',
  'src/core/usecases/resolve-beta-prior.ts',
  'src/core/usecases/portfolio-usecases.ts',
];

/**
 * O que a lente `nucleo` le antes do resto do nucleo: o modelo do valuation e a
 * tela que o consome.
 *
 * **A ordem e a do corte**, como em [METHOD_FIRST]. Ate 11/10/2026 a lente
 * lia o nucleo (entao `packages/equisim_core/lib`, em Dart) em ordem
 * alfabetica, e o corte caia antes de `services/valuation/`: a conta congelada
 * do calculo do usuario (Simular minhas premissas) nunca chegava a ela, que respondia "nenhuma tensao" sem a ter lido. E a
 * pergunta dela -- que regra de negocio vazou para a apresentacao -- nao tinha
 * como ser respondida sem a tela: a do valuation e a que mais monta numero a
 * partir do dominio.
 */
const CORE_FIRST = [
  'src/core/entities/valuation.ts',
  'src/core/services/valuation/manual-valuation.ts',
  'src/copy/manual-copy.ts',
  'src/features/manual/manual-page.tsx',
  'src/copy/domain-copy.ts',
];

export const LENSES: Record<LensId, Lens> = {
  // -------------------------------------------------------------------------
  registro: {
    id: 'registro',
    title: 'Documentacao contra repositorio',
    question: [
      'Onde a DOCUMENTACAO do projeto -- README, CLAUDE.md, CHANGELOG.md e os',
      'capitulos de docs/motor/ e docs/estudo/ -- diverge da REALIDADE do',
      'repositorio?',
      '',
      'Classifique cada divergencia em uma destas cinco classes, e diga qual',
      'no campo `observation`:',
      '',
      '  REGRA DIVERGENTE -- o documento descreve uma regra de calculo, um',
      '    limiar ou um comportamento de tela que o repositorio nao tem mais, ou',
      '    nunca teve. A mais grave: quem le a documentacao aprende o errado.',
      '  CHANGELOG SEM LASTRO -- o changelog anuncia como entregue algo que o',
      '    repositorio nao mostra, ou a versao do package.json nao e a mais',
      '    recente do changelog.',
      '  MUDANCA SEM REGISTRO -- mudanca de funcionalidade, de calculo ou de',
      '    tela visivel no historico do git sem entrada no changelog, ou sem o',
      '    capitulo de docs/motor/ que a descreve.',
      '  MEDICAO VENCIDA -- numero medido cuja data ja nao sustenta a conclusao',
      '    que dele se tirou.',
      '  REFERENCIA QUEBRADA -- documento que cita arquivo, funcao ou secao que',
      '    nao existe na arvore.',
    ].join('\n'),
    discipline: [
      'Esta lente e DIFERENCA DE CONJUNTOS, nao opiniao. Toda divergencia',
      '  nomeia os DOIS lados: o que o documento diz e o que o repositorio tem.',
      'A documentacao descreve o sistema COMO ELE E HOJE, sem historico. Nao',
      '  proponha devolver a ela narrativa de mudanca ("antes era X"): o',
      '  historico mora no CHANGELOG.md, e so la.',
      'O changelog fala com quem USA o produto. Nao reporte que uma entrada',
      '  "nao cita o arquivo" ou "nao nomeia a funcao": e escolha deliberada.',
      'PROIBIDO INFERIR REGRA A PARTIR DE CODIGO QUE VOCE NAO RECEBEU. Esta',
      '  lente recebe a documentacao, a arvore e o log, e nao o codigo-fonte:',
      '  afirmar que um simbolo, arquivo ou linha "persiste" ou "nao faz o que o',
      '  documento diz" e afirmar o que voce nao viu. REGRA DIVERGENTE exige',
      '  evidencia no material: o log que mostra a mudanca, ou dois documentos',
      '  que se contradizem.',
      'ARQUIVO NAO LIDO NAO SE ACUSA. De `docs/validacao/` voce recebe apenas a',
      '  ARVORE -- os nomes. Os relatorios de la sao medicoes DATADAS, e citar',
      '  um deles como estado atual FABRICA divergencia. Sobre arquivo cujo',
      '  conteudo nao veio, o maximo e INVENTARIAR que ele existe.',
      'ARQUIVO CITADO NAO E ARQUIVO AUSENTE. Antes de dizer que um documento',
      '  falta, PROCURE o marcador "===== ARQUIVO: <caminho> =====" no material',
      '  e o caminho na arvore do repositorio, que vem junto. Se o caminho',
      '  aparece em qualquer um dos dois lugares, o arquivo EXISTE e a tensao',
      '  nao existe.',
      'NAO reporte ausencia de documentacao em geral. A pergunta e sobre',
      '  divergencia entre documento e realidade, nao sobre volume de texto.',
    ],
    // **A ordem e a do corte.** O pequeno e indispensavel vem antes -- o
    // changelog, o estado gerado, a arvore e o log --, e os capitulos longos
    // da documentacao por ultimo, para que o corte do teto leve o guia de
    // estudo antes de levar o que diz o que o repositorio tem.
    materials: [
      { kind: 'arquivo', filePath: 'README.md' },
      { kind: 'arquivo', filePath: 'CLAUDE.md' },
      { kind: 'arquivo', filePath: 'CHANGELOG.md' },
      { kind: 'arquivo', filePath: 'package.json' },
      { kind: 'arquivo', filePath: 'docs/estado.md', optional: true },
      // ARVORE COMPLETA, nao um subconjunto. Esta lente pergunta se a
      // documentacao bate com a realidade; mandar arvore parcial faz o modelo
      // ver ausencia onde ha apenas material nao enviado. Aconteceu: `tool/` e
      // `functions/` ficaram de fora de uma lista de raizes e viraram duas
      // tensoes ESTRUTURAL falsas.
      { kind: 'arvore-completa' },
      { kind: 'git-log', count: 40 },
      { kind: 'diretorio', filePath: 'docs/motor', extensions: ['.md'] },
      { kind: 'diretorio', filePath: 'docs/estudo', extensions: ['.md'], optional: true },
    ],
  },

  // -------------------------------------------------------------------------
  nucleo: {
    id: 'nucleo',
    title: 'Nucleo de dominio',
    question: [
      'As entidades do nucleo sao coesas? Que regra de negocio vazou para a',
      'camada de apresentacao? Que value object falta para eliminar uma classe',
      'de erro por construcao, em vez de por validacao?',
    ].join('\n'),
    discipline: [
      'PROIBIDO sugerir pacote de terceiros dentro de `src/core`. A pureza',
      '  e travada pelo teste `test/core/purity.test.ts` e nao esta em negociacao.',
      '`src/core/lang/` e o runtime que reproduz a semantica do Dart (`DateTime`,',
      '  `round`, `mod`, `Random`) para o porte 1:1 do nucleo Dart original. Ele e',
      '  infraestrutura do porte, e nao entidade: nao proponha trocar o',
      '  `DateTime` dele por `Date` sem mostrar um numero que mude.',
      'Toda proposta cita arquivo e tipo que EXISTEM no material.',
      'NAO proponha renomear por gosto. Nome so entra em tensao quando ele',
      '  descreve coisa diferente do que o tipo faz.',
      'Serializacao que acompanha o tipo (`toJson`/`fromJson`) e contrato do',
      '  proprio tipo, e nao infraestrutura vazada: antes de afirmar que um',
      '  valor e convertido "em memoria", confira se a conversao esta no',
      '  construtor ou so no `toJson`. So o primeiro altera o dado que o',
      '  calculo le.',
      'JA AVALIADO E DEIXADO DE FORA DE PROPOSITO: o tipo de data de',
      '  calendario no lugar do `DateTime` truncado, as listas paralelas de',
      '  `TotalReturnIndex.build` e as do diagnostico (`growthPath` e',
      '  `retentionPath`), e o `FundamentalsSnapshot` que carrega o valor de',
      '  mercado e a contagem de hoje ao lado do exercicio. Ficaram fora do',
      '  escopo em 14/09/2026, e voltaram em 21, 25 e 27/09/2026 sem fato novo.',
      '  So reaponte mostrando um numero que um deles erra.',
      'A `unit` de `CalculationTrace` (`R$`, `%`) e texto do rastro de',
      '  auditoria, em portugues por construcao, e nao rotulo de tela: a regra',
      '  "o nucleo diz a regra e a grandeza, a tela escreve o numero" governa o',
      '  que a apresentacao monta, e o rastro nao e tela.',
      '  Recusado em 27/09/2026.',
      'Contagem de acoes em `double` no `FundamentalsSnapshot` e no divisor',
      '  NAO e defeito de tipo: parte das contagens do motor e ESTIMATIVA',
      '  continua (valor de mercado dividido pelo preco, razao medida da unit),',
      '  e o dado que chega inteiro da fonte nao ganha fracao em conta nenhuma.',
      '  Recusado em 25/09/2026. So reaponte com um preco justo que a fracao',
      '  mude.',
    ],
    // O que a rodada mexeu vem antes até da lista acima (14/10/2026): o
    // registro da normalização e o painel que o explica não estavam nela, e a
    // lente respondeu "nenhuma tensão" sem lê-los.
    materials: [
      {
        kind: 'alterados',
        roots: ['src/core', 'src/copy', 'src/features'],
        extensions: TS,
        exclude: GENERATED,
      },
      ...CORE_FIRST.map((filePath) => ({ kind: 'arquivo' as const, filePath })),
      { kind: 'arquivo', filePath: 'test/core/purity.test.ts' },
      {
        kind: 'diretorio',
        filePath: 'src/core',
        extensions: TS,
        exclude: [...GENERATED, ...CORE_FIRST],
      },
      { kind: 'arquivo', filePath: 'docs/motor/README.md', optional: true },
    ],
  },

  // -------------------------------------------------------------------------
  dados: {
    id: 'dados',
    title: 'Camada de dados e resiliencia',
    question: [
      'O que acontece quando a API de mercado cai, estoura cota ou devolve',
      'serie incompleta? O cache, o retry e a degradacao entregam a contingencia',
      'que esta documentada -- ou apenas a que foi escrita?',
    ].join('\n'),
    discipline: [
      'Toda tensao e confrontada com o comportamento DOCUMENTADO em',
      '  docs/motor/01-insumos-e-dados.md. Divergencia entre documento e codigo',
      '  e achado; ausencia de recurso que ninguem documentou, nao e.',
      'NAO proponha trocar de cliente de rede ou de banco local. O cliente',
      '  proprio sobre `fetch` (`src/data/network/`), o cache em IndexedDB',
      '  (`idb-keyval`) e o Firestore sao a arquitetura da versao web: entraram',
      '  no lugar do Dio e do Drift, com os mesmos interceptores.',
      'NAO especule sobre comportamento da API que o material nao demonstre.',
      'O RetryInterceptor reemite pelo mesmo cliente e passa de novo pelo',
      '  ThrottleInterceptor, e isso NAO e deadlock: o onError dos',
      '  interceptores corre na ordem de insercao, e o limitador libera a vaga',
      '  antes de o repetidor reemitir. Apontado quatro vezes e conferido',
      '  quatro vezes; o teste "rajada acima do teto de concorrencia, toda com',
      '  429, nao trava" em test/data/network-and-quality.test.ts o prova, e',
      '  reprova quando a liberacao sai. So reaponte mostrando o caminho que',
      '  aquele teste nao cobre.',
      'O custo de um dado velho no cache depende de QUEM O LE, e quem le esta',
      '  no nucleo, fora deste material. Afirmar que ele contamina o calculo',
      '  exige citar o consumidor; sem isso, a tensao e no maximo LOCAL. Dois',
      '  ja conferidos (24/09/2026): os campos "de hoje" dos fundamentos',
      '  (`sharesOutstanding`, `marketCap`, `enterpriseToEbitda`) sao lidos so',
      '  do exercicio mais recente, que e o que a resposta renova; o volume, so da',
      '  janela de liquidez recente (`EligibilityGate.medianTradedValue`), e volume',
      '  ausente e omissao do teste, e nao reprovacao.',
    ],
    materials: [
      {
        kind: 'diretorio',
        filePath: 'src/data',
        extensions: TS,
        exclude: GENERATED,
      },
      { kind: 'arquivo', filePath: 'functions/index.js' },
      { kind: 'arquivo', filePath: 'test/data/network-and-quality.test.ts' },
      { kind: 'arquivo', filePath: 'firestore.rules', optional: true },
      { kind: 'arquivo', filePath: 'docs/motor/01-insumos-e-dados.md', optional: true },
    ],
  },

  // -------------------------------------------------------------------------
  metodo: {
    id: 'metodo',
    title: 'Metodo financeiro',
    question: [
      'A metodologia de DCF e CAPM implementada aqui e defensavel numa banca?',
      'Que premissa esta IMPLICITA no codigo e deveria estar explicita e',
      'justificada? Onde uma escolha metodologica foi feita sem que o codigo',
      'registre por que ela, e nao a alternativa?',
    ].join('\n'),
    discipline: [
      'Esta lente NAO caca bug -- disso o auditor cuida, e melhor. Aqui se',
      '  questiona PREMISSA. Toda observacao nomeia a premissa e o ponto onde',
      '  ela esta codificada.',
      'NAO reporte erro aritmetico nem falta de guarda numerica: e trabalho do',
      '  auditor, e reporta-lo aqui duplica fila sem acrescentar nada.',
      'NAO proponha metodologia alternativa sem dizer o que ela CUSTA em dado',
      '  de entrada. Metodo que exige serie que o projeto nao tem e proposta',
      '  vazia.',
      'PREMISSA JA MEDIDA NAO SE REABRE SEM EVIDENCIA NOVA. Quando o comentario',
      '  no codigo ou o capitulo de docs/motor/ cita a medicao da premissa',
      '  (efeito, conjunto exposto, alternativa comparada), reporta-la de novo so',
      '  procede se voce apontar o que a medicao NAO cobriu -- outro caminho de',
      '  codigo, outro subconjunto, outra condicao. Repetir a objecao que a',
      '  medicao ja respondeu e ruido: em 21 e 22/09/2026 esta lente reabriu tres',
      '  premissas medidas (Blume +0,1%, traducao do cenario, minoritario com',
      '  efeito 0,00%). Limitacao declarada SEM medicao continua reportavel.',
      'A traducao do cenario (`ScenarioTranslation`: o deslocamento vai ao Ke',
      '  um a um, e as outras duas leituras estao medidas em',
      '  docs/validacao/cenario.md) foi reaberta pela TERCEIRA vez em',
      '  24/09/2026, sem evidencia nova. Os cenarios sao sensibilidade, e nao a',
      '  incerteza: o que a tela mostra como incerteza e a faixa calibrada. So',
      '  reaponte com medicao que aquele relatorio nao fez.',
      'ESTRUTURAL exige conjunto exposto que pese. A via do acionista de',
      '  companhia NAO financeira atende 1 dos 97 avaliados do aplicativo',
      '  (24/09/2026), e as financeiras nao realavancam. Tensao sobre esse',
      '  caminho e no maximo LOCAL, a menos que voce mostre um conjunto maior.',
      'O escudo fiscal do WACC na aliquota estatutaria e deliberado: a',
      '  deducao do juro vale na margem, e a margem de quem esta no Lucro Real',
      '  e a aliquota cheia. O Lucro Presumido tem teto de receita que quase',
      '  nenhuma listada respeita. Recusado em 25/09/2026; so reaponte com uma',
      '  companhia avaliada que esteja no Presumido.',
      'PONTO FLUTUANTE NO DCF NAO E PREMISSA A REABRIR. Cotacao, contagem de',
      '  papeis e valores do fluxo descontado em ponto flutuante (`number`;',
      '  `double` no Dart de antes da versao web), convertidos para',
      '  `Money` uma vez, na fronteira, e o arranjo aceito pela regra R1 do',
      '  auditor ("NAO ACUSE -- caminho de calculo de fluxo descontado"): dez',
      '  iteracoes acumulam erro de 1e-14, e normalizar em centavos no meio',
      '  introduziria erro de meio centavo por ano. A acao inteira e regra da',
      '  SIMULACAO, e a contagem de papeis fracionaria serve a uma divisao.',
      '  Levantado e recusado em 28/09/2026; tambem nao e tema desta lente,',
      '  que questiona premissa financeira, e nao tipo.',
    ],
    // **A ordem e a do corte.** O payload tem teto, e o corte e por arquivo
    // inteiro, do fim para o comeco. Ate 01/10/2026 esta lente lia
    // `usecases/` e `services/` em ordem alfabetica, e o corte caia antes de
    // `services/valuation/` -- o custo de capital, a realavancagem, o DCF e o
    // premio de mercado implicito nunca chegavam a ela, que respondia
    // "nenhuma tensao" sobre o metodo sem te-lo lido. Primeiro o que define o
    // preco justo; dados da CVM, backtest e meta ficam de fora, porque nao sao
    // metodo de DCF nem de CAPM.
    //
    // **O que a rodada mexeu no metodo vem antes** (11/10/2026): o teto ja
    // estava cheio com a lista acima, e o calculo do usuario (Simular minhas
    // premissas), novo em `services/valuation/`, ficava fora -- a lente nao tinha como
    // julgar a metodologia dele. O alterado entra uma vez so, na primeira
    // posicao em que aparece.
    materials: [
      {
        kind: 'alterados',
        roots: ['src/core/services/valuation'],
        extensions: TS,
      },
      ...METHOD_FIRST.map((filePath) => ({ kind: 'arquivo' as const, filePath })),
      {
        kind: 'diretorio',
        filePath: 'src/core/services/valuation',
        extensions: TS,
        exclude: METHOD_FIRST,
      },
      {
        kind: 'diretorio',
        filePath: 'src/core/services/metrics',
        extensions: TS,
      },
      { kind: 'arquivo', filePath: 'docs/AUDITORIA_DE_CALCULOS.md' },
      {
        kind: 'diretorio',
        filePath: 'test/qa_fixtures',
        extensions: ['.json'],
        optional: true,
      },
    ],
  },

  // -------------------------------------------------------------------------
  risco: {
    id: 'risco',
    title: 'Risco nao coberto',
    question: [
      'Que caminho de calculo ou de erro nao tem teste? Onde a suite da FALSA',
      'sensacao de cobertura -- testa o caminho feliz de algo cuja falha e o',
      'que importa?',
    ].join('\n'),
    discipline: [
      'Esta lente e DIFERENCA DE CONJUNTOS. Toda lacuna nomeia o arquivo que',
      '  esta coberto e o caminho que nao esta.',
      'NAO peca cobertura por cobertura. Codigo trivial sem teste nao e risco;',
      '  caminho de dinheiro ou de erro sem teste, e.',
      'NAO conte testes. Numero de testes nao e medida de risco coberto.',
      'O `ValuationRunner` (`src/data/runner/`) avalia num Web Worker, e no',
      '  `error` e no `messageerror` do worker resolve quem espera com o recuo',
      '  para o calculo em linha: worker morto NAO trava quem espera. Em',
      '  01/10/2026 esta lente pediu um',
      '  `onExit` em volta do `compute` do Flutter, que ja completava com erro',
      '  pela `Isolate.run`; nao repita o pedido sobre o worker sem mostrar o',
      '  caminho que fica sem resposta.',
      'A tolerancia da fonte a JSON de forma errada numa rota -- as outras rotas',
      '  continuam entregando os exercicios -- e escolha deliberada desde',
      '  25/09/2026, e o cache nao grava nulo por cima',
      '  de valor bom. Reporta-la de novo contra a regra da falha so com evidencia',
      '  NOVA: um caminho em que a serie sem a demonstracao chega a um preco',
      '  justo, e nao so ao cache.',
    ],
    // **O que a rodada mexeu vem primeiro** (11/10/2026). A lente lia os dois
    // diretorios de teste em ordem alfabetica, e o corte do teto caia antes do
    // teste e do codigo novos: ela respondia "nenhum caminho sem teste" sobre o
    // calculo do usuario (Simular minhas premissas) sem ter lido nem um nem outro.
    materials: [
      {
        kind: 'arvore',
        roots: ['src', 'tool', 'test'],
      },
      // Os testes alterados antes do codigo alterado: o material desta lente e
      // o teste, e o arquivo de codigo grande -- `compute-valuation.ts` tem
      // um quarto do teto -- nao pode empurrar o teste novo para fora.
      {
        kind: 'alterados',
        roots: ['test'],
        extensions: TS,
        exclude: GENERATED,
      },
      {
        kind: 'alterados',
        roots: ['src', 'tool'],
        extensions: TS,
        exclude: GENERATED,
      },
      // Os testes do aplicativo antes dos do nucleo, na mesma ordem de quando
      // moravam em `test/` e `packages/equisim_core/test/`: e a ordem do corte.
      { kind: 'diretorio', filePath: 'test/data', extensions: TS, exclude: GENERATED },
      { kind: 'diretorio', filePath: 'test/app', extensions: TS, exclude: GENERATED },
      { kind: 'diretorio', filePath: 'test/audit', extensions: TS, exclude: GENERATED },
      { kind: 'diretorio', filePath: 'test/ui', extensions: TS, exclude: GENERATED },
      { kind: 'diretorio', filePath: 'test/tool', extensions: TS, exclude: GENERATED },
      { kind: 'diretorio', filePath: 'test/core', extensions: TS },
    ],
  },

  // -------------------------------------------------------------------------
  rumo: {
    id: 'rumo',
    title: 'Rumo do projeto',
    question: [
      'O que a documentacao declara como limitacao ou pendencia e continua',
      'aberto? O que e divida assumida e o que e esquecimento? Qual o proximo',
      'passo com maior retorno para o objeto deste trabalho -- que e o ESTUDO,',
      'nao o aplicativo?',
    ].join('\n'),
    discipline: [
      'Esta e a lente mais propensa a produzir backlog generico, entao a',
      '  disciplina e a mais dura: TODA proposta cita um TRECHO da documentacao',
      '  (limitacao declarada, capitulo do motor ou entrada do changelog) e um',
      '  ARQUIVO do repositorio. Faltando qualquer um dos dois, descarte.',
      'NAO proponha recurso novo de produto. A pergunta e sobre divida entre o',
      '  declarado e o entregue, nao sobre o que mais o aplicativo poderia fazer.',
      'NAO repita o que outra lente ja cobre melhor. Modelagem e da `nucleo`,',
      '  cobertura e da `risco`, integridade documental e da `registro`.',
      'Limitacao JA DECLARADA no proprio comentario do codigo ou na documentacao',
      '  nao e tensao por existir. Se o trecho que voce citaria como evidencia ja',
      '  diz "fica registrado como limitacao", ele esta cumprindo o que a lente',
      '  pede -- e reporta-lo e cobrar duas vezes a mesma coisa. So vira tensao',
      '  quando ha caminho concreto, com o arquivo, para fecha-la.',
      'O changelog diz o que FOI entregue, versao a versao. Uma entrada antiga',
      '  nao e pendencia: o que uma versao posterior alterou ou removeu manda',
      '  sobre a anterior. Antes de reportar que algo "continua" pendente,',
      '  confira as versoes mais recentes.',
    ],
    // **A ordem e a do corte**, como na `registro`: o estado, o changelog e as
    // limitacoes declaradas antes da arvore e do log.
    materials: [
      { kind: 'arquivo', filePath: 'docs/estado.md', optional: true },
      { kind: 'arquivo', filePath: 'CHANGELOG.md' },
      { kind: 'arquivo', filePath: 'docs/validacao/limitacoes.md', optional: true },
      { kind: 'arquivo', filePath: 'docs/motor/08-verificacao-e-validacao.md', optional: true },
      { kind: 'arquivo', filePath: 'README.md' },
      { kind: 'arvore', roots: ['src', 'tool', 'test'] },
      { kind: 'git-log', count: 40 },
    ],
  },

  // -------------------------------------------------------------------------
  tela: {
    id: 'tela',
    title: 'Direcao visual e arquitetura de informacao',
    needsScreenshots: true,
    question: [
      'O que compete por atencao em cada tela? O que a disposicao diz que este',
      'aplicativo E -- e isso bate com o que ele faz? Um usuario que abre a',
      'tela sabe qual e a tarefa principal dela sem ler tudo?',
    ].join('\n'),
    discipline: [
      'Toda observacao NOMEIA um elemento visivel na captura e o liga a tarefa',
      '  primaria daquela tela.',
      'Sombra, gradiente, animacao e arredondamento sao POLIMENTO, nao direcao.',
      '  Se a tensao e sobre um deles, ela nasce POLIMENTO.',
      'NAO proponha pacote de UI de terceiros. A correcao usa o sistema proprio',
      '  de tokens em `src/styles.css` e os componentes de `src/ui/`.',
    ],
    materials: [
      { kind: 'arquivo', filePath: 'src/features/shell/app-shell.tsx' },
      { kind: 'arvore', roots: ['src/features', 'src/ui'] },
    ],
  },
};

/** Lentes utilizaveis agora, na ordem em que fazem sentido rodar. */
export const SUGGESTED_ORDER: LensId[] = [
  'registro',
  'nucleo',
  'dados',
  'metodo',
  'risco',
  'rumo',
  'tela',
];

export function resolveLens(name: string): Lens {
  const lens = (LENSES as Record<string, Lens | undefined>)[name];
  if (!lens) {
    throw new Error(
      `Lente desconhecida: "${name}".\n` +
        `Disponiveis: ${SUGGESTED_ORDER.join(', ')}`,
    );
  }
  return lens;
}
