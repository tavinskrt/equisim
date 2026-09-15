---
numero: 96
titulo: O t da habilidade é corrigido pela estrutura da sobreposição e comparado com o crítico que ela dá, e o Newey-West tem de passar de 2 junto
status: aceita
origem: voce
data: 2026-09-15
citacao: >
  Seus itens de escopo para esta rodada são C1d, C1c e C3. Quero medir a
  habilidade do motor quando todas as fases estiverem completas.
afeta:
  - tool/validation/regression.dart
  - tool/regressao_condicional.dart
  - tool/recusas_custo.py
  - test/tool/regression_test.dart
  - docs/validacao/habilidade_trimestral.md
  - docs/validacao/habilidade_trimestral.json
substitui: []
---

## Contexto

O item C1c do plano: coortes trimestrais. A
[decisão 93](093-as-deslistadas-entram-nas-coortes-e-o-t-e-o-menor.md) deixou,
para o critério do R3, o menor entre o `t` comum do segundo passo de Fama-MacBeth
e o de Newey-West, "até as coortes trimestrais darem série longa o bastante". Elas
chegaram, e a regra não serve a elas:

- **o `t` comum passa a ser inútil**: coortes de três em três meses medidas em 36
  meses compartilham até 33 meses de retorno, e o `t` que as supõe independentes
  sai inflado por um fator de três a quatro;
- **o Newey-West não tem distribuição conhecida com 22 coortes e 11
  defasagens**: a autocovariância estimada é ruído, e com cinco coortes anuais ela
  já tinha saído negativa e estreitado o erro.

## Decisão

1. **O `t` é corrigido pela estrutura que a sobreposição impõe, e não estimado
   da série** (`Regression.overlapAdjustedT`). Com `L = h/Δ − 1` coortes
   sobrepostas e choques independentes mês a mês, a coorte `t` e a `t+j` têm
   correlação `ρ_j = 1 − j/(L+1)`. Sob ela, o desvio amostral subestima o desvio
   verdadeiro por `c` e a variância da média cresce por `F`, os dois em conta
   fechada de `k` e `L`, e o `t` corrigido é o comum vezes `√(c/F)`.
2. **O limiar vem da mesma estrutura, por simulação**
   (`Regression.overlapCritical`): 20.000 séries de somas sobrepostas de choques
   normais, média zero, e o quantil do `t` corrigido com o mesmo nível unilateral
   de `t > 2` sob a normal, 2,275%. O gerador é o splitmix64 com semente fixa,
   escrito igual no Dart e no Python, e o crítico sai o mesmo nas duas
   ferramentas e em toda execução.
3. **O critério do R3 passa a ser: `t` corrigido acima do crítico, e Newey-West
   acima de 2.** O corrigido cobre a sobreposição e a cauda de poucas coortes; o
   Newey-West, a persistência que vá além dela — a do sinal, que muda devagar.
4. **O `t` comum continua sendo reportado**, com o `p` da simulação, para que a
   leitura antiga e a nova fiquem lado a lado.

## Consequências aceitas

**O crítico é alto quando há poucas coortes efetivas, e isso é o preço de ser
honesto com elas.** Medido: 2,70 para 22 coortes trimestrais de 36 meses; 3,24
para cinco coortes anuais de 36 meses; e, sem sobreposição, 2,52 para sete coortes
— que é o quantil da t de Student com seis graus de liberdade, 2,5165, integrado
à parte. É a conferência de que a simulação reproduz o caso conhecido.

**A regra da decisão 93 era otimista, e a leitura dela muda.** Sob a correção, a
leitura anual da rodada anterior — potencial dado o P/B em 36 meses, `t` comum de
1,24 com as deslistadas — dá `t` corrigido de 0,63 contra o crítico de 3,24. E o
IC dos soltos do corte de liquidez dado o B/M em 36 meses, que a
[decisão 95](095-a-recusa-por-liquidez-fica-pelo-nivel-e-nao-pela-ordenacao.md)
leu com `t` de 3,08, dá 1,56 contra 3,24: **a ordenação em 36 meses não estava
provada**. Em 12 meses as coortes anuais não se sobrepõem, e o `t` de 2,73 dela
passa no crítico de 2,52.

**A estrutura supõe choques independentes entre meses.** Se o retorno
transversal tiver memória própria, a correção fica curta — é por isso que o
Newey-West continua no critério. E se o sinal mudar muito de coorte para coorte,
a correção fica longa, e o critério, conservador. Um critério de aprovação pode
errar para esse lado.

**O veredito do R3 não sai nesta rodada.** O usuário pediu, em 15/09/2026, para
medir a habilidade com todas as fases completas: o C1 foi para depois da Fase 3,
e o que esta decisão fixa é o instrumento.
