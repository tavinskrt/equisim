import type { HintEntry } from '../../ui/hint';

/**
 * Glossário dos indicadores das carteiras. Fora do componente porque as duas
 * carteiras exibem exatamente os mesmos números: texto duplicado é convite para
 * as duas explicações divergirem.
 */
export const metricsGlossary: readonly HintEntry[] = [
  {
    term: 'Patrimônio final',
    meaning:
      'Quanto a carteira valeria ao fim do período: as posições a preço de mercado mais o caixa que sobrou. Abaixo do valor vêm o aportado e o alocado — a diferença entre o patrimônio e o aportado é o ganho.',
  },
  {
    term: 'Aportado × alocado',
    meaning:
      'O aportado é o dinheiro que o investidor disponibilizou, e é o número que ele já conhece. O alocado é quanto disso virou ação, depois de cada aporte ser dividido pelos pesos da carteira. A diferença é o caixa: a sobra que não completou mais uma ação inteira e espera o aporte seguinte — nada se perde, e ela conta no patrimônio.',
  },
  {
    term: 'TWR — retorno ponderado pelo tempo',
    meaning:
      'Rentabilidade da composição, neutra ao cronograma de aportes. É por ele que Principal e Reserva se comparam: as duas recebem os mesmos aportes nas mesmas datas, então o que sobra de diferença é a escolha dos ativos.',
  },
  {
    term: 'XIRR — retorno ponderado pelo dinheiro',
    meaning: 'A rentabilidade que o investidor de fato obteve, porque considera quanto entrou e em que data. É este o número a confrontar com a meta.',
  },
  { term: 'CAGR', meaning: 'O TWR convertido em taxa média ao ano. Serve para comparar janelas de durações diferentes na mesma unidade.' },
  {
    term: 'Volatilidade',
    meaning: 'Desvio-padrão dos retornos diários, anualizado. Mede oscilação, não perda: uma carteira pode balançar muito e ainda terminar acima.',
  },
  { term: 'Máx. drawdown', meaning: 'A maior queda do topo ao fundo dentro do período. Responde quanto o investidor teria visto sumir no pior trecho.' },
  { term: 'Sharpe', meaning: 'Retorno acima do CDI dividido pela volatilidade total — quanto de prêmio cada unidade de oscilação entregou.' },
  { term: 'Sortino', meaning: 'Como o Sharpe, mas só a oscilação de queda entra na conta: não penaliza a volatilidade que trabalhou a favor.' },
  { term: 'Calmar', meaning: 'Retorno anualizado dividido pelo máximo drawdown — prêmio por unidade da pior queda enfrentada.' },
];

/** Glossário das colunas do desempenho por ativo. */
export const perAssetGlossary: readonly HintEntry[] = [
  {
    term: 'alvo → atual',
    meaning:
      'O peso estipulado quando o ativo entrou e o peso que ele tem ao fim do período. A simulação não rebalanceia: quem sobe passa a pesar mais sozinho.',
  },
  {
    term: 'Deriva (p.p.)',
    meaning: 'A distância entre os dois pesos, em pontos percentuais. Positiva quando o ativo ganhou espaço na carteira, negativa quando perdeu.',
  },
  {
    term: 'Cotas · destinado',
    meaning:
      'Quantas cotas a simulação acumulou no ativo e quanto capital ele recebeu dos aportes. A quantidade é INTEIRA: cada aporte compra o que couber em lotes de uma, ao preço do dia, e a sobra fica no caixa do ativo esperando o aporte seguinte.',
  },
  {
    term: 'Retorno',
    meaning:
      'Quanto o capital destinado àquele ativo rendeu no período, contando a posição a mercado mais o caixa dela. É retorno de PREÇO: a simulação não distribui provento. Como as duas carteiras rodam na mesma janela e sob o mesmo cronograma de aportes, os retornos são comparáveis entre Principal e Reserva.',
  },
  {
    term: 'Por que ele difere do gráfico do ativo',
    meaning:
      'Este número mede o que o SEU dinheiro fez, não o que o preço fez. Com aporte mensal, quem cai e volta rende — o aporte comprou barato no meio —, e quem sobe e volta perde. Dois ativos que começam e terminam no mesmo preço, um em vale e outro em pico, chegam aqui a 56,5 pontos percentuais de distância. As duas leituras são verdadeiras e respondem a perguntas diferentes; esta responde a que importa para a troca entre carteiras, porque é o dinheiro que de fato seguiu este cronograma.',
  },
];

/**
 * A Reserva muda de sentido entre as telas: no estudo é banco de candidatos;
 * na simulação, carteira paralela completa. Sem dizê-lo onde o número
 * aparece, o patrimônio dela se lê como dinheiro que se teria — e é falso.
 */
export const hypotheticalReserve =
  'A Reserva é um banco de candidatos; aqui ela é simulada como carteira inteira, sob os mesmos aportes da Principal. É o que torna a comparação possível — e faz do patrimônio dela um valor hipotético.';
