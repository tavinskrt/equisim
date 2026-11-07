/**
 * O histórico de versões do Equisim, na ordem da mais recente para a mais
 * antiga. É a fonte única: o `CHANGELOG.md` da raiz é gerado a partir daqui
 * (`npm run changelog`), e a tela de novidades lê este mesmo arquivo.
 *
 * O formato segue o Keep a Changelog 1.1.0 (https://keepachangelog.com/pt-BR/1.1.0/)
 * e a numeração, o Versionamento Semântico 2.0.0 (https://semver.org/lang/pt-BR/).
 * O que conta como interface pública, e portanto o que decide entre MAJOR,
 * MINOR e PATCH, está em `versioningPolicy`.
 *
 * Cada item é escrito para quem usa o produto: diz o que mudou na avaliação,
 * na simulação ou na tela, e não onde mudou no código.
 */

/** As quatro categorias de mudança, na ordem em que aparecem em cada versão. */
export type ChangeKind = 'added' | 'changed' | 'removed' | 'fixed';

export const changeKinds: readonly ChangeKind[] = ['added', 'changed', 'removed', 'fixed'];

/** O rótulo de cada categoria, em português, como no Keep a Changelog traduzido. */
export const changeKindLabel: Record<ChangeKind, string> = {
  added: 'Adicionado',
  changed: 'Alterado',
  removed: 'Removido',
  fixed: 'Corrigido',
};

export type Changes = Partial<Record<ChangeKind, readonly string[]>>;

export interface Release {
  /** `MAJOR.MINOR.PATCH`, sem o `v`. */
  readonly version: string;
  /** Data da publicação, `AAAA-MM-DD` (ISO 8601). */
  readonly date: string;
  /** O tema da versão, em poucas palavras. */
  readonly title: string;
  readonly changes: Changes;
}

/** Como o projeto lê o Versionamento Semântico. */
export const versioningPolicy = {
  publicInterface:
    'A interface pública do Equisim é o que o usuário guarda e o que ele lê como resultado: as carteiras, metas, acompanhamentos e valuations gravados, e o método que produz o preço justo.',
  major:
    'MAJOR quando a plataforma ou o método de avaliação é reconstruído de ponta a ponta, ou quando o que o usuário gravou deixa de ser lido como antes.',
  minor:
    'MINOR quando uma funcionalidade entra, muda ou sai, ou quando uma regra de cálculo muda, mantendo legível tudo o que o usuário gravou.',
  patch: 'PATCH quando a versão só corrige defeito, sem funcionalidade nova.',
  zero: 'As versões 0.x foram o desenvolvimento inicial, em que tudo podia mudar a qualquer momento.',
} as const;

/**
 * O que já está no código e ainda não saiu numa versão. Vazio na maior parte
 * do tempo: quando uma versão é publicada, os itens daqui passam para ela.
 */
export const unreleased: Changes = {};

export const changelog: readonly Release[] = [
  {
    version: '2.5.0',
    date: '2026-11-07',
    title: 'Histórico de versões no aplicativo',
    changes: {
      added: [
        'Item Changelog no menu do perfil, logo abaixo da troca de tema, que abre o histórico de versões com as datas e as mudanças de cada uma, separadas em Adicionado, Alterado, Removido e Corrigido.',
        'Comando Ver o changelog na busca global (Ctrl/⌘ + K).',
        'Número da versão em uso no menu do perfil e na tela Meu perfil.',
      ],
      changed: [
        'A documentação técnica do motor e o guia de estudo passam a descrever cada regra como ela vale hoje, sem depender da leitura de registros anteriores.',
      ],
    },
  },
  {
    version: '2.4.0',
    date: '2026-11-06',
    title: 'Backtest de compra única e interface unificada',
    changes: {
      changed: [
        'O Backtest compra uma ação de cada ativo da carteira, no lote do mercado fracionário, ao fechamento do primeiro pregão da janela, com a tarifa da B3, e não compra mais nada: o investido é exatamente o que as ações e a tarifa custaram.',
        'Cada ativo pesa na carteira o próprio preço sobre a soma dos preços, e o peso deriva com o mercado, sem rebalanceamento.',
        'A evolução comparada do Backtest mostra o patrimônio em reais, com o eixo a partir do zero; a base 100 continua disponível na exportação em CSV.',
        'Unificação da interface no modo completo: o Raio-X e o Backtest passam a exibir permanentemente todas as métricas, gráficos de dispersão e correlação, projeções e sensibilidade, removendo a alternância entre os modos Essencial e Completo.',
      ],
      removed: [
        'Aportes, XIRR, caixa e peso-alvo do Backtest, que deixaram de ter função com a compra única.',
        'A alternância Essencial/Completo do cabeçalho, da tela Meu perfil e da busca global.',
      ],
    },
  },
  {
    version: '2.3.0',
    date: '2026-11-05',
    title: 'Acompanhamento da carteira na Meta',
    changes: {
      added: [
        'Acompanhamento da carteira realizada na Meta: a partir da data de início e do dia de aporte escolhidos, cada aporte compra ações inteiras do ativo de maior potencial entre os que pesam menos que o dobro do peso igual, e a carteira é comparada mês a mês com o exigido pela meta, o esperado, o CDI e o Ibovespa.',
        'As compras do acompanhamento ficam gravadas, e a curva mostra o patrimônio realizado contra a trajetória que a meta pede.',
        'Explicações curtas para os conceitos do Estudo, da Meta e do Backtest que apareciam sem definição.',
      ],
      changed: [
        'A carteira Principal do Estudo é sempre equiponderada: incluir ou tirar um ativo reequipondera, e um estudo gravado com outros pesos abre equiponderado.',
        'Cada linha de ativo do Estudo ocupa uma linha só, também no celular.',
        'Textos repetidos do Estudo, da Meta e do Backtest foram enxugados.',
      ],
      removed: [
        'A coluna Peso e o botão Equiponderar do Estudo.',
        'O retorno esperado da carteira, o cartão Carteira frente à meta e a curva do esperado; a Meta passa a confrontar a carteira pelo que ela fez, no acompanhamento.',
        'O aviso de concentração setorial e o resumo do alto do Estudo.',
      ],
    },
  },
  {
    version: '2.2.0',
    date: '2026-10-29',
    title: 'Raio-X em página própria e novos gráficos',
    changes: {
      added: [
        'O Raio-X passa a ter página própria por ativo, com botão Voltar, logo, nome, setor e a entrada no estudo; o endereço pode ser compartilhado, e no computador um índice lateral marca a seção à vista.',
        'Movimento curto na interface: as áreas e os cartões entram em sequência, os números da leitura contam até o valor, as etapas da avaliação aparecem em texto enquanto o motor calcula e o cartão da leitura inclina levemente com o mouse. Tudo respeita a preferência de movimento reduzido do sistema.',
        'Curva de acumulação da Meta num gráfico de linha novo, com leitura do valor de cada mês ao passar o cursor.',
      ],
      changed: [
        'A evolução comparada do Backtest passa ao mesmo gráfico de linha da Meta; o risco × retorno continua no gráfico de dispersão.',
      ],
      fixed: [
        'Excluir a conta apaga todos os dados dela na nuvem — estudos, valuations confirmados e simulações — e exige a senha atual antes de apagar qualquer coisa; se a senha está errada, nada é apagado.',
        'O intermediário que protege a chave da fonte de cotações aceita apenas os endereços previstos, e as regras de acesso garantem que cada usuário leia e grave só as próprias carteiras.',
        'O site publicado passa a enviar cabeçalhos de segurança do navegador.',
      ],
    },
  },
  {
    version: '2.1.0',
    date: '2026-10-28',
    title: 'Lucro do ano corrente e logos',
    changes: {
      added: [
        'A logo da empresa acompanha o ticker em toda a interface, com as iniciais no lugar quando a imagem não carrega.',
      ],
      changed: [
        'O lucro de partida da avaliação é o do ano corrente anualizado quando já há balanço trimestral (ITR) publicado depois do último anual (DFP): o acumulado do ano vezes 12 ÷ meses, com o balanço na data do trimestre.',
      ],
    },
  },
  {
    version: '2.0.0',
    date: '2026-10-25',
    title: 'Equisim na web',
    changes: {
      added: [
        'Aplicativo web, que abre em qualquer navegador moderno e funciona sem conta, com os dados guardados no próprio navegador.',
        'Busca global (Ctrl/⌘ + K) para abrir qualquer ativo, ir a uma área ou executar um comando.',
        'Frase-resumo da avaliação no alto do Raio-X: distância abaixo de 10% entre o preço e o preço justo é lida como perto, e a partir de 100% como sinal a investigar.',
        'Alternância entre os modos Essencial e Completo no Raio-X e no Backtest.',
      ],
      changed: [
        'A plataforma passa a ser web de ponta a ponta. O método de avaliação não muda: o motor novo foi conferido número a número contra o anterior, em 371 ativos e treze montagens da avaliação, sem nenhuma divergência.',
        'Carteiras, valuations confirmados e preferências gravados na conta continuam valendo na versão web.',
        'Os pacotes de dados (CVM, B3, curva do Tesouro e validação) acompanham o site publicado.',
      ],
      removed: [
        'O aplicativo nativo anterior, substituído pela versão web.',
      ],
    },
  },
  {
    version: '1.10.0',
    date: '2026-10-22',
    title: 'Valuations confirmados',
    changes: {
      added: [
        'O valuation confirmado pelo usuário é gravado com as premissas, o resultado e a decomposição contra o motor, e aparece no Painel de Logs de Cálculo.',
        'O cartão Seus valuations salvos, na avaliação de cada ativo, e o filtro Valuations confirmados no Painel de Logs.',
        'Na lista de ativos do Estudo, o valuation do usuário substitui o do motor quando discorda dele, marcado como seu, com o potencial contra a cotação de hoje.',
      ],
    },
  },
  {
    version: '1.9.0',
    date: '2026-10-14',
    title: 'Simular minhas premissas',
    changes: {
      added: [
        'Simular minhas premissas: o usuário refaz a conta do motor com os próprios números — lucro de partida, crescimento, taxa de desconto e as demais premissas —, partindo da conta exata que o motor fez, e vê o que o preço de hoje supõe. O preço justo do motor continua o validado.',
      ],
      changed: [
        'A sensibilidade passa a um cartão só, com os três conjuntos nomeados pelas premissas — Premissas mais duras, Premissas do motor e Premissas mais brandas — e o quanto foi mexido em nota.',
        'Quando as premissas mais brandas dão preço menor que as mais duras, o cartão explica que a empresa rende abaixo do custo de capital e que crescer destrói valor.',
      ],
    },
  },
  {
    version: '1.8.0',
    date: '2026-10-02',
    title: 'Prêmio implícito e controle estatal',
    changes: {
      added: [
        'Ressalva de controle estatal na avaliação, a partir do Formulário Cadastral da CVM, sem mudar o preço justo.',
        'Documentação do motor regra por regra, com a fórmula, a teoria e a evidência de cada uma, e um guia de estudo para quem não é de finanças.',
      ],
      changed: [
        'O prêmio de mercado do CAPM passa a ser a média de dez anos do prêmio implícito no preço da bolsa, a mesma para todo ativo; sem a série, vale o prêmio parametrizado de 5,5%, e a avaliação diz isso.',
        'Sem o par valor patrimonial por ação e contagem do exercício, a base de patrimônio é o patrimônio líquido da demonstração.',
      ],
      fixed: [
        'A contagem de ações por data das coortes de validação é conferida contra o salto do preço, com âncora na contagem mais recente.',
        'A consulta de proventos da B3 voltou a trazer o histórico de sete emissores que vinham sem nenhum provento.',
      ],
    },
  },
  {
    version: '1.7.0',
    date: '2026-09-25',
    title: 'Rastro íntegro e eventos de ações',
    changes: {
      added: [
        'Réplica fora da amostra pré-registrada: as previsões de três coortes ficam seladas antes de o desfecho existir, e a leitura só é liberada na data marcada.',
      ],
      changed: [
        'O rastro que o Painel de Logs exporta é íntegro: sempre serializável, completo, e emitido por toda saída da avaliação, inclusive as recusas.',
        'Capital emitido depois do último balanço entra no patrimônio da avaliação quando o valor está declarado, e é avisado quando não está.',
        'Desdobramentos, grupamentos e bonificações que a fonte de preços não ajustou passam a ser ajustados na série do beta, na faixa calibrada e no retorno das coortes.',
      ],
      fixed: [
        'Proventos com a mesma data ex entram juntos no retorno total, em vez de um descontar o outro.',
        'Uma mudança de base na série de preços apaga o ativo inteiro do cache, e não só parte dele.',
        'A cópia dos insumos da avaliação não perde campo algum entre uma etapa e outra.',
      ],
    },
  },
  {
    version: '1.6.0',
    date: '2026-09-22',
    title: 'Múltiplos de pares e custos de transação',
    changes: {
      added: [
        'Triangulação por múltiplos de pares — P/L, P/VP e EV/EBITDA contra a mediana do subsetor — como segunda leitura declarada, que não entra no preço justo.',
        'Tarifa da B3 na simulação, de 0,030% por compra, com a linha Custos na tela.',
        'Aviso quando o beta foi estimado numa janela mais curta que a pedida.',
        'Declaração do peso do valor terminal no preço justo e da origem do beta e da estrutura de capital na perpetuidade.',
      ],
      changed: [
        'O beta de referência do setor acompanha o aplicativo, e o custo de capital é resolvido contra a alavancagem que a própria avaliação produz.',
        'Os pesos do WACC usam a dívida líquida, como o resto do modelo, e o caixa rende a taxa livre de risco, e não o custo de empréstimo.',
        'O juro e o rendimento do caixa de cada ano seguem a curva de juros, como o custo do capital próprio.',
        'O cálculo do custo de capital é tentado de dois pontos de partida, e só é recusado quando nenhum deles fecha.',
        'A razão de unidade das units sai da composição declarada à CVM, e a medida no valor de mercado vira conferência.',
        'O cenário de desconto move o custo do capital próprio um a um.',
        'Sem despesa financeira publicada, o prêmio de crédito sai da alavancagem.',
        'Os valores em dinheiro arredondam pelo decimal escrito, e as mensagens de erro dizem o número que violou a regra.',
        'As coortes de validação leem a versão de cada demonstração que era pública na data delas.',
      ],
    },
  },
  {
    version: '1.5.0',
    date: '2026-09-16',
    title: 'Deslistadas e habilidade medida',
    changes: {
      added: [
        'Empresas deslistadas entram nas coortes de validação, cada uma com o que existia na data, contra o viés de sobrevivência.',
        'A tela de metas diz, com o número medido, que o prêmio tirado do potencial ainda não tem habilidade comprovada.',
      ],
      changed: [
        'A faixa calibrada sai do preço, da volatilidade do papel e do preço justo com o peso medido, e é recalibrada com as deslistadas.',
        'A estatística t da habilidade é corrigida pela sobreposição das coortes.',
        'Nenhuma avaliação muda de via no meio da conta: a via da firma avalia o capital próprio pelo fluxo do acionista derivado.',
        'Sem ordenação comprovada, o retorno esperado de cada ativo é o custo do capital próprio dele, sem prêmio.',
      ],
    },
  },
  {
    version: '1.4.0',
    date: '2026-09-14',
    title: 'CVM, curva do Tesouro e faixa calibrada',
    changes: {
      added: [
        'Curva de juros dos prefixados do Tesouro como taxa livre de risco padrão: cada ano da projeção desconta ao forward daquele ano, com prazo em dias úteis pelo calendário brasileiro.',
        'Pacote das demonstrações da CVM embarcado no aplicativo, versionado, com aviso quando a avaliação segue sem ele.',
        'Ponte entre ticker e CNPJ pelo registro oficial da B3, e contagem oficial de ações líquida de tesouraria como divisor por papel.',
        'Setor pela classificação oficial da B3, por emissor.',
        'Eventos de ações inferidos da série histórica da B3 e contagem de ações por data pelo Formulário de Referência.',
        'Prazo das concessões lido do Formulário de Referência: o excedente sobre o capital termina no fim do contrato.',
        'Faixa calibrada fora da amostra como medida de incerteza do preço justo, em 12 e 36 meses.',
        'Proventos da B3, conferidos, no retorno total das coortes de validação e do beta; a simulação da carteira continua sem provento.',
      ],
      changed: [
        'A ingestão da CVM lê o período e o tipo de cada documento (anual ou trimestral).',
        'A base de patrimônio da avaliação é o patrimônio líquido da CVM.',
        'A banda de cenários passa a se declarar sensibilidade, e não probabilidade.',
      ],
      fixed: [
        'A mescla de fontes não empresta fluxo de outro exercício, e documento recebido depois da data não ocupa o ano.',
        'Falha na cotação corrente e ativo omitido por um lote recorrem ao cache vencido, como as demais falhas.',
      ],
    },
  },
  {
    version: '1.3.0',
    date: '2026-09-11',
    title: 'Dados da CVM e beta medido',
    changes: {
      added: [
        'Demonstrações da CVM mescladas às da fonte de mercado campo a campo, com a procedência de cada campo registrada.',
        'Base reconstruída pelo ciclo quando o exercício corrente vem no prejuízo, em vez de descartar a empresa.',
      ],
      changed: [
        'O beta é desalavancado pela dívida líquida sobre o valor de mercado, medida na janela em que foi estimado, e pelo mesmo escudo fiscal com que é realavancado.',
        'O crescimento perpétuo tem piso de −5%, o da banda de sanidade, e teto no crescimento nominal da economia.',
        'O retorno esperado transversal ancora no custo do capital próprio, e não no CDI.',
        'O retorno do Ibovespa usa médias de um trimestre nas pontas.',
        'A tolerância da razão de unidade das units passa a ser relativa, de 5%.',
        'O retorno por ativo do Backtest diz que mede o dinheiro aplicado, com o tamanho da diferença para o retorno de preço.',
      ],
      removed: [
        'A leitura da lacuna da meta como dividend yield: o retorno esperado já é total.',
      ],
      fixed: [
        'Exercício publicado sem demonstração de resultado sai da série, e a recusa nomeia a causa certa.',
        'Falha em qualquer demonstrativo reprova a busca inteira, em vez de seguir com dado parcial.',
        'Conta ausente no plano de contas da CVM (como o EBIT de um banco) fica ausente, e não vira zero.',
        'A contagem de ações da CVM, que não tem escala declarada, não entra no divisor; entra só a fração em tesouraria.',
        'O cache dos indicadores macroeconômicos só vale quando cobre a janela pedida.',
      ],
    },
  },
  {
    version: '1.2.0',
    date: '2026-09-10',
    title: 'Custo de capital resolvido ano a ano',
    changes: {
      added: [
        'Custo de capital resolvido ano a ano contra a alavancagem projetada: o beta é realavancado e o WACC recalculado até o valor parar de mudar.',
        'Beta encolhido por precisão em direção ao beta do setor (Vasicek), com o erro-padrão da estimativa.',
        'Convenção de meio de ano no desconto: o caixa do exercício chega ao longo do ano.',
      ],
      changed: [
        'O fluxo da firma é tributado pela alíquota estrutural do ativo, a mediana das alíquotas efetivas publicadas.',
        'O peso entre a via da firma e a do acionista é contínuo na participação do capital próprio, e não um degrau.',
        'O capital próprio passa a vir do fluxo do acionista derivado do fluxo da firma.',
        'O veredito de vantagem competitiva é refeito contra a taxa de equilíbrio resolvida, até estabilizar.',
        'O crescimento projetado fica limitado ao que o retorno sobre o capital financia.',
        'A participação dos não controladores sai do capital próprio, e a equivalência patrimonial deixa de ser tributada duas vezes.',
        'Contrato de prazo determinado não recebe excedente de retorno perpétuo, e a perpetuidade fica declarada como premissa.',
      ],
      fixed: [
        'Estrutura de capital que não fecha deixa de virar preço por interpolação: a avaliação diz que foi recusada.',
      ],
    },
  },
  {
    version: '1.1.0',
    date: '2026-09-09',
    title: 'Validação preditiva',
    changes: {
      added: [
        'Validação preditiva fora da amostra: a avaliação refeita com o que era público em oito coortes anuais, de 2018 a 2025, confrontada com o retorno realizado em 12 e 36 meses.',
        'Diagnósticos estruturados no resultado da avaliação.',
        'DCF reverso: o retorno terminal, o prêmio de risco ou o nível de juros que igualaria o preço justo ao de mercado.',
      ],
      changed: [
        'O divisor por papel é a contagem que forma a cotação; quando as contagens publicadas divergem, vale a maior.',
        'O prêmio de crédito tem dois direcionadores — alavancagem e cobertura de juros —, e a despesa financeira decide qual deles pode falar.',
        'A vantagem competitiva decai pela persistência medida do excedente do próprio ativo, e não por um corte fixo.',
        'A participação do capital próprio que escolhe a via é medida na taxa estrutural, e não na do dia.',
      ],
    },
  },
  {
    version: '1.0.0',
    date: '2026-09-07',
    title: 'Novo motor de avaliação',
    changes: {
      added: [
        'Motor de avaliação em cascata: elegibilidade por liquidez, histórico e solvência; instituições financeiras avaliadas pelo fluxo do acionista; verificação de que o fluxo da firma sustenta perpetuidade; e base e taxa atribuídas em duas saídas independentes.',
        'Duas vias de avaliação: a da firma, que desconta o lucro operacional após impostos ao WACC, e a do acionista, que desconta o lucro ao custo do capital próprio.',
        'Crescimento fundamental, igual ao retorno sobre o capital vezes o reinvestimento, com os limiares tirados da estatística do próprio ativo.',
        'Normalização da base pelo ciclo, com precedência do ciclo em commodities e cíclicos pesados.',
        'Trava de saúde operacional: queda de lucro ou EBITDA acima de 50% no triênio impede normalizar a base para cima, salvo nos setores cíclicos, e barra a vantagem competitiva.',
      ],
      changed: [
        'O horizonte de convergência do potencial passa de 12 para 36 meses.',
        'A vantagem competitiva exige retorno do ciclo de ao menos 1,5 vez o custo de capital, ou 5 pontos percentuais acima dele, com no mínimo oito exercícios de histórico.',
      ],
      removed: [
        'Os limiares fixos do motor anterior, substituídos pela estatística de cada ativo.',
      ],
    },
  },
  {
    version: '0.3.0',
    date: '2026-09-02',
    title: 'Simulação por ações inteiras',
    changes: {
      changed: [
        'A simulação compra ações inteiras; a sobra de cada aporte fica em caixa por ativo e entra no aporte seguinte.',
        'O fluxo descontado é o lucro por ação vezes a parcela não retida, com a retenção derivada do crescimento sustentável; sem retorno sobre o patrimônio utilizável, vale o valor do lucro estacionário.',
      ],
      removed: [
        'Proventos da simulação da carteira e da avaliação.',
      ],
      fixed: [
        'A divisão de cada aporte entre os ativos distribui o resto em centavos, e o total investido reconstitui o aportado exatamente.',
      ],
    },
  },
  {
    version: '0.2.0',
    date: '2026-08-30',
    title: 'Sistema de design e acessibilidade',
    changes: {
      added: [
        'Sistema de design próprio, com cores, tipografia e espaçamento padronizados, e contraste de texto medido segundo a WCAG.',
        'Telas conferidas em larguras de 320 a 1024 pixels e com o texto ampliado até 200%.',
        'Painel de Logs de Cálculo, para conferir a apuração de cada número da avaliação.',
      ],
      changed: [
        'As telas de operação foram reorganizadas na disposição e na arquitetura de informação.',
      ],
    },
  },
  {
    version: '0.1.0',
    date: '2026-08-19',
    title: 'Primeira versão registrada',
    changes: {
      added: [
        'Avaliação de ações da B3 por fluxo de caixa descontado, com o custo de capital pelo CAPM e o prêmio de mercado parametrizado.',
        'Meta patrimonial definida por aporte inicial, aporte mensal, prazo e valor final, com a rentabilidade exigida calculada.',
        'Simulação histórica de carteiras de até 15 ativos, sem rebalanceamento: os pesos de entrada derivam com o mercado.',
        'Horizonte de convergência do potencial de 12 meses, declarado no resultado.',
        'Defasagem de publicação de 90 dias, para que a simulação use só as demonstrações que já eram públicas em cada data.',
        'Proventos na simulação, na base bruta de divulgação, com o imposto de 15% retido sobre os juros sobre capital próprio.',
      ],
      changed: [
        'As simulações gravadas passam a morar junto das carteiras.',
      ],
      removed: [
        'Fundos imobiliários e o índice IFIX: o escopo é de ações.',
        'Os efeitos sonoros da interface.',
      ],
    },
  },
];

/** A versão mais recente publicada. */
export const latestRelease: Release = changelog[0]!;
