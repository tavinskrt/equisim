---
numero: 158
titulo: A evolução comparada do Backtest passa ao gráfico de linha da Bklit UI, e o risco × retorno fica no Recharts
status: aceita
origem: voce
data: 2026-10-29
citacao: >
  Podemos agora migrar a tela de backtest para a Bklit.
afeta:
  - src/features/backtest/evolution-chart.tsx
  - src/ui/charts/bklit/
  - test/ui/evolution-chart.test.tsx
  - docs/motor/07-aplicativo.md
substitui: []
---

## Contexto

A decisão 156 fez da curva de acumulação da Meta o piloto da Bklit UI, e
deixou os outros gráficos no Recharts até a comparação. Com o piloto aceito,
veio o pedido de migrar a tela de Backtest. Ela tem dois gráficos em Recharts:

- a **evolução comparada**, uma linha por carteira sobre datas de pregão;
- o **risco × retorno**, uma dispersão de volatilidade contra retorno.

O resto da tela (ponte do patrimônio, mapa de correlação, desempenho por
ativo) é HTML e CSS do próprio Equisim, sem biblioteca de gráfico.

## Decisão

**A evolução comparada passa ao `LineChart` da Bklit; o risco × retorno fica
no Recharts.**

1. **Os dados passam por um ajuste antes de chegar ao gráfico.** A Bklit lê
   todas as curvas de uma tabela só, e um valor ausente vira o topo do
   gráfico. A função `plotPoints`, em `evolution-chart.tsx`, prepara os
   pontos assim:
   - o pregão que falta no meio de uma curva é interpolado no tempo, o mesmo
     segmento reto que o `connectNulls` do Recharts desenhava;
   - nas pontas, o gráfico fica no período em que as duas carteiras têm
     cotação, e o rodapé avisa quando isso corta alguma.

   O valor interpolado só posiciona a linha. O tooltip mostra o ausente como
   "—", e a tabela e o CSV não passam por esse ajuste.
2. **Segmento reto entre pregões** (`curveLinear`). A curva natural, padrão da
   Bklit, passaria entre um dia e outro por valores que a carteira nunca teve.
   Sai também o esmaecer das pontas, outro padrão dela: o último pregão é o
   resultado da simulação e não pode sumir no fundo.
3. **A escala do eixo depende da grandeza.** Na base 100, o eixo se ajusta à
   faixa dos dados, com a linha de 100 tracejada, porque é a diferença entre
   as carteiras que se lê ali. No patrimônio em reais, o eixo parte do zero.
   Para isso o `LineChart` copiado ganhou a opção `yDomainFit`, a quarta
   mudança registrada no `README.md` da pasta.
4. **Trocar de grandeza remonta o gráfico.** A curva entra de novo, em vez de
   se transformar de índice em reais, que não são a mesma conta.
5. **O risco × retorno fica no Recharts.** A dispersão da Bklit
   (`ScatterChart`) só aceita datas no eixo x, só desenha círculos e não
   escreve rótulo no ponto. Ela perderia as formas e os tickers que
   identificam cada ponto sem depender de cor.

## Consequências aceitas

- **O Recharts continua no projeto**, no risco × retorno e na rosca de
  setores do Estudo. A Bklit fica em dois gráficos, a curva de acumulação e a
  evolução, e o pedaço dela é compartilhado pela Meta e pelo Backtest.
- **Período comum nas pontas.** Se uma carteira começa ou termina em data
  diferente da outra, o gráfico mostra só o período comum. A série completa de
  cada uma segue na tabela e no CSV.
- **Nenhum número muda.** `src/core` não é tocado, e a tabela de fim de mês é
  a mesma de antes.
