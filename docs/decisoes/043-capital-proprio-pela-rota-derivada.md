---
numero: 43
titulo: O capital próprio passa a vir do fluxo do acionista derivado, e a ponte deixa de decidir preço
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Prossiga para D1c e D1d se possível. Rode as lentes. Pode ignorar as
  decisões anteriores.
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - docs/validacao/identidade_das_vias.md
substitui: []
---

## Contexto

A [decisão 41](041-custo-de-capital-realavancado-ano-a-ano.md) provou que as
duas rotas do capital próprio coincidem dentro de **1e-6** quando o custo de
capital é resolvido ano a ano, e a [decisão 42](042-caminho-de-taxas-em-producao.md)
ligou o solucionador à produção. Faltava o passo que dá sentido aos dois: o
capital próprio ainda vinha de `EV − D`.

A ponte é a diferença de dois números grandes e quase iguais quando o capital
próprio é fino, e o erro relativo do valor da firma chega ao preço por papel
amplificado por `1/participação` — 138 vezes na RENT3. Era isso que a
pós-condição dos 20% e a mescla da
[decisão 38](038-transicao-continua-entre-as-vias.md) existiam para conter.

## Decisão

**Com o caminho de taxas resolvido, o preço por papel vem de
`DcfCalculator.equityFromFirm`** — o fluxo do acionista derivado do da firma,
`FCFE = FCFF − juros(1−τ) + ΔDívida`, descontado ao caminho de `Ke`.

**Não é uma segunda opinião.** Sob o caminho resolvido as duas rotas coincidem,
e isso está travado por teste. O que muda é a **condição numérica**: a rota
derivada não faz a subtração.

**A pós-condição dos 20% e a mescla deixam de se aplicar ali.** Elas existiam
para escolher entre dois estimadores que discordavam; sob esta rota há um só.
Continuam valendo no recuo — sem `β_U` ou sem convergência, a ponte é o
caminho, e com ela a proteção.

## Consequências aceitas

**Trinta e seis dos 122 preços justos se movem além de 0,5%**, com variação
mediana de **+0,0%**. O potencial mediano vai de −37,3% para **−35,8%**, o p75
de −5,3% para **+1,5%** — o quartil superior cruzou o zero — e os positivos de
27 para **31**. O multiplicador necessário no fluxo cai de 1,37× para 1,31×.

**Nove ativos deixam de migrar, e três caem muito**: VBBR3 −70%, ENGI11 −67%,
RENT3 −67%. Eles migravam para a via do acionista e recebiam o número dela, que
era mais alto. **Isso não era uma estimativa melhor — era outro modelo**, como a
[decisão 39](039-as-duas-vias-sao-modelos-independentes.md) mediu. Sob a rota
derivada eles recebem o que a própria avaliação da firma produz, e o motor
deixa de escolher o maior entre dois números que discordam.

**O `terminalShare` do diagnóstico muda de significado na rota derivada**: passa
a ser a fração do **capital próprio** explicada pelo terminal, não a do valor da
firma. Em ativo alavancado ela é maior, e a ressalva de terminal pesado dispara
mais. É mudança de referência declarada, não de critério.

**A via do acionista sobre LPA continua** para quem cai no recuo e para
instituição financeira, e com ela a discordância da decisão 39.

**A alternativa descartada** era manter a ponte e a pós-condição junto com a
rota derivada, usando-a só onde a participação é fina. Recusada porque
reintroduziria o degrau que a decisão 38 removeu — agora entre a ponte e a rota
derivada, em vez de entre as duas vias.
