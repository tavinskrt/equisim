---
numero: 65
titulo: O retorno por ativo mede o dinheiro, e o rótulo passa a dizer quanto
status: aceita
origem: parecer
data: 2026-09-11
afeta:
  - packages/equisim_core/lib/src/services/backtest/portfolio_backtest.dart
  - lib/presentation/backtest/backtest_page.dart
  - docs/validacao/retorno_por_ativo.md
substitui: []
---

## Contexto

A lente `metodo` propôs substituir `AssetPerformance.totalReturn` — a razão
`(valor final + caixa − aportado) ÷ aportado` — por um TWR ou XIRR por ativo,
"isolado do cronograma de aporte".

A preocupação de fundo é que ativos com históricos diferentes fiquem
incomparáveis. **Esse canal está fechado duas vezes**, e a medição confirmou:
`PortfolioBacktest.run` recua o início efetivo para o mais tardio dos primeiros
pregões e avisa; `backtestComparisonProvider` calcula o início comum sobre a
união dos tickers das **duas** carteiras antes de executar qualquer uma. Dois
ativos com 60 meses de diferença de listagem saem com o mesmo `totalReturn`
quando a trajetória é a mesma.

## Decisão

A conta fica. O rótulo ganha a ressalva, com o tamanho medido.

O que sobra depois de fechado aquele canal é que, com janela e cronograma
comuns, `totalReturn` ainda difere do retorno de preço — porque o aporte mensal
interage com a trajetória. Dois ativos que partem de 100 e voltam a 100, um em
vale e outro em pico, chegam a **56,5 pontos percentuais** de distância com
retorno de preço zero para ambos. Numa carteira real de 15 ativos, Spearman de
**0,7571** entre as duas medidas e deslocamento máximo de **6 postos**.

**A medida que está no lugar é a certa para a pergunta que a tela faz.** O
cartão existe para decidir uma troca entre Principal e Reserva, e essa decisão
é sobre o dinheiro que de fato seguiu aquele cronograma. A ALOS3 rendeu +39,1%
ao investidor mensal com o preço parado em −0,0%, e isso é resultado de comprar
durante a queda — não ilusão a corrigir.

## Consequências aceitas

O número continua não descrevendo o ativo, e um leitor que o compare ao gráfico
encontra até 56,5 p.p. de diferença. O glossário da tela já dizia o certo —
*"quanto o **capital destinado** àquele ativo rendeu"* — e passa a trazer
também a razão e a magnitude.

**Fica como dívida, e não como defeito:** a tela não oferece a leitura
independente de cronograma. Quem quiser saber como o ativo andou precisa do
gráfico. Uma segunda coluna resolveria, e é acréscimo de interface — não
correção.
