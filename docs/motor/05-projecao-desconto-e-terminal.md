# 5. Projeção, desconto e terminal

As fórmulas do fluxo de caixa descontado, como o código as executa. Estudo:
[guia, cap. 1](../estudo/01-dinheiro-no-tempo.md) e
[cap. 4, seções 4.6 a 4.9](../estudo/04-fluxo-de-caixa-descontado.md). Cada
fórmula abaixo é refeita com números nos [casos](../estudo/casos/).

Código: [dcf.dart](../../packages/equisim_core/lib/src/services/valuation/dcf.dart)
(`DcfAssumptions`, `DcfCalculator`) e
[compute_valuation.dart, `_premissas`, `_descontarDoBalanco`](../../packages/equisim_core/lib/src/usecases/compute_valuation.dart).

---

## 5.1 As premissas de cada ano

`N = 10` anos (decisão 115, por medição: o nível não depende do horizonte, e o
peso do terminal sim). `t` vai de 1 a N.

| Grandeza | Fórmula | Função | Fundamento |
|---|---|---|---|
| Crescimento | `g_t = g − (g − g∞)·(t − 1)/(N − 1)`, limitado a `0,95·ROIC_t` | `growthAt`, `sustainable` | desgaste gradual da vantagem (McKinsey, "fade") |
| Taxa | caminho ano a ano (resolvido, ou da curva), ou `r − (r − r∞)·(t − 1)/(N − 1)` sem caminho | `discountRateAt` | capítulo 4, seção 4.5 |
| Retorno sobre o capital | `ROIC_t = ROIC_base − (ROIC_base − r_t)·(t − 1)/(N − 1)` | `returnOnCapitalAt` | concorrência leva o retorno ao custo; o ano N encontra o estado estacionário `b_N = g∞/r∞` |
| Retenção | `b_t = g_t / ROIC_t`, em [0; 0,95]; zero se `g_t ≤ 0` ou `ROIC_t ≤ 0` | `retentionAt` | `g = b × ROIC` (McKinsey) |
| Meio de ano | `√(1 + r_t)` sobre cada fluxo; `√(1 + r∞)` sobre o terminal | `lift`, `midYearLift` | o caixa chega ao longo do ano (decisão 48) |

`ROIC_base` é o retorno do último exercício × fator de normalização (ou o do
ciclo, quando a base é reconstruída).

---

## 5.2 A projeção

```
lucro_t   = lucro_{t−1} × (1 + g_t)             (lucro_0 = base)
fluxo_t   = lucro_t × (1 − b_t)
fator_t   = Π_{s≤t} (1 + r_s)
VP_t      = fluxo_t × √(1 + r_t) ÷ fator_t
capital_1 = lucro_1 ÷ ROIC_base;   capital_t = capital_{t−1} + b_t × lucro_t
```

O fator **acumula** as taxas de cada ano; não eleva uma taxa só a `t`
(`DcfCalculator._project`).

---

## 5.3 As três formas de valor terminal

| Forma | Quando | Fórmula | Função | Evidência |
|---|---|---|---|---|
| **Retorno neutro** (padrão) | sem vantagem residual | `VT = lucro_{N+1} ÷ r∞` — o crescimento sai da conta (RONIC = r∞) | `terminalValue` | McKinsey, "value driver formula" com RONIC = WACC |
| **Vantagem residual** | veredito concedido | `ROIC∞ = r∞ + φ^N·(ROIC_ciclo − r∞)`; `VT = lucro_{N+1}·(1 − g∞/ROIC∞) ÷ (r∞ − g∞)`, com `r∞ − g∞ ≥ 0,5 p.p.` | `terminalValue`, [growth_guards.dart, `residualMoat`](../../packages/equisim_core/lib/src/services/valuation/growth_guards.dart) | decisão 36; Mauboussin e Johnson (1997) |
| **Concessão com prazo lido** | retorno neutro, contrato que acaba M anos depois do horizonte | `VT = capital_N + EVA_{N+1}·(1 − (1 + r∞)^−M) ÷ r∞`, `EVA_{N+1} = lucro_{N+1} − r∞·capital_N` | `terminalValue` | decisões 50 e 88 |

**O veredito da vantagem residual** barra quando: há contrato com prazo
determinado; falta retorno do ciclo ou custo; o histórico tem menos de 8
exercícios; Φ não foi medido ou passa de 0,60; a persistência não é estimável
(menos de 4 pares de anos); ou o retorno do ciclo não supera o custo de
equilíbrio. `φ` é o coeficiente de um AR(1) do excedente (retorno − custo de
equilíbrio) em anos adjacentes, limitado a [0; 0,90], sem correção de viés de
amostra pequena (medida e descartada na decisão 36). O custo contra o qual o
excedente se mede é o de **equilíbrio**, e o resolvido quando há ponto fixo
(decisões 44 e 51).

**O que o retorno neutro não diz** (item B12, decisão 107): ele fixa o retorno do
capital **novo**. O instalado continua rendendo `lucro_{N+1} ÷ capital_N` para
sempre; a parcela `EVA_{N+1}/r∞` a valor presente é reportada no rastro, e vira
aviso quando passa de 20% do capital próprio (`neutralTerminalExcess`).

---

## 5.4 Via do acionista

`DcfCalculator.shareholder`: a projeção de 5.2 sobre o **lucro por papel**,
descontada ao caminho de Ke; o preço justo é `Σ VP_t + VP(VT)` e já é por papel.
Não há ponte de dívida (a captação já está no lucro). O cenário de desconto
desloca o caminho inteiro de Ke (item B36, corrigido em 28/09/2026: com o Ke
resolvido ano a ano, só a perpetuidade se movia).

---

## 5.5 Via da firma: o fluxo do acionista derivado

Desde a decisão 102, o capital próprio da via da firma **não** é `EV − dívida`:
é o fluxo do acionista derivado do da firma, descontado ao Ke
(`DcfCalculator.equityFromFirm`).

```
FCFF_t = NOPAT_t × (1 − b_t)                             (projeção de 5.2)
S_t    = D^b_{t−1}·Kd_t·(1 − τ) − C_{t−1}·Rf_t·(1 − τ) − D_{t−1}·g_t
FCFE_t = FCFF_t − S_t
VP_t   = FCFE_t × √(1 + Ke_t) ÷ Π(1 + Ke_s)

FCFF_{N+1} = VT_firma^∞ × (r∞ − g∞)       (a perpetuidade da firma, sem o corte do contrato)
FCFE_{N+1} = FCFF_{N+1} − S_{N+1}
VT_acionista = FCFE_{N+1} ÷ (Ke∞ − g∞)
             [contrato: VT∞·(1 − q^M) + (capital_N − D_N)·q^M,  q = (1 + g∞)/(1 + Ke∞)]
VP(VT) = VT_acionista × √(1 + Ke∞) ÷ Π(1 + Ke_s)

capital próprio = Σ VP_t + VP(VT) − minoritários (+ capital posterior)
preço justo     = capital próprio ÷ papéis da ponte
```

- `D^b` = dívida bruta, `C` = caixa, `D = D^b − C`; os três crescem a `g_t`.
- Com o caminho resolvido, `Kd_t = Rf_t + prêmio` e o caixa rende `Rf_t`
  (decisão 127); **sem** resolução e com curva, idem (item B37).
- Minoritários não negativos são subtraídos (decisão 49).
- **Por que não `EV − D`:** com capital próprio fino, a diferença de dois
  números grandes amplifica o erro por `1 ÷ participação` — 138 vezes na RENT3
  (decisões 43 e 102).
- **A identidade:** com alavancagem constante e pesos do próprio modelo,
  `FCFE_{N+1} = E·(Ke − g)`, e o terminal do acionista é o terminal da firma
  menos a dívida; as duas rotas coincidem dentro de 10⁻⁶ com as taxas
  resolvidas (decisão 43, teste em `levered_rates_test.dart`).

**O rastro desta conta** (painel de logs) tem, desde 28/09/2026 (item B35), três
passos: a projeção do fluxo da firma (onde o WACC é só o alvo do retorno), o
fluxo do acionista com o desconto ao Ke de cada ano, e o terminal convertido.
Antes, o rastro montava o fator com o WACC e mostrava ao lado o valor presente
descontado ao Ke — "fluxo ÷ fator" não dava o valor escrito, e a soma mostrada
não era a soma das parcelas.

---

## 5.6 Do capital próprio ao resultado

| Grandeza | Conta | Função |
|---|---|---|
| Preço justo | capital próprio ÷ papéis (via da firma) ou soma por papel (acionista) | `DcfOutcome.fairValuePerShare`, convertido para `Money` uma vez |
| Participação do terminal | `VP(VT) ÷ capital próprio` (pode passar de 100%) | `terminalShare` (decisão 51) |
| Participação do capital próprio | `E ÷ EV` | `equityShare` |
| Upside | `(justo − preço) ÷ preço` | `ValuationResult.upside` |
| Preço com margem | `justo × (1 − margem)`; margem zero por padrão no aplicativo | `ValuationResult` |
| Taxa exibida | a do ano 1 (`discountRateAt(1)`) | `_withScenarios` |

## Limitações deste capítulo

- Alavancagem constante na projeção (dívida cresce com a empresa).
- Convergência linear do retorno e do crescimento, em dez anos, para todas as
  empresas.
- Na perpetuidade neutra, o capital instalado mantém o retorno da projeção para
  sempre (declarado e medido, item B12).
