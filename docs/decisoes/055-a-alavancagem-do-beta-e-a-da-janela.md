---
numero: 55
titulo: O beta é desalavancado pela alavancagem da janela em que foi estimado e pelo mesmo escudo fiscal com que é realavancado
status: aceita
origem: conselheiro
data: 2026-09-11
citacao: >
  Apurar o debtToMarketEquity em média ou mediana sobre os mesmos anos da
  janela do estimador de risco, para uso em desalavancagens.
afeta:
  - packages/equisim_core/lib/src/services/metrics/market_leverage.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/lib/src/usecases/resolve_beta_prior.dart
  - packages/equisim_core/test/beta_shrinkage_test.dart
  - tool/beta_ida_volta.dart
  - docs/validacao/beta_ida_volta.md
substitui: []
---

## Contexto

A [decisão 54](054-a-regua-da-alavancagem-e-uma-so.md) acertou **qual dívida**
desalavanca o beta. Sobrou **qual data**.

O beta é covariância de **cinco anos** de retorno diário e carrega a estrutura
de capital daqueles cinco anos. A alavancagem que o desalavancava era a do
último exercício publicado — uma foto.

Medido em 11/09/2026 sobre 124 ativos com ao menos três exercícios na janela: o
fator da janela difere do de hoje em mais de 10% em **50** deles e em mais de
25% em **24**. Em 96 dos 124 a empresa está mais alavancada hoje do que esteve
na janela.

## Decisão

**A alavancagem que desalavanca o beta é a mediana da janela em que ele foi
estimado.** `MarketLeverage.overWindow` reconstrói o valor de mercado de cada
exercício da janela pelo **pregão mais próximo do fechamento** vezes a
**contagem de ações daquele exercício**, e devolve a mediana de
`dívida líquida ÷ valor de mercado`.

**Mediana e não média**: um exercício de valor deprimido — fundo de crise,
evento societário — domina a média e não a mediana, e o que se quer é a
estrutura típica do período.

**Com menos de três exercícios utilizáveis, recua para a foto**, que é o
comportamento anterior e fica declarado no código.

**Pregão a mais de vinte dias do fechamento não serve.** Vinte dias cobrem
feriado prolongado e recesso sem alcançar o exercício vizinho; preço de outro
trimestre não descreve aquele fechamento.

## Consequências aceitas

**Oitenta e oito dos 127 preços justos mudam, e agora nos dois sentidos** — 65
caem e 23 sobem, contra 96 caem e 0 sobem da decisão 54. A janela pode ser mais
ou menos alavancada que hoje, e o beta acompanha. CSAN3 −68,2%, MILS3 −50,0%,
KLBN11 −40,6%; UGPA3 +32,2%, ENEV3 +26,6%, JHSF3 +20,3%.

O potencial mediano vai de −37,5% para **−41,8%** e os positivos de 35 para 34.

**A MILS3 expôs um erro de dado que esta decisão conserta de lado.** O
`marketCap` corrente que a fonte publica para ela é de R$ 762 mil contra
R$ 1,28 bi de dívida líquida — errado por três ordens de grandeza —, e o D/E
saturava no teto de 3,0. A medida por janela não usa esse campo: reconstrói o
valor de mercado por preço e contagem do próprio exercício. **O campo continua
errado onde nada o substitui**, e isso fica declarado.

**A contagem de ações do exercício é a certa, e não a corrente.** Usar a
corrente mediria a empresa de hoje nos exercícios de então — o mesmo erro que a
[decisão 25](025-reconstrucao-do-motor-de-avaliacao.md) corrigiu ao criar
`sharesOutstandingAsOf` para o patrimônio.

**A identidade da decisão 54 deixa de valer no ano zero, e é assim que tem de
ser.** `β_U` desalavancado na janela e realavancado na estrutura do modelo não
devolve o beta observado — não devolver é o propósito: `β_U` é grandeza livre
de alavancagem, e realavancá-la em outra estrutura é o que dá sentido a ela. O
que a decisão 54 travou é a álgebra da operação, e essa continua exata.

**E a terceira assimetria da mesma volta: o escudo fiscal.** A ida usava a
alíquota **estrutural** do ativo e a volta, a **estatutária**. O `(1 − τ)` de
Hamada é o escudo fiscal do juro, e a
[decisão 37](037-aliquota-estrutural-no-fluxo-da-firma.md) já dizia que ele
continua na estatutária — *"a dedutibilidade do juro vale na margem, e a margem
é a alíquota cheia"*. A estrutural é a alíquota do **fluxo**, que é outra coisa.

Com a mediana estrutural do universo em 18,6% contra 34% de estatutária, o
termo da dívida saía 23% maior na ida do que na volta. Corrigido: **76 preços
mudam, 75 caem**, com variação mediana de −2,1% — CSAN3 −65,9%, YDUQ3 −16,7%,
ANIM3 −14,2%.

**A contagem de dias é feita em UTC.** A auditoria pegou:
`difference().inDays` entre duas meias-noites locais dá 23 ou 25 horas numa
transição de horário de verão, e o truncamento erra por um dia — exatamente na
margem em que a escolha do pregão mais próximo é decidida.

**A alternativa descartada** era usar a média em vez da mediana. Recusada pela
mesma razão que o resto do motor prefere mediana: um exercício de valor de
mercado deprimido puxaria a alavancagem típica para o pior ponto do período.
