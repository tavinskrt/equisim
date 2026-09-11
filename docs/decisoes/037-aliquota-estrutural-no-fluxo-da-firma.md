---
numero: 37
titulo: O fluxo da firma passa a ser tributado pela alíquota estrutural do ativo, e não pela estatutária que a fonte embute
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Antes de irmos para o passo 3, audite esse nível de fluxo explícito e
  descubra o porquê desse multiplicador. Se houver solução, aplique-a
afeta:
  - packages/equisim_core/lib/src/entities/fundamentals.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/lib/src/services/valuation/capital_base.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - tool/fluxo_explicito.dart
  - docs/validacao/fluxo_explicito.md
substitui: []
---

## Contexto

O [DCF reverso](035-dcf-reverso-e-regressao-condicional.md) deixou um resíduo
nomeado e não isolado: depois de o terminal e a taxa de desconto saírem como
explicação do viés de nível, sobrava um multiplicador mediano de **1,74×** entre
o fluxo que o motor desconta e o que o preço capitaliza. O suspeito registrado
era o freio de reinvestimento, e era hipótese.

A auditoria está em [`fluxo_explicito.md`](../validacao/fluxo_explicito.md), e
decompôs o resíduo em quatro contrafactuais, todos medidos por um laço que
**reproduz a produção com erro zero** em 122 de 122 ativos.

Dos quatro, três não são defeito:

- **O freio de reinvestimento** custa 47,8% do lucro operacional no primeiro ano
  e põe 20 dos 122 no teto de 95%, mas `b = g/ROIC` é a identidade que diz
  quanto capital novo um crescimento exige. Desligá-lo reintroduz o que a
  [decisão 25](025-reconstrucao-do-motor-de-avaliacao.md) corrigiu.
- **Cobrar só o crescimento real** é defensável e é mudança de método; adotá-la
  porque fecha 22,4% do vão seria ajustar o motor ao mercado, o que a decisão 35
  veda.
- **A convergência do ROIC** ajuda o valor; desligá-la o piora.

O quarto é defeito: **a alíquota**. A fonte publica `NOPAT = EBIT × 0,66` — a
estatutária brasileira aplicada a toda empresa, em 4.572 de 4.572 exercícios do
cache. A alíquota efetiva mediana medida é de **22,1%**, e **112 dos 122** pagam
menos que a estatutária. JCP, incentivo regional, lucro presumido e prejuízo
fiscal compensado não são exceção no Brasil.

E é **regime, não evento**: a dispersão robusta da alíquota dentro da mesma
empresa é de **7,5 p.p.** sobre uma mediana de **15 exercícios**, com 82 de 120
estáveis abaixo de 10 p.p.

## Decisão

**O fluxo da firma passa a ser tributado pela alíquota estrutural do ativo** —
a mediana dos exercícios publicados, confinada em `[0, estatutária]` e exigindo
ao menos cinco exercícios medíveis. Sem isso, vale o `NOPAT` publicado pela
fonte.

**Mediana e não último exercício**, porque é ela que separa incentivo estrutural
de evento. **Confinada no teto** porque pagar mais que a marginal em
perpetuidade é transitório e a fonte já aplicou a estatutária.

**A alíquota entra na série de capital e no fluxo-base ao mesmo tempo.** Mudar
só o fluxo deixaria o ROIC na convenção antiga, e o freio `b = g/ROIC` passaria
a cobrar reinvestimento de um retorno que não é o do fluxo descontado — o mesmo
defeito que a [decisão 31](031-escala-do-preco-tributo-e-invariancia-das-guardas.md)
mediu em 17% na AZZA3.

**O escudo fiscal do WACC continua na estatutária**, e deve continuar: a
dedutibilidade do juro vale na margem, e a margem é a alíquota cheia. As duas
alíquotas medem coisas diferentes e só coincidiam por acidente da fonte.

**A via do acionista não é tocada**, porque parte do lucro líquido, que já vem
tributado.

## Consequências aceitas

**O efeito compõe, e é grande.** NOPAT maior sobre a mesma base é ROIC maior,
ROIC maior é retenção menor, e retenção menor é fluxo maior de novo. Medido:
**80 dos 122** preços justos mudam além de 0,5%, com variação mediana de
**+16,2%**. O potencial mediano vai de −45,7% para **−42,3%**, o p75 de −19,6%
para **−0,9%**, e os potenciais positivos de 15 para **28**.

**O vão não fecha.** Restam 1,53× de multiplicador mediano. O freio explica boa
parte e é método; o que sobra depois dele não tem candidato nomeado.

**Nove ativos caem, alguns brutalmente, e a causa não é esta decisão.** VBBR3 vai
de R$ 33,71 para R$ 2,65 e PRIO3 de R$ 53,88 para R$ 7,46. Todos os nove são
**troca de via**: o NOPAT maior eleva o valor da firma, a participação do capital
próprio cruza os 20% da pós-condição da
[decisão 34](034-fronteira-das-vias-medida-na-taxa-estrutural.md), a migração
deixa de disparar e o ativo fica na via da firma, que para ele devolve muito
menos. Antes, eles estavam na via do acionista porque o valor da firma estava
deprimido por uma alíquota que não era a deles.

**Isso expõe um segundo defeito, que esta decisão não corrige.** A discordância
entre as duas vias chega a **12,7×** na VBBR3, e **treze ativos** estão a menos
de 10 p.p. acima do corte de 20%. É a mesma família do degrau que a
[decisão 36](036-decaimento-medido-do-excedente-na-perpetuidade.md) removeu e da
travessia que a decisão 34 removeu — um limiar decidindo entre dois estimadores
que discordam por múltiplos. A própria decisão 34 registrou a conciliação das
vias como assunto de outra decisão, e continua sendo: bundlá-la aqui esconderia
qual das duas mudanças produziu qual efeito.

**Números publicados mudam de novo.** Todo preço justo da via da firma se move.

**A alíquota efetiva usa `|despesa| ÷ lucro antes`**, e o valor absoluto
transforma crédito tributário em alíquota positiva. É conservador — eleva a
alíquota e reduz o NOPAT — e é anterior a esta decisão; fica registrado como
limitação, não corrigido aqui.

**A alternativa descartada** era convergir a alíquota da efetiva para a
estatutária ao longo da projeção, como o desconto e o ROIC já convergem, sob o
argumento de que incentivos expiram. Recusada pela medição: com dispersão de
7,5 p.p. sobre quinze exercícios, a alíquota brasileira se comporta como regime
e não como benefício temporário, e convergir imporia uma expiração que o dado
não mostra.
