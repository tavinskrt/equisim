---
numero: 114
titulo: O motor é nominal em todo o caminho, e as três não neutralidades de unidade ficam medidas
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B6, B7, B3, B4 e B5.
afeta:
  - packages/equisim_core/test/real_nominal_test.dart
  - packages/equisim_core/lib/src/services/valuation/dcf.dart
  - docs/validacao/real_nominal.md
substitui: []
---

## Contexto

O item B7 dizia: «o motor desconta fluxo nominal a taxa nominal e usa o IPCA só
no teto da perpetuidade; nunca foi conferido que as duas pontas usam a mesma
convenção de inflação em todo o caminho».

**Conferir lendo o código não é prova.** É a mesma inspeção que deixou passar
tudo o que as rodadas anteriores acharam. O que prova é a invariância: valor
presente é quantia de hoje, e reexpressar a conta inteira em moeda constante —
cada premissa deflacionada por Fisher — não pode movê-lo.

## O que foi medido

Em forma fechada, e fixado em
[real_nominal_test.dart](../../packages/equisim_core/test/real_nominal_test.dart)
([real_nominal.md](../validacao/real_nominal.md)).

**A invariância vale, ao último dígito, em todo o caminho de desconto**: fluxos
explícitos com caixa no fim do ano, decaimento linear do crescimento e estrutura
a termo da taxa. O decaimento linear sobreviver a Fisher **não era óbvio** — a
interpolação é linear e Fisher não é —, e fecha porque interpolar entre dois
fatores brutos é o mesmo que interpolar entre os deflacionados.

**Ela não vale em três lugares, e os três são o mesmo fato:** operação sobre
taxa **líquida** não é neutra à unidade; sobre fator **bruto**, é.

| | fator | a π = 4,5% |
|---|---|---:|
| caixa no meio do ano | `(1+π)^−1/2` | 0,9782 |
| terminal neutro | `r∞ ÷ (r∞ − π)` | **1,305** na mediana dos 97 |
| freio de reinvestimento | `g ÷ ROIC` em cada unidade | — |

## Decisão

**A formulação nominal é a correta, e fica. As três não neutralidades passam a
ser declaradas, com o tamanho medido.**

1. **`g = b·ROIC` é identidade nominal, e é a raiz das três.** Reter `b` do lucro
   e aplicá-lo a um `ROIC` nominal faz o lucro **nominal** crescer `b·ROIC`. Em
   moeda constante a mesma fórmula dá outro `b` — e `b` é fração do lucro,
   grandeza sem unidade, que não pode depender de em que moeda a conta foi
   escrita. **A tradução ingênua para termos reais é que está errada**, e não o
   motor.
2. **O terminal fica onde está.** `VT = lucro_{N+1} ÷ r` é a leitura nominal, e
   é a **menor** das duas: a real daria `r ÷ (r − π)` vezes mais, um terço a
   mais na mediana. Escolher a maior exigiria afirmar que o capital novo rende o
   custo de capital **em termos reais**, o que é premissa diferente e mais
   generosa.
3. **A convenção de meio de ano fica, e é a única que anda contra a
   prudência** — 2,2% acima da leitura em moeda constante. Fica por ser a
   convenção padrão de fluxo distribuído no ano, e o tamanho está declarado.
4. **O teto da perpetuidade continua nominal, e por composição.**
   `(1+real)(1+π) − 1`, nunca a soma, e na mesma unidade do desconto — um teto
   real contra desconto nominal faria o spread `r − g∞` ser nominal menos real.
5. **A prova vira teste, e o teste traz a guarda.** Trocar Fisher por subtração
   move o preço justo em mais de 5%, e o teste reprova nos dois sentidos: se a
   invariância quebrar onde vale, e se alguém tornar neutro o que a decisão
   declara não neutro.

**O cálculo não muda.** O que muda é que a convenção deixa de ser suposição de
leitura e passa a ser propriedade provada, com três exceções nomeadas e
medidas.

## Consequências aceitas

**O fator do terminal é instável com juro baixo.** `r ÷ (r − π)` explode quando
`r` se aproxima de `π`. No universo de hoje o `r∞` mínimo é de 13,5% e o fator
máximo é 1,50; num mercado de juro real baixo a mesma leitura seria frágil. É
ressalva do número, e não do método.

**O motor em termos reais não existe, e não foi construído.** O que está medido
é o tamanho da diferença entre as duas leituras, e não qual descreve melhor o
ativo. Construí-lo exigiria reescrever `g = b·ROIC` na forma correta em moeda
constante, que é trabalho de método e não de tradução.

**A inflação é o IPCA anualizado de dez anos, 4,5%**, a mesma âncora do teto da
perpetuidade. Outra inflação move os três fatores, e a forma fechada permite
recalculá-los sem reexecutar nada.
