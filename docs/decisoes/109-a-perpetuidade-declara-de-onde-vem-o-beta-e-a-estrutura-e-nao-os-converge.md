---
numero: 109
titulo: A perpetuidade declara de onde vêm o beta e a estrutura de capital, e não os leva a um estado estacionário imposto
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B12, B14 e B15.
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/services/valuation/levered_rates.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - tool/perpetuidade.dart
  - tool/gabarito_cascata.dart
  - docs/validacao/perpetuidade.md
substitui: []
---

## Contexto

A lente `metodo` apontou em 15/09/2026 que a taxa de equilíbrio da perpetuidade
troca **só** a taxa livre de risco: o mesmo beta, e — na via da firma — o WACC
com o peso do capital próprio e a dívida **de hoje**. Um estado estacionário com
o beta e a alavancagem do ano da avaliação é premissa não declarada, e ela pesa
onde metade do valor mora.

**Metade do apontamento caiu com a
[decisão 105](105-o-aplicativo-resolve-o-prior-do-beta-e-o-custo-de-capital.md).**
O aplicativo passou a resolver o caminho de taxas, e a alavancagem de equilíbrio
virou a que a própria projeção alcança no ano N — não mais a de hoje. Sobrou o
beta, que continua sendo o de hoje, estimado na janela de cinco anos, levado à
perpetuidade sem convergir.

O item B15 pedia declarar a origem dos dois, medir o efeito de levá-los ao
estado estacionário — beta em direção a 1 (Blume) e alavancagem da mediana do
setor — e escolher.

## O que foi medido

Sobre a entrada congelada do gabarito, em 21/09/2026, nos 102 avaliados
([perpetuidade.md](../validacao/perpetuidade.md)):

**A alavancagem do ano N é praticamente a de hoje.** Comparadas ativo a ativo
nos 80 em que as duas existem, a diferença mediana é de **−0,01**, e ela sobe em
24 deles. O modelo não produz uma alavancagem fugindo para o infinito: ele chega
a um ponto perto de onde partiu.

| `D/E` | p25 | mediana | p75 |
|---|---:|---:|---:|
| hoje | 0,00 | 0,29 | 1,25 |
| no ano N, o do modelo | 0,09 | 0,64 | 1,37 |
| mediana do setor da B3, hoje | 0,04 | 0,34 | 0,56 |

**Convergir o beta não move nada, e a razão é que ele já convergiu.** Com Blume
a `w = 0,67`, a taxa de equilíbrio muda **−0,0%** na mediana e o preço justo
**+0,1%** — p10 de −1,5% e p90 de +2,8%. O encolhimento da
[decisão 40](040-beta-encolhido-por-precisao.md) já puxa o beta em direção ao
prior transversal, e o prior relavancado fica perto de 1: o beta mediano que
chega ao preço é **0,955**, e `0,67 × 0,955 + 0,33` dá 0,97.

**Impor a mediana do setor move menos ainda, e custa avaliação.** A taxa de
equilíbrio muda 0,0% na mediana, o preço justo 0,0% — e **5 dos 102 deixam de
ser avaliados**, porque a alavancagem imposta quebra o ponto fixo.

## Decisão

1. **A origem é declarada.** O custo de capital da perpetuidade diz, no código e
   nos diagnósticos, de onde vêm as duas pontas: a estrutura de capital é a do
   **ano N do modelo** quando as taxas são resolvidas (decisão 105) e a de hoje
   quando não são; o beta é o de **hoje**, encolhido em direção ao prior
   transversal, sem convergência adicional.
   `ValuationDiagnostics.terminalEquityShare` passa a carregar a primeira.
2. **Nenhuma das duas alternativas é adotada.** Blume move 0,1% do preço justo
   porque o encolhimento já fez o trabalho; a mediana setorial move 0,0% e custa
   cinco avaliações.
3. **As duas ficam como imposição de diagnóstico**
   (`ValuationInputs.terminalBetaWeightOverride` e `terminalLeverageOverride`),
   como as demais varreduras: elas não são do aplicativo, e existem para que a
   próxima leitura não refaça a pergunta sem instrumento.

## Consequências aceitas

**A premissa continua sendo premissa, e agora está escrita.** O beta de cinco
anos vale para sempre. O que a torna aceitável não é a teoria — é a medição de
que a alternativa clássica não muda o número, porque a decisão 40 já aproxima o
beta do mercado por outro caminho, e por um que tem erro-padrão a justificá-lo.

**O argumento vale enquanto o encolhimento valer.** Se o prior transversal se
afastar de 1 — um universo em que o beta desalavancado mediano caia muito —,
Blume voltaria a ter efeito, e esta decisão precisaria ser remedida. O
instrumento fica pronto para isso.

**A alavancagem de equilíbrio é a do modelo, e o modelo não a escolhe.** Ela é o
que a projeção da dívida e do valor produz no ano N, e não um alvo declarado.
Medida, ela fica perto da de hoje; mas continua sendo consequência, e não
premissa — quem quiser um alvo precisa da imposição, e do argumento.
