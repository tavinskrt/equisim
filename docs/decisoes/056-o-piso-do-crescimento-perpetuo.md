---
numero: 56
titulo: O crescimento perpétuo passa a ter o piso da banda de sanidade, e não zero
status: aceita
origem: voce
data: 2026-09-11
citacao: >
  Prossiga com o item 1 do bloco A. Mesmo esquema: ao final, reestruture a
  lista necessária para chegar no valuation sem erros conhecidos e motor de
  referência. Ao final, rode as lentes.
afeta:
  - packages/equisim_core/lib/src/services/valuation/growth_estimator.dart
  - packages/equisim_core/test/usecases_test.dart
  - docs/validacao/fluxo_explicito.md
substitui: []
---

## Contexto

`GrowthEstimator` declara uma banda de sanidade para o crescimento estimado, e
o piso dela tem razão escrita: *"uma empresa em perpetuidade não encolhe
indefinidamente"*, `floorRate = -0.05`.

E `perpetual` aplicava **por cima dela** um segundo piso, em zero — que tornava
o primeiro inalcançável. O projeto declarava um limite e usava outro.

O piso em zero afirma que **toda empresa em declínio volta a crescer zero em
dez anos**: o caminho explícito decai linearmente de `g₁` até `g_∞`, e com
`g₁ = −4,56%` e `g_∞ = 0` ele **sobe**.

## Decisão

**O piso do crescimento perpétuo é `GrowthEstimator.floorRate`**, o mesmo da
banda de sanidade, e o teto continua sendo o crescimento nominal da economia.
Uma regra, e não uma regra com exceção.

**Onde a economia encolhe mais que o piso, o teto vence.** `clamp` lança quando
o piso supera o teto, e é caminho alcançável por quem monta premissas à mão. A
precedência é do teto: "ninguém cresce acima da economia para sempre" é a regra
mais forte das duas.

## Consequências aceitas

**Três preços justos caem**: PCAR3 −23,4%, BRAP4 −4,7%, B3SA3 −2,3%. São os
únicos do universo com crescimento fundamental negativo.

A PRNR3 aparece na varredura com −2,4% e **não é efeito econômico**: o preço
justo vai de R$ 0,42 para R$ 0,41, um passo de um centavo sobre um papel de
centavos, vindo de diferença de convergência do ponto fixo na oitava casa
decimal.

**A distribuição não se move**: potencial mediano em −41,0%, 34 positivos, p75
em +4,5%.

**O declínio perpétuo agora é possível, e limitado a −5% ao ano.** É premissa
forte, e é a que a banda de sanidade já declarava — o que muda é que ela passou
a valer onde estava escrito que valeria.

**O terminal neutro limita o alcance disto.** Com `ROIC_∞ = WACC` o crescimento
perpétuo não cria valor, e `g_∞` entra na perpetuidade só por
`fluxo_{N+1} = fluxo_N·(1 + g_∞)`. O peso real dele é ser o alvo do decaimento
do período explícito — e era ali que dez anos de recuperação presumida
entravam.

**Um piso em zero passou a ser alcançável, e fica declarado.** O reinvestimento
terminal do ramo com vantagem competitiva é `(g_∞ / ROIC_∞)` confinado em
`[0; 0,95]`, e o mesmo confinamento existe em `retentionAt`. Com `g_∞` negativo
a razão fica negativa e o piso morde: **a empresa que encolhe libera capital, e
o motor não lhe credita isso**. É a direção conservadora — creditar exigiria
afirmar que o capital liberado chega ao acionista —, e antes desta decisão o
caminho não era alcançável, porque `g_∞` nunca era negativo. A lente `metodo`
apontou no mesmo dia, e a resposta é esta: declarado, não corrigido.

**A alternativa descartada** era manter o piso em zero e declará-lo como
premissa. Recusada porque o projeto **já tinha** a premissa declarada em outro
número: manter os dois seria manter a contradição por escrito.
