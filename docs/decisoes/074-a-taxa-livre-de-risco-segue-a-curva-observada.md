---
numero: 74
titulo: A taxa livre de risco pode seguir a curva observada, e o padrão é decisão do usuário
status: aceita
origem: parecer
data: 2026-09-14
afeta:
  - packages/equisim_core/lib/src/services/valuation/yield_curve.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/test/yield_curve_test.dart
  - packages/equisim_core/test/usecases_test.dart
  - tool/curva_ligar.dart
  - tool/tesouro_baixar.py
  - docs/validacao/curva_de_juros.md
substitui: []
---

## Contexto

A §2.9 registrava que a estrutura a termo do motor "não é uma curva de juros":
a taxa livre de risco de cada ano era uma interpolação linear entre **dois
pontos do CDI** — o corrente e a média decenal —, e a perpetuidade era
descontada nesta última.

O Tesouro Transparente publica, por dia desde 2004 e sem cadastro, a taxa de
cada título do Tesouro Direto. Com o *Tesouro Prefixado* (LTN, cupom zero) e o
*Prefixado com Juros Semestrais* (NTN-F), a curva nominal tem vértices de 0,3
a cerca de 10 anos em toda data amostrada desde 2015.

Confrontada com o motor, coorte a coorte:

| coorte | motor: ano 1 → perpetuidade | curva: ano 1 → perpetuidade | diferença na perpetuidade |
|---|---|---|---:|
| 2018 | 6,39% → 10,41% | 8,09% → 12,10% | +1,69 p.p. |
| 2019 | 5,99% → 9,92% | 4,94% → 7,81% | −2,11 p.p. |
| 2020 | 2,00% → 9,32% | 3,10% → 8,96% | −0,36 p.p. |
| 2021 | 4,88% → 8,46% | 9,01% → 11,96% | **+3,50 p.p.** |
| 2022 | 13,48% → 8,61% | 12,37% → 12,36% | **+3,75 p.p.** |
| 2023 | 13,27% → 9,21% | 10,96% → 12,11% | +2,90 p.p. |
| 2024 | 10,43% → 9,28% | 12,17% → 12,31% | +3,03 p.p. |
| 2025 | 14,90% → 9,36% | 14,02% → 13,84% | **+4,48 p.p.** |

**Desde 2021 o motor desconta a perpetuidade 2,9 a 4,5 p.p. abaixo do que o
mercado de títulos precifica.** E a forma também: em 2022 a interpolação fazia
a taxa cair de 13,5% a 8,6% — uma previsão de queda de juros que a curva,
plana em 12,4%, não continha.

## Decisão

`YieldCurve` monta a curva nominal a partir dos títulos prefixados, com
interpolação flat-forward e extrapolação pelo último forward. `TreasuryCurve.at`
escolhe a data-base mais recente **até** a avaliação, nunca depois — é o que
permite a curva de cada coorte do backtest.

`ValuationInputs.riskFreeCurve`, quando presente, faz a taxa de cada ano da
projeção ser o **forward de um ano** da curva e a da perpetuidade o forward
depois do fim da projeção. Ausente, vale a interpolação de dois pontos, sem
mudança nenhuma.

A troca é **só da fonte da taxa**, e isso está provado por teste: uma curva
plana na taxa do CDI, com a taxa estrutural igual a ela, reproduz o motor sem
curva a 1e-9 no potencial.

**O padrão do aplicativo não muda nesta decisão.**

## Consequências aceitas

**O efeito é grande no nível e pequeno na ordenação.** Em 04/09/2026, mesmos
fundamentos e mesmo preço:

| | dois pontos | curva |
|---|---:|---:|
| avaliados | 127 | 127 |
| potencial mediano | −37,6% | **−48,6%** |
| fração com potencial positivo | 30,4% | **16,8%** |
| correlação de postos | | **0,9325** |

A curva é a escolha defensável para o **valuation exemplar** — é a taxa que o
mercado atribui a cada prazo, e não uma previsão do motor. Mas ela piora o
nível que a §2.8 já registrava como deslocado, e muda o que o usuário lê em
toda tela de avaliação. **Ligá-la por padrão é decisão do usuário**, e fica
explícita no plano como tal.

**As aproximações, declaradas no código:** prazo em anos corridos e não em
dias úteis; taxa da NTN-F tratada como taxa à vista — em 10/09/2026, LTN e
NTN-F de mesmo prazo diferem em −20 e +2 bp —; e só a curva nominal, sem a
real das NTN-B. A consistência entre crescimento nominal e desconto nominal é o
item B7.

**`capm.riskFreeRate` continua sendo o CDI corrente** nos usos fora do caminho
de taxas — custo da dívida padrão, conferências de auditoria. Com curva, o ano
1 do caminho vem do forward da curva, e os dois podem diferir por dezenas de
pontos base.
