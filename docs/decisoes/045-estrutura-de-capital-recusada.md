---
numero: 45
titulo: Recusa do solucionador deixa de virar preço pela interpolação, e a discordância entre as vias para de decidir
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Prossiga para D2. Mesmo esquema: me forneça a lista necessária para chegar ao
  valuation sem erros conhecidos ao final e rode as lentes.
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/services/valuation/levered_rates.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - packages/equisim_core/test/levered_rates_test.dart
  - tool/vias.dart
  - docs/validacao/vias.md
substitui: []
---

## Contexto

A [decisão 42](042-caminho-de-taxas-em-producao.md) estabeleceu o recuo: sem
`β_U`, sem convergência ou com falha do solucionador, vale a interpolação de
dois pontos. Na época o recuo cobria 5 dos 122, e a distinção entre *não
convergir* e *recusar* não parecia ter consequência.

O D2 remediu a discordância entre as duas vias depois das decisões 41 a 44 e
encontrou a consequência. Dos 96 ativos com as duas vias avaliáveis, 90 recebem
o caminho resolvido. **Os seis restantes são exatamente os seis que ainda eram
mesclados e migrados** — e nos seis o solucionador não falhou: recusou.

- AGRO3, MYPK3, PRIO3: capital próprio não positivo **no ano zero**;
- KLBN3, KLBN4, KLBN11: WACC de equilíbrio abaixo do crescimento perpétuo.

Em todos a recusa vem na segunda ou terceira iteração — depois de a
realavancagem corrigir a taxa. A primeira iteração parte da interpolação: passar
por ela e morrer na seguinte é a definição de "a interpolação não enxergava o
problema".

## Decisão

**A recusa do solucionador não é falha de método, e não se recua dela.**
`LeveredCostOfCapital.solve` passa a ter dois desfechos com significados
diferentes:

| | o que significa | o que a cascata faz |
|---|---|---|
| não convergir em 100 iterações | o método não fechou | recuo para a interpolação |
| `ComputationFailure` | a estrutura não fecha | a via da firma não vale |

**Recusada a estrutura, a via da firma não produz número.** A avaliação migra
inteira para o fluxo do acionista, com o motivo nomeado, e **não há mescla** — a
mescla da [decisão 38](038-transicao-continua-entre-as-vias.md) combina dois
estimadores, e aqui só existe um.

**Sem a via do acionista, a recusa é do ativo**, e sai nomeada como a
[decisão 25](025-reconstrucao-do-motor-de-avaliacao.md) exige.

**A recusa passa a dizer quando aconteceu** — ano e iteração. Sem isso não há
como separar "a estrutura não fecha" de "o ponto fixo passeou por um iterado
inviável", e as duas pedem tratamentos opostos.

## Consequências aceitas

**A discordância entre as vias deixa de decidir.** Nos 90 ativos em que as duas
são calculáveis, **nenhum resultado mescla e nenhum migra**. A discordância
continua — mediana de 1,21×, 50 dos 90 além de 1,5× — e vira fato registrado
em vez de escolha.

**Seis preços justos mudam**: PRIO3 +463,0%, AGRO3 +68,0%, KLBN11 +23,4%,
KLBN4 +22,9%, MYPK3 +19,9%, KLBN3 +19,8%. O potencial mediano não se move
(−36,1%), o p25 melhora de −69,3% para −66,5%.

**Dois ativos deixam de ser avaliados**: AMER3 e BHIA3, com a mesma recusa
nomeada. A **BHIA3 aparecia com +230,4% de potencial** — o motor anunciava
tripla enquanto a própria conta dizia que, reprecificado o custo do capital
próprio pela alavancagem que ele tem, não sobra capital próprio. Perder um
potencial positivo assim é ganho.

**A via da firma passou a ser a mais próxima do mercado**: 47 de 90 contra 43,
com erro mediano de 52,6% contra 53,8% — vindo de 39 de 92 e 59,1% na versão
anterior. Não é prova de acerto, e sim sinal de que a via que mudou foi a que
melhorou.

**A recusa é mais forte do que a evidência exige em um ponto.** Capital próprio
não positivo no ano zero é conclusão sobre a estrutura *dada a projeção de
dívida crescendo a `g`*, que é premissa da rota (b) da
[decisão 41](041-custo-de-capital-realavancado-ano-a-ano.md), não fato
observado. A saída (a) — amarrar a dívida ao valor — daria outra resposta para
os mesmos seis. A escolha entre elas continua sendo a da decisão 41, e não é
reaberta aqui.

**A cobertura cai de propósito.** O motor passa a avaliar menos ativos, e o que
sai é o que ele não sabe avaliar. Cobertura não é critério.

**A alternativa descartada** era manter o recuo e apenas marcar o resultado com
uma ressalva. Recusada porque a mescla já entrega o número ao usuário: uma
ressalva ao lado de um preço que a própria conta rejeita não impede que o preço
seja usado, e o projeto já decidiu que recusa nomeada é preferível a número
frágil.
