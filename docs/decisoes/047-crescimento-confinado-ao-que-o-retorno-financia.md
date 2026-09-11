---
numero: 47
titulo: O contrafactual passa a rodar pela cascata, e o crescimento é confinado ao que o retorno financia
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Prossiga pelo bloco A, iniciando por D4. Mesmo esquema: ao final, reestruture
  a lista necessária para chegar ao valuation sem erros conhecidos e motor de
  referência ao final e rode as lentes.
afeta:
  - packages/equisim_core/lib/src/services/valuation/dcf.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - tool/fluxo_explicito.dart
  - docs/validacao/fluxo_explicito.md
substitui: []
---

## Contexto

O D4 pergunta de onde vem o resíduo entre o preço justo e o de mercado. A
resposta anterior — 1,74× de multiplicador mediano, decomposto por
contrafactuais — vinha de um laço escrito dentro de
`tool/fluxo_explicito.dart` que replicava a projeção do núcleo.

**O laço deixou de replicá-la e nada acusou**, porque a conferência que o
acompanhava comparava o laço contra `DcfCalculator` com as mesmas premissas: só
provava que ele somava certo. Três diferenças acumuladas: crescimento perpétuo
igual ao teto da economia em 78 dos 120 ativos, reinterpolação de dois pontos
no lugar do caminho resolvido da
[decisão 41](041-custo-de-capital-realavancado-ano-a-ano.md), e a ponte
`EV − D` no lugar da rota derivada da
[decisão 43](043-capital-proprio-pela-rota-derivada.md).

É o mesmo defeito que a [decisão 45](045-estrutura-de-capital-recusada.md)
encontrou em `tool/vias.dart`: **costura de diagnóstico que reconstrói o insumo
mede outro motor, em silêncio.**

## Decisão

**O contrafactual passa a ser imposto à cascata.** `ValuationInputs` ganha
`reinvestmentOverride` e `cashTimingOverride`, declarados no resultado como
instrumento de diagnóstico — como `laneOverride`, `growthOverride` e
`baseFactorOverride` já são. O utilitário perde a projeção própria.

**O vão passa a ser medido em `preço ÷ justo`**, e não em multiplicador do
valor da firma: a conversão antiga trazia a amplificação `1/participação` para
dentro da medida.

**O crescimento projetado é confinado ao que o retorno financia:**
`g_t ≤ 0,95 · ROIC_t`, e o mesmo contra o retorno terminal na perpetuidade.

É a identidade `g = b·ROIC` aplicada na **premissa** em vez da consequência.
Antes ela era aplicada só na consequência: `b = g/ROIC` truncado em 0,95
deixava o lucro compor à taxa cheia enquanto apenas 95% dele era cobrado pelo
financiamento, e a diferença virava caixa distribuível de uma expansão que
ninguém pagou.

## Consequências aceitas

**Quatorze dos 116 ativos com retorno utilizável tinham `g > ROIC`, e os 14
estavam no teto da retenção.** MOVI3 projetava 31,8% de crescimento sobre 13,4%
de retorno; na FESA4 o freio pedia 6,8 vezes o lucro operacional antes de ser
truncado. Nesses o crescimento cai para `0,95·ROIC`.

**O teto de 95% deixa de ser alcançável por truncamento.** Desligá-lo passa a
mover zero ativos — `m = 1,00×` — porque os 15 que ainda estão em `b = 0,95`
chegaram lá pelo confinamento do crescimento, não pelo corte da retenção. A
retenção mediana do ano N cai de 51,0% para 38,9%.

**O item D6 da fila fecha por medição, e não por escolha.** A pergunta era se o
teto de 95% distorcia o fluxo; a resposta é que ele não segurava nada — o que
distorcia era o crescimento não financiável que ele mascarava.

**Os números publicados da §3 de `fluxo_explicito.md` ficam obsoletos**, e o
documento os mantém com a data e a razão. O vão remedido é de 1,42× na mediana,
com 36 dos 120 já acima do preço de mercado.

**O freio continua a não ser candidato a conserto.** Desligá-lo fecha 30,5% do
vão e cobrar só o crescimento real fecha 27,7%, e os dois seguem sendo escolha
de método — afrouxá-los para fechar o vão é ajustar o motor ao mercado, o que a
[decisão 35](035-dcf-reverso-e-regressao-condicional.md) veda.

**A alternativa descartada** era consertar o laço do utilitário em vez de
removê-lo. Recusada porque o defeito não é o laço estar errado hoje: é ele
poder ficar errado de novo a cada decisão que muda a cascata, sem que a
conferência veja.
