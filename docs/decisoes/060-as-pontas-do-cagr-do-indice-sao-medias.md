---
numero: 60
titulo: As pontas do CAGR do índice são médias, e os anos vão de centro a centro
status: aceita
origem: parecer
data: 2026-09-11
afeta:
  - packages/equisim_core/lib/src/usecases/portfolio_usecases.dart
  - packages/equisim_core/test/market_anchors_test.dart
substitui: []
---

## Contexto

`ResolveMarketAnchors` apura duas taxas de crescimento a partir de séries
longas, e as apurava de dois jeitos diferentes.

`_activityCagrOf`, do IBC-Br, já media **médias móveis de doze meses** nas duas
pontas e contava os anos **entre os centros** das duas médias. A justificativa
estava escrita no próprio código: *"um CAGR entre dois pontos isolados herdaria
inteiramente o ruído deles"*.

`_cagrOf`, do Ibovespa, media **ponta a ponta** — o fechamento do primeiro
pregão contra o do último. O índice de bolsa oscila muito mais que um índice de
atividade dessazonalizado, e era o único dos dois sem o tratamento.

O CAGR do Ibovespa é o `marketCagr`, que alimenta o prêmio de risco de mercado.
Dois dias de pregão decidiam o nível dele.

## Decisão

`_cagrOf` passa a promediar **63 pregões** (um trimestre) em cada ponta e a
medir os anos **de centro a centro** das duas médias, como `_activityCagrOf` já
fazia. Em série curta a janela encolhe para metade dos pontos disponíveis, de
modo que as duas pontas nunca se sobreponham.

Medido em 11/09/2026, na janela de dez anos — 2.479 pregões, 9,97 anos:

| ponta | CAGR |
|---|---:|
| 1 pregão (antes) | **12,57%** |
| 21 pregões | 11,43% |
| 63 pregões (agora) | **11,06%** |
| 252 pregões | 10,24% |

**1,51 ponto percentual** separava a medida antiga da nova.

## Consequências aceitas

A média atrasa o sinal: uma alta recente entra no CAGR diluída por um
trimestre. É o preço de não herdar o ruído de dois dias, e é o mesmo preço que
o índice de atividade já pagava — a alternativa descartada é manter duas
convenções para a mesma pergunta, que era o estado anterior.

Escolher 63 e não 21 ou 252 é escolha de calibragem, não de princípio: 21
pregões ainda deixam 11,43% (0,37 p.p. da medida trimestral) e 252 derrubam
para 10,24%. O trimestre é o menor prazo em que o resultado para de se mover
com a janela.

`ResolveMarketAnchors` não tinha teste nenhum antes desta decisão. O que os
seis novos testes fixam não é a fórmula, e sim a propriedade que a justifica:
**sobre uma exponencial limpa o estimador recupera a taxa exata**, a 1e-9, para
5%, 10% e 18% ao ano. É por isso que os anos vão de centro a centro — promediar
as pontas sem deslocar as datas encurtaria o expoente e enviesaria o CAGR para
cima.
