---
numero: 46
titulo: A via do acionista resolve o próprio custo de capital contra a alavancagem, e a instituição financeira fica de fora por direito
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Prossiga para D2b. Mesmo esquema: ao final, reestruture a lista necessária
  para chegar ao valuation sem erros conhecidos ao final e rode as lentes.
afeta:
  - packages/equisim_core/lib/src/services/valuation/levered_rates.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/test/levered_rates_test.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - tool/via_acionista.dart
  - docs/validacao/via_acionista.md
substitui: []
---

## Contexto

A [decisão 45](045-estrutura-de-capital-recusada.md) tirou da via do acionista o
papel de segundo estimador: nos 90 ativos com as duas vias calculáveis, nenhum
resultado mescla e nenhum migra. Ela continuou avaliando sozinha **33 dos 120**
— 15 por instituição financeira, 3 por lucro operacional não sustentado e 15
pela estrutura de capital recusada pela própria decisão 45.

E nesses 33 o motor descontava ao `Ke` do CAPM com o beta alavancado de hoje,
**supondo essa alavancagem perene**. É a hipótese que a
[decisão 41](041-custo-de-capital-realavancado-ano-a-ano.md) mediu e descartou
para a via da firma. O motor tinha dois custos de capital próprio para o mesmo
ativo: nos 90 em que os dois existem, eles diferiam por mais de 1 p.p. em 38.

**Emprestar o caminho da via da firma não era possível.** Nos 18 ativos em que a
via do acionista decide sozinha fora da Porta 1, a via da firma produz caminho
de taxas em **zero** — porque as portas que mandam o ativo para lá são
exatamente as que tornam a via da firma indisponível.

## Decisão

**`LeveredCostOfCapital.solveEquity` resolve o `Ke` pelo lado do capital
próprio**, sem passar pelo valor da firma:

```
E_t   = (LPA_t + E_{t+1}) / (1 + Ke_t)
β_L,t = β_U · (1 + (1 − τ)·D_{t−1}/E_{t−1})
Ke_t  = Rf_t + β_L,t · prêmio
```

O capital próprio vem por acumulação regressiva do fluxo do acionista, e a
dívida segue a base de capital — a mesma premissa da via da firma, porque trocá-
la aqui faria as duas divergirem por construção. Tudo na escala **por papel**:
`D/E` é razão, e resolver assim mantém a contagem de ações fora do ponto fixo.

**A instituição financeira fica de fora, e é de direito.** Depósito e captação
são insumo do negócio, não financiamento: realavancar por `D/E` trataria a
matéria-prima como estrutura de capital, que é o que a Porta 1 existe para não
fazer. Para banco vale o `Ke` do CAPM sobre o beta observado.

**A recusa do solucionador vale nas duas vias.** A decisão 45 separou recusa de
não convergência na via da firma; a mesma separação passa a valer aqui, com uma
diferença: na via do acionista não há para onde migrar, e a recusa é do ativo.

**O diagnóstico carrega o `Ke` de equilíbrio resolvido**
(`ValuationDiagnostics.terminalCostOfEquity`), que é o que permite comparar de
fora os dois custos de capital que o motor produz para o mesmo ativo.

## Consequências aceitas

**Cobertura de 103 dos 120**, e de **18 dos 18** não financeiros que a via do
acionista avalia em produção. A exceção cobre exatamente o que foi declarado.

**Os dois custos de capital convergiram.** A diferença entre o `Ke` resolvido
pela firma e o da via do acionista caiu de 38 para **18 em 90** acima de 1 p.p.,
e a mediana foi de −0,52 p.p. para **0,00 p.p.**

**Quinze preços justos mudam**, nos dois sentidos: PRNR3 −28,6%, AXIA3 −14,3%,
UGPA3 −10,8%, SMFT3 −10,7%, as três KLBN em torno de −10%; MILS3 +15,4%,
MBRF3 +13,1%, MYPK3 +7,1%, PRIO3 +4,7%. O potencial mediano não se move
(−36,1%), o p25 piora de −66,5% para −69,0% e os positivos ficam em 30.
**Nenhum ativo deixa de ser avaliado.**

**Para banco, a alavancagem perene passa a ser premissa declarada.** Ela era
premissa antes também, e silenciosa; o que muda é que agora está nomeada e vale
só onde foi escolhida.

**Três bancos escapam da exceção por falta de setor na fonte** — BRSR6, PINE4 e
SANB4 chegam sem `sectorKey`, a Porta 1 não os pega e a Porta 3 os captura.
Passam a ser realavancados como se o depósito fosse financiamento. **O efeito
medido é de terceira casa decimal** — −0,27%, −0,15% e −0,10% — porque o
confinamento de `D/E` em 3,0 satura muito antes da alavancagem de um banco, e o
`Ke` resolvido reencontra o do CAPM. Fica declarado em `limitacoes.md`, e
corrigi-lo é trabalho de dado.

**A discordância entre as vias continua**, e o D2b não a fecha: crescimento e
normalização seguem medidos sobre séries de capital diferentes, e é isso que
[vias.md](../validacao/vias.md) mede em 50 de 90 além de 1,5×. O que esta
decisão remove é a parte da discordância que vinha do custo de capital.

**A alternativa descartada** era emprestar à via do acionista o caminho de taxas
que o ponto fixo da via da firma devolve. Recusada por medição, não por gosto:
nos 18 ativos em que ela decide sozinha fora da Porta 1, esse caminho não existe
em nenhum.
