---
numero: 58
titulo: O retorno esperado transversal ancora no custo de capital próprio, o caixa rende a taxa livre de risco, e três invariantes do núcleo passam a ser do tipo
status: aceita
origem: voce
data: 2026-09-11
citacao: >
  Prossiga com os itens do bloco B. Se achar necessário, corrija também os
  erros inventariados de código "legado" pelas lentes.
afeta:
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/lib/src/services/portfolio/expected_return.dart
  - packages/equisim_core/lib/src/services/goal/feasibility.dart
  - packages/equisim_core/lib/src/repositories/repositories.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/portfolio_test.dart
  - packages/equisim_core/test/result_and_rates_test.dart
  - lib/di/providers.dart
  - lib/presentation/backtest/backtest_providers.dart
  - lib/presentation/goals/goal_page.dart
  - tool/retorno_esperado.dart
  - docs/validacao/retorno_esperado.md
substitui: []
---

## Contexto

O Bloco A fechou sem defeito conhecido. O que restava vivo estava na camada que
transforma preço justo em decisão de carteira, e a lente `metodo` apontava o
mesmo item havia **oito rodadas**.

## Decisão

### 1. O retorno esperado transversal ancora no `Ke`, e não no CDI

```
E[R_i] = Ke_i + z_i · prêmio      (antes: CDI + z_i · prêmio)
```

O ativo **mediano** da seção recebia exatamente o CDI, de modo que o prêmio de
risco aparecia só como dispersão e nunca como nível. Medido sobre os 127
avaliados: a mediana do retorno esperado era **14,09% — o próprio CDI** — e
passa a **20,45%**; a carteira igualmente ponderada vai de 15,09% para 21,06%,
**+5,97 p.p.**

Antes, segurar as 127 ações prometia **um ponto percentual** acima da renda
fixa, contra os 5,5 de prêmio que o mesmo motor usa para descontar o fluxo.

`ValuationDiagnostics.costOfEquity` passa a sair com o resultado — é
`Rf + β·prêmio` sobre a taxa corrente. Sem ele, a âncora recua para o CDI e o
resultado declara em `CrossSectionalReturn.anchoredOnCostOfEquity`; nos 127,
nenhum precisou do recuo.

### 2. `RateSeries` exige alinhamento, e `annualized` exige base positiva

A série prometia `dates` e `rates` alinhadas posição a posição e **não
verificava**. A justificativa registrada era que `annualized` só consulta
`rates` — o que torna a divergência invisível até alguém indexar as duas, e aí
o estouro acontece longe da origem.

Passa a lançar `ArgumentError` na construção, e não a devolver `Result`: é erro
de programação, não de dado. **A invariante pegou o próprio teste**, que
construía três taxas com zero datas.

`annualized` passa a recusar base não positiva, que produziria infinito ou
expoente invertido — os dois saindo como número plausível.

### 3. `FeasibilityVerdict.requiredAnnualRate` deixa de ser `double.infinity`

O sentinela dizia "não há taxa" com um número, e obrigava todo consumidor a
lembrar de testar `isFinite` antes de formatar. Passa a ser `double?`, e o
compilador cobra o tratamento nos quatro pontos da interface que o liam.

### 4. O Sharpe usa a taxa livre de risco **da janela simulada**

`riskFreeRateProvider` devolve o CAGR decenal do CDI, e a simulação pode correr
três anos. **A Selic saiu de 2% para 14%** no intervalo que o cache cobre:
confrontar o retorno de uma janela com a renda fixa de outra mede a diferença
entre os períodos, não o prêmio pelo risco.

`riskFreeRateForWindowProvider` resolve o CDI da própria janela, e recua para o
decenal sem rede ou sem pregão. **A janela chega por parâmetro**: montá-la
dentro do provedor a partir do relógio tornaria a resposta não determinística,
que é a regra que o gate cobra.

### 5. Caixa rende taxa livre de risco, e não o WACC

Sem dívida bruta não há custo de dívida a medir, e o recuo era a própria taxa
de desconto. Com dívida líquida **negativa** ela multiplica um peso negativo:
**o motor creditava ao caixa o rendimento do negócio**.

Medido: 18 dos avaliados chegam ao recuo, e em 16 a via é a do acionista, que
não usa este número. Os dois que usam são ALOS3, com R$ 2,43 bi de caixa
líquido, e BRAP4, com R$ 18 mi. Trocando o recuo pela taxa livre de risco:
**ALOS3 −10,5%** e SAUD3 −1,4%.

A lente `metodo` apontou a linha, e a conferência mostrou que o recuo é
inalcançável por falta de dado — **nenhum** ativo com dívida fica sem `Kd`
medível — e alcançável por excesso de caixa, que é outro caso.

## Consequências aceitas

**Dois preços justos mudam**, e só pelo item 5: ALOS3 −10,5% e SAUD3 −1,4%. Os
itens 1 a 4 não tocam a cascata de avaliação — o que muda neles é o que a
camada de carteira faz com ela.

**O retorno esperado da carteira sobe cerca de 6 p.p.**, e com ele a comparação
contra a rentabilidade exigida pela meta. Metas que apareciam como inatingíveis
podem passar a caber — e é o número certo que passa a decidir isso.

**O nível do potencial continua fora da conta.** A âncora mudou; a recusa em
anualizar o potencial, não. As duas coisas são independentes, e a segunda tem
razão própria registrada em `ExpectedReturn`.

**`maxAssets = 15` continua na entidade**, embora seja limite de interface —
a lente `nucleo` aponta, e mover exige decisão sobre o contrato da tela, não
só refatoração. Fica listado.

**A bandeira da âncora sai de haver `Ke`, e não de comparar as duas.** A
auditoria pegou: comparar `double` por desigualdade declararia recuo onde não
houve, e beta zero produz `Ke == CDI` legitimamente.

**A alternativa descartada** para o item 1 era somar o prêmio à âncora única
(`CDI + prêmio + z·prêmio`). Recusada porque apagaria o beta: dois ativos no
mesmo ponto da seção têm retornos esperados diferentes quando têm riscos
sistemáticos diferentes, e é exatamente isso que o `Ke` de cada um carrega.
