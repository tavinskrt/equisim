---
numero: 40
titulo: O beta é encolhido por precisão, e não substituído pela mediana setorial
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Pode começar com o beta desalavancado e depois prosseguir para A2
afeta:
  - packages/equisim_core/lib/src/services/metrics/beta.dart
  - packages/equisim_core/lib/src/services/metrics/beta_shrinkage.dart
  - packages/equisim_core/lib/src/services/valuation/cost_of_capital.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/lib/src/usecases/resolve_beta_prior.dart
  - packages/equisim_core/test/beta_shrinkage_test.dart
  - tool/beta_setorial.dart
  - docs/validacao/beta_setorial.md
substitui: []
---

## Contexto

A [decisão 39](039-as-duas-vias-sao-modelos-independentes.md) estabeleceu que
`Ke` e `WACC` não estão ligados pela alavancagem, e que sem essa ligação a
conciliação das vias não acontece. O beta desalavancado virou pré-requisito.

A proposta era o beta *bottom-up* clássico: desalavancar por Hamada, tomar a
**mediana setorial** como risco de negócio e realavancar. Ela supunha duas
coisas, e a medição em [`beta_setorial.md`](../validacao/beta_setorial.md)
derrubou as duas:

1. **A regressão individual não é ruidosa.** Erro-padrão mediano de **0,07**
   sobre ~1.250 pregões, e acima de 0,30 em apenas 6 dos 363.
2. **O setor explica pouco.** Agrupar reduz a dispersão robusta em **13,1%**
   (0,40 para 0,35), e os setores grandes ficam entre 0,41 e 0,48 de dispersão
   interna. **95 dos 363** não têm setor com três pares.

Substituir moveria o `Ke` do ativo mediano em **2,13 p.p.**, trocando um
estimador de erro-padrão 0,07 por uma mediana de dispersão interna 0,35.

## Decisão

**A substituição pela mediana setorial fica descartada, por medição.**

**O beta passa a ser encolhido por precisão**, no esquema de Vasicek:

```
w = (1/SE²) / (1/SE² + 1/σ_prior²)
β = w · β_regressão + (1 − w) · β_prior
```

Nenhum limiar decide — a precisão decide, e é contínua. Medido: peso mediano de
**0,98** no estimador individual, **23 dos 363** abaixo de 0,90, e `|ΔKe|`
mediano de **0,03 p.p.** O ativo típico não se move.

**`BetaEstimate` passa a carregar o erro-padrão**, pela identidade
`SE(β) = |β|·√((1−ρ²)/(ρ²·(n−2)))`. Sem ele o encolhimento não existe, e sem
ele o motor aceitava qualquer número: a **AZUL3** devolve `β = 109.108` com
`ρ = 0,11` sobre 142 pregões e erro-padrão de **83.228**, e entrava no CAPM
indistinguível de um beta de verdade.

**`D/E` é confinado em 3,0** na relação de Hamada. Ela supõe dívida sem risco;
acima disso o capital próprio é opção sobre os ativos e a relação linear deixa
de descrever. Medido, `D/E` tem mediana de 0,28 e p75 de 1,96, mas chega a 94,5
onde o valor de mercado do capital próprio praticamente sumiu.

**O prior é resolvido fora da cascata**, por `ResolveBetaPrior`, no mesmo
arranjo de `ResolveMarketAnchors`: a cascata avalia um ativo por vez e é pura,
e estatística transversal não cabe ali. Sem prior, vale a regressão crua — o
comportamento anterior.

## Consequências aceitas

**O ganho direto é pequeno, e é honesto dizê-lo.** Em produção, o preço justo
se move **0,09%** na mediana dos 122 avaliados, com 21 além de 0,5% e máximo de
4,57%. Os betas degenerados pertencem a ativos que a Porta 0 já filtra. O que a
decisão compra não é nível — é **não deixar entrar no CAPM um número sem
informação**.

**O que ela entrega de fato é o insumo de A2.** `ShrunkBeta.unlevered` passa a
ser grandeza de primeira classe, e é ela que liga `Ke` a `WACC`.

**`BetaSource` ganha `shrunk`**, e só aparece quando o encolhimento moveu o
número.

**A taxonomia setorial continua sendo a da fonte**, não GICS nem B3 — a §1.5
das [limitações](../validacao/limitacoes.md). Outra taxonomia daria outras
medianas, e o prior herda essa escolha.

**O erro-padrão supõe regressão simples e resíduo bem comportado.** Não há
correção para autocorrelação nem heterocedasticidade, que o `inference.dart`
já sabe fazer em outro contexto — a estimativa é de triagem, e o uso dela aqui
é de peso relativo, não de teste de hipótese.

**O prior é do universo do dia**, e a §1.8 das limitações registra que ele
varia entre execuções. Duas execuções em dias diferentes podem encolher de
formas ligeiramente diferentes.

**A alternativa descartada** era adotar o *bottom-up* setorial assim mesmo, por
ser a prática consagrada. Recusada porque a prática pressupõe regressões
ruidosas, e as deste universo não são — a medição contradiz a premissa, não a
técnica.
