---
numero: 72
titulo: A ingestão lê o período e o tipo do documento, e o LPA da CVM não entra
status: aceita
origem: parecer
data: 2026-09-14
afeta:
  - tool/cvm_ingerir.dart
  - tool/cvm_ligar.dart
  - packages/equisim_core/lib/src/services/cvm/fundamentals_merge.dart
  - docs/validacao/cvm_trimestral.md
substitui: []
---

## Contexto

Ao preparar o item A1.8, a conferência da estrutura do ITR revelou três
defeitos nas rodadas anteriores. Nenhum deles aparecia nos totais publicados;
todos apareceram ao olhar o documento linha a linha.

**1. A DRE do ITR traz duas linhas por conta.** No 2º e no 3º trimestre, cada
conta vem com o trimestre isolado (`DT_INI_EXERC` no início do trimestre) **e**
com o acumulado do exercício (`DT_INI_EXERC` no início do exercício). A
receita do 2T23 da WEG chegava como R$ 15,87 bi e como R$ 8,17 bi com o mesmo
código, e o leitor ficava com a primeira que aparecesse. Medido sobre a base
completa: **19.237 dos 29.218 ITRs** tinham a duplicação.

**2. "Anual" era "termina em dezembro".** Cinco companhias do universo têm
exercício social fora do calendário — AGRO3 (junho), SMTO3, JALL3 e RAIZ4
(março), CAML3 (fevereiro). Para elas o ITR de dezembro é um acumulado parcial,
e entrava na medição do A1.7 como ano cheio. **O SMTO3 (−45,2 p.p.) e o AGRO3
(−5,6 p.p.) estavam na lista de movimentos daquela medição e eram artefato**;
refeita, o SMTO3 move −0,9 p.p.

**3. O LPA da CVM é zero, e zero não é nulo.** A conta `3.99` vem exatamente
zero em **14.684 de 15.206** exercícios. A regra "a CVM vence" o preferia ao LPA
do mercado, o que desligava em silêncio o árbitro `lucro ÷ LPA` da contagem de
ações.

## Decisão

- Entre as linhas de uma conta no mesmo documento, fica a de **menor
  `DT_INI_EXERC`** — o acumulado. A regra funciona também em exercício que não
  começa em janeiro, que é onde uma regra por mês falharia.
- O **tipo de documento** (DFP ou ITR) entra na chave e na saída. A série anual
  é a DFP, pelo tipo, e nunca pelo mês.
- O comparativo do ano anterior (`PENÚLTIMO`) passa a ser gravado para o ITR,
  com o próprio início de período, porque é dele que saem os doze meses.
- `earningsPerShare` entra em `FundamentalsMerge.somenteDeMercado`, como a
  contagem de ações da decisão 70.

## Consequências aceitas

**A conferência que valida a correção é externa ao leitor.** O comparativo que
o ITR de um ano traz para o mesmo trimestre do ano anterior tem de bater com o
acumulado que o ITR daquele ano publicou. Bate a 0,1% em **89,3%** das receitas,
**92,6%** dos lucros, **88,7%** dos EBITs e **83,0%** dos caixas operacionais,
sobre 21 a 24 mil pares. O resíduo é, como hipótese não verificada,
reapresentação do ano anterior dentro do comparativo.

**O A1.7 foi reportado com dois ativos contaminados**, e o registro daquela
rodada dizia que "os sete que se movem são, cinco deles, bancos" sem apontar
que dois dos outros eram defeito. A medição refeita está em
`docs/validacao/cvm_trimestral.md`.
