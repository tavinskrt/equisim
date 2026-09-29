# 3. Base e crescimento (Porta 2, saídas 1 e 2)

Como o motor escolhe o lucro de partida e quanto ele cresce. Estudo:
[guia, cap. 4, seções 4.4 a 4.6](../estudo/04-fluxo-de-caixa-descontado.md);
estatística no [cap. 6](../estudo/06-estatistica.md). Casos: normalização em
[VALE3](../estudo/casos/vale3.md) e [ITUB4](../estudo/casos/itub4.md); tendência
que mantém a base em [WEGE3](../estudo/casos/wege3.md).

Parâmetros em [growth_guards.dart, `ValuationParameters`](../../packages/equisim_core/lib/src/services/valuation/growth_guards.dart);
série em [capital_base.dart](../../packages/equisim_core/lib/src/services/valuation/capital_base.dart);
orquestração em [compute_valuation.dart, `_saida1`, `_fluxoBase`, `_saida2`](../../packages/equisim_core/lib/src/usecases/compute_valuation.dart).

---

## 3.1 A série de capital

| Regra | Código | Fundamento / evidência |
|---|---|---|
| Via da firma: base = capital investido, lucro = NOPAT na alíquota estrutural. Via do acionista: base = patrimônio, lucro = lucro líquido | `CapitalSeries.build` | McKinsey: ROIC e crescimento do capital investido; Damodaran: ROE para financeiras |
| Alíquota estrutural = mediana das alíquotas efetivas (≥ 5 exercícios), limitada a [0; 34%]; sem isso, o NOPAT publicado (34%) | `CapitalSeries.structuralTaxRate` | JCP, incentivo e presunção são regime, e regime é o que se projeta (decisão 37); mediana porque um ano atípico não arrasta |
| Limpeza: descarta ponto com base fora de [1/8; 8]× a mediana de até dois vizinhos de cada lado | `_cleanByNeighbour` | falha de escala da fonte; a referência local evita julgar o bom contra o ruim |
| Retorno do ano = lucro do ano ÷ base de **abertura** (ano anterior); prejuízo entra com sinal | `CapitalSeries` | o lucro é gerado pelo capital que existia no começo do ano |
| Retorno do ciclo = mediana dos retornos dos 8 exercícios anteriores ao corrente (≥ 4) | `cycleReturn`, `cycleWindow = 8` | um ciclo de commodity ou de crédito cabe em oito anos; mediana resiste a extremos |
| Série com menos de 4 pontos: a via não se aplica | `isTooShort` | — |

---

## 3.2 Saída 1 — as três guardas e a normalização

| Guarda | Regra | Parâmetros | Evidência |
|---|---|---|---|
| **1 — tendência** | regressão do retorno contra o ano na série completa (≥ 6), `t` com erro de Newey-West, crítico de Student a α = 10%; a tendência **domina** se é significante e se a deriva em 8 anos (`|inclinação| × 8`) é pelo menos igual à correção (`|atual − ciclo|`) | `alpha = 0,10`, `minTrendDominance = 1,0`, `trendDriftWindow = 8` | decisões 25, 27 e 28 |
| **2 — capital externo (Φ)** | soma, na janela de 8 anos, de `max(0, Δbase − lucro)` ÷ base inicial: capital que não veio de lucro retido | `maxExternalCapital = 1,0` (declara, **não** bloqueia) | decisão 28 |
| **3 — desvio do ciclo** | destoa se `|atual − ciclo|` > 1,5 MAD escalado, **ou** se atual ÷ ciclo sai de [0,75; 1,33] | `robustZ = 1,5` | decisões 25 e 27 |

**Normaliza** se a guarda 3 disser que destoa, a tendência não dominar (ou o
setor tiver precedência do ciclo) e o retorno atual for positivo:

```
fator = clamp(retorno do ciclo ÷ retorno atual, 0,33, 3,00)
base  = lucro do exercício × fator
```

| Regra especial | Código | Evidência |
|---|---|---|
| **Precedência do ciclo** em commodity e cíclico pesado (setor "materiais básicos" ou subsetor de petróleo, refino, mineração, siderurgia, papel e celulose, petroquímicos): normaliza mesmo com tendência significante | [cyclical_sectors.dart](../../packages/equisim_core/lib/src/services/valuation/cyclical_sectors.dart), `CyclicalSectors.hasCyclePrecedence` | decisão 28: a perna de alta do ciclo tem forma de tendência |
| **Trava de saúde**: se o pior entre lucro líquido e EBITDA caiu mais de 50% em três anos, o fator não passa de 1,00 (não normaliza para cima) | `recentOperationalDecline`, `maxOperationalDecline = 0,50`, `operationalHealthWindow = 3` | decisões 28 e 29 (caso QUAL3: +477% vinha da base normalizada) |
| **Commodity é isenta da trava** (só na base) | `_saida1` | decisão 30 |
| A vantagem competitiva residual **não** tem trava de saúde | `GrowthGuards.residualMoat` | decisão 36 tirou os cortes de nível; texto corrigido em 28/09/2026 (item B39) |
| **Base reconstruída**: retorno atual ≤ 0, ciclo > 0, sem trava e fluxo positivo em ≥ 60% da janela → base = retorno do ciclo × capital de hoje | `_fluxoBase` | decisão 53: o vale do ciclo não descarta a empresa; vira ressalva |
| Base ≤ 0 depois de tudo: a via não se aplica | `_fluxoBase` | — |

A base da via do acionista é por papel: lucro líquido ÷ papéis da ponte × fator
(recuo: lucro por ação publicado × razão da unit) (`_earningsPerQuotedUnit`).

---

## 3.3 Saída 2 — crescimento

| Regra | Código | Fundamento | Evidência |
|---|---|---|---|
| `g` = **mediana** das variações anuais da base (≥ 4 variações consecutivas) | `GrowthGuards.dispersion` | `g = b × ROIC` (McKinsey): a base de capital é o que o reinvestimento acumula | decisão 25 |
| Conferência: crescimento de uma regressão de `ln(base)` contra o ano, `e^b − 1`, erro pelo método delta `(1 + g) × erro(b)` | idem | Wooldridge; método delta | [crescimento_log_linear.md](../validacao/crescimento_log_linear.md) |
| **Não identificado** se o erro passa de 3 p.p., **ou** se `|mediana − regressão| ÷ erro` passa do crítico de Student **e** a diferença passa de `max(2 p.p.; 25% × |mediana|)` | `maxGrowthStdError = 0,03`, `dispersionFloor = 0,02`, `dispersionRelative = 0,25` | a série não diz um crescimento só | decisão 27 |
| Não identificado, mas a inflação é **financiável** (retenção exigida `inflação ÷ ROIC do ciclo` < 1 e ≤ retenção mediana observada) → `g` = inflação, com ressalva | `anchorIsFundable` | crescer com a inflação é o mínimo de uma empresa em continuidade | — |
| Nem isso → `g` = 0, com ressalva e aviso | `_saida2` | direção conservadora, declarada | — |
| Crescimento de cada ano limitado ao que o retorno financia: `g_t ≤ 0,95 × ROIC_t` | [dcf.dart, `sustainable`](../../packages/equisim_core/lib/src/services/valuation/dcf.dart) | reter 100% para sempre não é plano | decisão 47 |

---

## 3.4 Crescimento perpétuo

| Regra | Código | Evidência |
|---|---|---|
| `g∞ = min(g, teto nominal)`, limitado a **[−5%; teto]** | [growth_estimator.dart, `GrowthEstimator.perpetual`](../../packages/equisim_core/lib/src/services/valuation/growth_estimator.dart) | decisão 56 (piso de −5%); o rastro dizia [0; teto] até 28/09/2026 |
| Teto = crescimento nominal da economia, `(1 + real) × (1 + inflação) − 1` | `MarketAnchors` | nominal porque a taxa de desconto é nominal |
| O crescimento de cada ano decai em linha reta de `g` a `g∞` ao longo dos dez anos | `DcfAssumptions.growthAt` | vantagem se desgasta com a concorrência, não acaba numa data (substituiu a queda em degrau) |

## Limitações deste capítulo

- A lista de setores cíclicos é mantida à mão, e decide duas regras
  (precedência e isenção).
- A normalização supõe que o retorno volta à mediana de oito anos; não prevê
  preço de commodity nem mudança estrutural sem tendência estatística.
- O crescimento vem só da história; aquisições aparecem como capital externo
  declarado, e não são modeladas.
