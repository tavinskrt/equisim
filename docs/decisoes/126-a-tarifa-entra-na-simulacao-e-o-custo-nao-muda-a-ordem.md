---
numero: 126
titulo: A tarifa da B3 entra na simulação, o spread entra nas coortes, e o custo muda o nível e não a ordem
status: aceita
origem: voce
data: 2026-09-22
citacao: >
  Seus itens de escopo para esta rodada são B8, B21 (pode finalizar a
  reescrita das outras duas metades), C4 e D3.
afeta:
  - packages/equisim_core/lib/src/services/backtest/portfolio_backtest.dart
  - lib/presentation/backtest/backtest_page.dart
  - lib/presentation/export/csv_export.dart
  - tool/custos_spread.py
  - tool/custos_simulacao.dart
  - tool/regressao_condicional.dart
  - tool/b3_baixar.py
  - docs/validacao/custos_transacao.md
  - docs/validacao/limitacoes.md
substitui: []
---

## Contexto

O item C4 pedia que o custo de transação entrasse no backtest e que o efeito
sobre o retorno medido fosse reportado. As [limitações](../validacao/limitacoes.md)
§2.5 diziam que o motor não modelava corretagem, emolumentos nem spread, e que
a distorção era baixa por não rebalancear — **mas não medida**.

«O backtest» do projeto são dois, e o custo pesa diferente em cada um: a
**simulação da carteira**, que o aplicativo mostra, compra em cada aporte e
nunca vende; as **coortes de validação**, que respondem ao R3, compram na data
e vendem no horizonte.

## O que foi medido

[custos_transacao.md](../validacao/custos_transacao.md), com três ferramentas.

**O spread** foi estimado papel a papel da máxima, da mínima e do fechamento
diários do COTAHIST, que passaram a ser baixados à parte
(`b3_baixar.py --extremos`). O estimador de **Abdi e Ranaldo (2017)** ordena
como deve — 1,72%, 0,87% e 0,42% do tercil menos ao mais líquido —; o de
**Corwin e Schultz (2012)**, mais citado, saiu **invertido** nesta amostra, e
foi descartado com a medição registrada.

**Nas coortes**, com tarifa e meio spread nas duas pontas: o retorno mediano de
36 meses cai de 14,00% para **13,14%**, e **o critério da decisão 96 dá o mesmo
resultado nas cinco ordenações** — nenhuma passa, bruta ou líquida. Os IC se
movem na terceira casa.

**Na simulação**, em cinquenta carteiras sorteadas do universo congelado: a
tarifa da B3 tira **0,024%** do patrimônio final e 0,006 p.p. do XIRR.

## Decisão

1. **A simulação cobra a tarifa da B3 por padrão** — 0,030% por compra, em
   centavos inteiros, arredondada meio para cima, saindo do caixa do ativo
   antes da compra. `TransactionCosts` aceita corretagem fixa por ordem, que é
   zero por padrão. A identidade passa a ser **aportado = alocado + custos +
   caixa**, ao centavo, e a tela mostra a linha «Custos».
2. **O spread não entra na simulação, e é declarado.** Ela compra ao
   fechamento, e o spread pago depende de como a ordem é mandada; um número
   único para todas as carteiras seria falsa precisão. A sensibilidade de 0,5%
   por compra — 0,53% do patrimônio, 0,12 p.p. de XIRR — fica registrada.
3. **As coortes medem os dois**, e `regressao_condicional.dart --custos`
   remede a habilidade sobre o retorno líquido. **A leitura do R3 não muda.**
4. **A limitação §2.5 foi reescrita** com os números, em vez de «não medido».

## Consequências aceitas

**O custo não muda a ordem, e isso é quase aritmética.** Custo uniforme preserva
a ordem dos retornos de uma coorte, e o IC é correlação de ordens. O que a
medição acrescenta é que a **variação** do custo com a liquidez — de 0,4% a 1,7%
de spread — também é pequena demais diante da dispersão dos retornos para
reordenar a amostra. Quem ler esta decisão como «o motor sobrevive ao custo»
leu errado: o motor não passava antes, e continua não passando.

**O estimador é conservador para o papel líquido** — a PETR4 sai com 0,72% de
spread, contra centésimos cotados. Um custo menor só reforçaria a conclusão.

**Os testes que conferem contabilidade da simulação passaram a declarar
`TransactionCosts.none`**, e o custo ganhou grupo próprio. A alternativa — mudar
os números conferidos para os com tarifa — misturaria duas perguntas no mesmo
teste. As fixtures das telas também declaram o cenário sem custo, e a tela com
custo tem teste próprio: com a tarifa, R$ 1.000,00 a R$ 10,00 compram 99 ações,
e não 100.
