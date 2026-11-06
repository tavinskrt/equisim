---
numero: 161
titulo: O Backtest compra uma ação de cada ativo, pelo fracionário, no primeiro pregão da janela, e mais nada
status: aceita
origem: voce
data: 2026-11-06
citacao: >
  Vamos fazer uma modificação no backtest. Para compararmos realmente a
  rentabilidade da carteira, vamos fazer que a compra dos ativos seja apenas
  de um ativo pelo mercado fracionário apenas no período do início da janela.
  Não esqueça de, quando fazer essa alteração, remover o código morto da tela
  de backtest
afeta:
  - src/core/services/backtest/portfolio-backtest.ts
  - src/app/backtest.ts
  - src/app/csv-export.ts
  - src/copy/fmt.ts
  - src/features/backtest/
  - test/core/backtest.test.ts
  - test/app/backtest.test.ts
  - test/app/fixtures.ts
  - test/ui/screens.test.tsx
  - test/ui/evolution-chart.test.tsx
  - docs/motor/07-aplicativo.md
  - README.md
substitui:
  - 9
---

## Contexto

A tela de Backtest simulava as duas carteiras com o plano da aba Meta: o aporte
inicial e os mensais, divididos pelos pesos, comprando ações inteiras, com a
sobra em caixa por ativo (`PortfolioBacktest.run`, decisão 9). A comparação de
rentabilidade passava por esse cronograma: o patrimônio, o XIRR, o caixa
residual e o retorno por ativo dependiam das datas e dos valores dos aportes, e
o glossário precisava explicar por que o retorno de um ativo na carteira
diferia do gráfico do próprio ativo — 56,5 pontos percentuais no caso extremo.

O pedido é comparar a rentabilidade da carteira sem esse ruído.

## Decisão

**O Backtest compra uma ação de cada ativo, no primeiro pregão da janela, e não
compra mais nada.**

1. **A compra.** Quantidade 1 de cada ativo da carteira — a do mercado
   fracionário da B3, que negocia de 1 a 99 ações —, ao fechamento do primeiro
   pregão da janela comum às duas carteiras, com a tarifa da B3 por ordem
   (`TransactionCosts.b3`, decisão 126). O investido é exatamente o que as ações
   e a tarifa custaram, e não sobra caixa. Forma nova no núcleo,
   `PortfolioBacktest.runOneShareEach`.
2. **Sem aporte depois.** O plano da Meta não entra no Backtest; a tela não
   exige mais meta para simular.
3. **A medida da comparação é o TWR**, como já era. Sem fluxo depois da compra,
   o TWR é o retorno da cesta comprada, e não depende de quanto cada cesta
   custou.
4. **O código morto sai da tela.**
   - O XIRR, das métricas e do CSV: com um fluxo só, na entrada, ele coincide
     com o retorno ponderado pelo tempo. "O realizado frente à meta" passa a
     usar o CAGR.
   - O Alocado e o Em caixa, das métricas, da ponte e do CSV: sem sobra, são o
     investido menos os custos e zero.
   - A vista em base 100 da evolução comparada: sem aporte, ela é o
     patrimônio em reais dividido por uma constante, e duas vistas da mesma
     curva confundiam o usuário. A evolução fica só em reais, como pedido em
     06/11/2026 ("queria ver literalmente em reais [...] pode remover a opção
     de ver na base 100"). O percentual segue no TWR das métricas, e a série em
     base 100, no CSV.
   - O peso alvo, o peso atual, a deriva e a barra de peso do desempenho por
     ativo, e os verbetes do glossário que explicavam aportes e deriva.
   - O dia do aporte das preferências do Backtest, `PortfolioComparison.hasBoth`
     e `isPortfolioPoint`, que nenhum código chamava.

`PortfolioBacktest.run` e `ContributionPlan` **ficam no núcleo**, sem mudança de
número: as ferramentas de validação (`tool/validation/invariants.ts`,
`tool/return-by-asset.ts`, `tool/simulation-costs.ts`) e o gabarito de paridade
com o núcleo Dart usam o plano de aportes. As duas formas dividem o calendário,
a marcação a mercado e a consolidação das métricas.

## Consequências aceitas

- **A carteira passa a ser ponderada pelo preço.** Com uma ação de cada, cada
  ativo pesa o próprio preço sobre a soma dos preços, como num índice ponderado
  por preço (o Dow Jones Industrial Average é o exemplo clássico), e não a
  fatia igual do Estudo. Uma ação de R$ 100 pesa dez vezes uma de R$ 10, e a
  rentabilidade da cesta segue mais a ação cara. A alternativa, comprar a
  mesma quantia de cada ativo, foi descartada por não ser o que o pedido disse.
- **Principal e Reserva investem valores diferentes**, porque têm ativos e
  preços diferentes. O patrimônio final das duas não se compara; o TWR, o CAGR
  e as métricas de risco, sim.
- **O preço é o do lote padrão.** A fonte de cotações publica o fechamento do
  código sem o sufixo F; o fechamento do fracionário pode diferir alguns
  centavos dele. A diferença fica declarada, e não corrigida.
- **A decisão 9 fica derrubada só no Backtest.** O "V0 + PMT" dela continua
  valendo na Meta e no acompanhamento da carteira (decisão 159); o "sem
  rebalanceamento" continua valendo aqui também.
- **Números do Backtest mudam.** Estudos salvos, capturas e textos que citam
  patrimônio ou XIRR do Backtest antigo deixam de bater com a tela. Os números
  congelados do artigo e da validação não vêm desta tela e não mudam.
