---
numero: 51
titulo: A volta entre o veredito e a taxa é fechada até parar, e o peso do terminal passa a medir a mesma coisa nas três rotas
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Prossiga com o bloco A, por D12. Mesmo esquema: ao final, reestruture a lista
  necessária para chegar no valuation sem erros conhecidos e motor de
  referência. Ao final, rode as lentes.
afeta:
  - packages/equisim_core/lib/src/services/valuation/growth_guards.dart
  - packages/equisim_core/lib/src/services/valuation/dcf.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - tool/fluxo_explicito.dart
  - docs/validacao/fade_terminal.md
substitui: []
---

## Contexto

O D12 tinha duas pendências abertas pela
[decisão 44](044-moat-contra-a-taxa-resolvida.md) e pela
[decisão 43](043-capital-proprio-pela-rota-derivada.md).

**A primeira: não havia terceiro passe.** O veredito da vantagem competitiva se
mede contra a taxa de equilíbrio; o retorno terminal que ele concede muda a
projeção; a projeção muda a alavancagem; a alavancagem muda a taxa. A decisão
44 fechou um passe dessa volta e parou, com o argumento de que o `λ` mediano de
0,0015 tornava o resíduo de segunda ordem.

**A segunda: `terminalShare` mudou de referência.** Na ponte ele media contra o
valor da **firma**; na rota derivada e na via do acionista, contra o do
**acionista**. O mesmo campo carregava duas grandezas conforme um caminho que o
leitor não vê, e o corte de 80% da ressalva `terminalPesado` valia para as duas.

## Decisão

**A volta é fechada até o par parar de mudar**, com teto de
`ValuationParameters.moatMaxPasses = 10`.

**O teto não é conveniência: a circularidade não tem ponto fixo em alguns
ativos.** Na fronteira exata do veredito, conceder o excedente muda a taxa o
bastante para recusá-lo, e recusá-lo a devolve. Quando isso acontece, a parada é
declarada com o motivo — teto alcançado, ou o solucionador não fechou a taxa que
o veredito seguinte pedia.

**O veredito só é adotado depois que a taxa dele fecha.** O código anterior o
adotava antes, de modo que uma falha do solucionador deixava o preço com o
retorno terminal de um passe descontado pelo caminho de taxas do outro.

**O peso do terminal passa a ser medido contra o capital próprio nas três
rotas.** A pergunta que a ressalva faz é quanto do **preço** repousa sobre a
perpetuidade, e o preço é o do acionista: a dívida é subtração fixa, e o
terminal contribui com o valor descontado inteiro dele para o que sobra.

**Ele pode passar de 100%, e passar é o sinal.** Com capital próprio fino o
terminal descontado supera o que sobra ao acionista; truncar em 1 esconderia
exatamente o caso mais frágil.

## Consequências aceitas

**Doze dos 105 precisavam de três passes ou mais**, e três não estabilizam. O
`λ` mediano pequeno que sustentava a parada em dois passes continua verdadeiro —
o que ele não dizia é que a cauda existe.

**Quatro preços justos mudam**, e por dois motivos distintos:

| Ativo | variação | causa |
|---|---:|---|
| KLBN3 | **+17,5%** | par descasado entre veredito e taxa |
| KLBN11 | +17,4% | mesma |
| TAEE4 | −2,7% | ponto fixo, dez passes |
| SMTO3 | −1,8% | ponto fixo, nove passes |

**A ressalva `terminalPesado` passa a marcar 7 ativos em vez de 2.** Os cinco
que apareceram têm terminal acima de 80% do preço e abaixo de 80% do valor da
firma — eram exatamente os que a referência antiga escondia, e são os
alavancados.

**Números de `terminalShare` publicados ficam defasados** para todo ativo com
dívida. O peso mediano do universo vai de 41% para 43%.

**O teto de dez passes é parâmetro novo**, e é o único desta decisão. Ele está
onde a cauda medida termina, com folga sobre os nove que o pior caso
convergente consumiu — não é escolha de gosto, é o topo de uma distribuição
observada.

**O `NaN` deixou de ser sentinela na participação do capital próprio.** A
auditoria pegou: pelo lado do acionista `enterpriseValue` é `E + D`, e com
caixa líquido maior que o próprio negócio ele fica não positivo — a razão
perdia sentido e saía formatada como `NaN%` no aviso ao usuário.
`LeveredRates.equityShareAt` passa a devolver nulo, e quem escreve o aviso
decide o que dizer no lugar.

**A alternativa descartada** era manter dois passes e declarar o resíduo.
Recusada porque a medição derrubou o argumento que a sustentava: o resíduo não
é de segunda ordem em doze ativos, e em três ele nem sequer converge — coisa
que dois passes não têm como revelar.
