---
numero: 142
titulo: O prêmio de mercado do CAPM passa a ser a média de dez anos do prêmio implícito no preço da bolsa
status: aceita
origem: voce
data: 2026-10-01
citacao: >
  Depois de analisar todas essas variáveis, decidimos implementar somente a
  mudança no prêmio de risco para implementar a média dos 10 anos. Pode
  realizar a implementação no código, corrigindo e implementando todos os itens
  relacionados a esta implementação. A questão do crescimento apenas deixe de
  lado, por enquanto. Pode consultar a B3 e fazer o backtest com o prêmio
  normalizado.
afeta:
  - packages/equisim_core/lib/src/services/valuation/implied_premium.dart
  - packages/equisim_core/lib/src/services/valuation/cost_of_capital.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/portfolio_usecases.dart
  - lib/data/repositories/market_premium_repository.dart
  - lib/di/providers.dart
  - lib/presentation/valuation/valuation_providers.dart
  - lib/presentation/study/study_page.dart
  - assets/mercado/premio_implicito.json
  - tool/premio_implicito.dart
  - tool/validation/congelado.dart
  - tool/gabarito_cascata.dart
  - tool/backtest_valuation.dart
  - docs/validacao/premio_implicito.md
substitui:
  - 116
---

## Contexto

O prêmio de risco de mercado do CAPM era **5,5% fixo** desde a decisão 116, que
o manteve depois de medir as duas alternativas que o item B3 pedia: o histórico
com encolhimento devolvia 5,49%, e o «implícito» de então — o prêmio que zerava
o potencial mediano **do motor** — saía −3,9%.

Em 29/09/2026, conferindo os cálculos, o orientador perguntou de onde vinha o
prêmio e se havia como capturá-lo do mercado em vez de deixá-lo fixo
(apontamento de 29/09, item B42). Duas medições responderam:

- **O histórico** — o Ibovespa contra o CDI na mesma janela
  ([premio_historico.md](../validacao/premio_historico.md)) — depende da janela
  (−2,17% a +1,85% hoje) e foi negativo em 25 das 31 coortes do backtest.
- **O implícito no preço da bolsa** — o método de Damodaran
  ([premio_implicito.md](../validacao/premio_implicito.md)): em cada fim de
  trimestre desde 2011, o valor de mercado somado das listadas igualado aos
  dividendos e JCP de doze meses, crescendo com a economia nominal. O do
  trimestre fica negativo quando o prefixado dispara; **a média de dez anos fica
  positiva em todas as coortes**, entre 0,9% e 1,6%, e concorda com o histórico
  de dez anos de hoje.

O usuário e o orientador decidiram pela média de dez anos em 01/10/2026, depois
de ver também a medição do crescimento (item B45), que fica de lado.

## Decisão

**O prêmio de mercado é a média de dez anos do prêmio implícito**, a mesma
para todo ativo:

1. **O prêmio de cada trimestre é `r − Rf`**, com `r = rendimento × (1 + g) +
   g` (o retorno que o preço da bolsa embute; `g` é o crescimento nominal da
   economia das âncoras de mercado) e `Rf` o prefixado de dez anos da curva do
   Tesouro na mesma data. É a diferença, e não a razão de Fisher, porque o CAPM
   do motor soma: `Ke = Rf + β × prêmio`. Com beta 1, a diferença devolve
   exatamente o retorno que o preço embute.
2. **A média é a dos trimestres com fim em `(data − 10 anos, data]`**, com pelo
   menos 20. A série começa em 2011; as coortes de 2018 usam os 29 a 32
   trimestres que havia, e a janela está cheia a partir de 31/12/2020.
3. **A série chega por pacote**, `assets/mercado/premio_implicito.json`, gerado
   por `tool/premio_implicito.dart --so-serie` e versionado — o aplicativo não
   tem como somar a bolsa inteira para avaliar um ativo. Em 14/09/2026 o prêmio
   é **1,21%**.
4. **Sem pacote, o prêmio é o parametrizado de 5,5%**, e a avaliação diz isso.
   O pacote velho continua valendo — a média anda um quadragésimo por trimestre,
   e trocá-la pelos 5,5% seria salto maior que a defasagem —, com ressalva da
   data depois de 183 dias.
5. **O retorno esperado da tela de estudo e da meta usa o mesmo prêmio** no
   escore das ordenações: as duas pontas do trabalho não podem adotar prêmios
   diferentes.
6. **O backtest usa, em cada coorte, a média até a data dela**, só com os
   trimestres anteriores. As montagens antigas do gabarito (`doisPontos`,
   `curva`) e a montagem `mercado` do backtest ficam com 5,5%: são o registro do
   que se mediu antes.

**Provento entra no prêmio, e só nele.** A série do prêmio implícito soma os
proventos da bolsa inteira — é a primeira vez que provento entra na avaliação
desde a decisão 23, e a decisão 89 o tinha reaberto só como retorno total da
validação. Entra **agregado**, como insumo de uma grandeza de mercado; o fluxo
de cada ativo, a simulação da carteira e o retorno esperado continuam de preço.

## Consequências aceitas

- **O nível do motor passa a vir, em parte, do mercado.** Um prêmio tirado do
  preço do mercado inteiro aproxima o preço justo mediano do preço por
  construção. O teste que continua valendo é o de **ordem** entre as ações
  (R3), que um prêmio igual para todas não mexe.
- **O prêmio carrega uma premissa de crescimento**: um ponto a mais ou a menos
  em `g` move o prêmio em cerca de um ponto. E não conta a recompra de ações, e
  soma só as companhias listadas hoje nas datas antigas da série.
- **O pacote tem de ser regerado a cada trimestre** para a média acompanhar o
  mercado; a ressalva de 183 dias existe para que o esquecimento apareça.
- **A réplica do C7 continua decidida pelo motor pré-registrado** do commit
  `e856ec6` (decisão 138); o motor desta decisão entra nela como a série «motor
  da data», de referência.
- **A faixa calibrada e a habilidade foram remedidas** com o backtest de cada
  coorte no prêmio dela: ver o plano (itens B42, C2c e C1) e
  [habilidade_trimestral.md](../validacao/habilidade_trimestral.md).
