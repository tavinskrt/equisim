import type { HintEntry } from '../../ui/hint';

/**
 * Glossário dos indicadores das carteiras. Fora do componente porque as duas
 * carteiras exibem exatamente os mesmos números: texto duplicado é convite para
 * as duas explicações divergirem.
 */
export const metricsGlossary: readonly HintEntry[] = [
  {
    term: 'Patrimônio final',
    meaning: 'Quanto a cesta comprada valeria ao fim do período: uma ação de cada ativo, a preço de mercado. A diferença entre ele e o investido é o ganho.',
  },
  {
    term: 'Investido',
    meaning:
      'O que a cesta custou no primeiro pregão da janela: uma ação de cada ativo, pelo mercado fracionário, mais a tarifa da B3. É a única compra da simulação — não há aporte depois —, e por isso não sobra caixa. As duas carteiras custam valores diferentes, porque têm ativos e preços diferentes.',
  },
  {
    term: 'TWR — retorno ponderado pelo tempo',
    meaning:
      'Rentabilidade da cesta no período. É por ele que Principal e Reserva se comparam: é uma taxa, e não depende de quanto cada cesta custou, então o que sobra de diferença é a escolha dos ativos. Sem aporte depois da compra, ele coincide com o retorno do investidor (XIRR), que por isso não aparece.',
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
    term: 'Investido → final',
    meaning:
      'O que a ação custou no primeiro pregão da janela, com a tarifa da B3, e quanto ela valia no último. A simulação compra uma ação de cada ativo, pelo mercado fracionário, e não compra mais nada.',
  },
  {
    term: 'Retorno',
    meaning:
      'Quanto o valor da ação mudou no período, sobre o que ela custou. É retorno de PREÇO: a simulação não distribui provento. Como as duas carteiras compram no mesmo pregão, os retornos são comparáveis entre Principal e Reserva — e, sem aporte no meio, este número é o do gráfico do ativo, menos a tarifa da compra.',
  },
];

/**
 * A Reserva muda de sentido entre as telas: no estudo é banco de candidatos;
 * na simulação, carteira paralela completa. Sem dizê-lo onde o número
 * aparece, o patrimônio dela se lê como dinheiro que se teria — e é falso.
 */
export const hypotheticalReserve =
  'A Reserva é um banco de candidatos; aqui ela é simulada como carteira inteira, com uma ação de cada ativo comprada no mesmo pregão da Principal. É o que torna a comparação possível — e faz do patrimônio dela um valor hipotético.';
