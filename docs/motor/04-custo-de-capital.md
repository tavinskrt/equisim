# 4. Custo de capital

A taxa que desconta cada ano. Estudo: [guia, cap. 3](../estudo/03-risco-e-retorno.md).
Casos: WACC com caixa líquido na [WEGE3](../estudo/casos/wege3.md), passo 7;
banco sem realavancagem no [ITUB4](../estudo/casos/itub4.md), passo 3;
estrutura recusada na [RENT3](../estudo/casos/rent3.md).

---

## 4.1 CAPM e prêmio de mercado

| Regra | Código | Fundamento | Evidência |
|---|---|---|---|
| `Ke = Rf + β × prêmio` | [cost_of_capital.dart, `CapmInputs.costOfEquity`](../../packages/equisim_core/lib/src/services/valuation/cost_of_capital.dart) | Sharpe (1964), Lintner (1965) | — |
| Prêmio de mercado **5,5%**, fixo | `CapmInputs`, `MarketPremiumSource` | histórico e implícito foram tentados: o histórico tem erro de 7,85 p.p. e o encolhimento devolve 5,49%; o implícito sai −3,9% | decisão 116, [premio_de_mercado.md](../validacao/premio_de_mercado.md) |
| O Ke "do dia" (CDI corrente) serve ao WACC estático e à tela de metas; o de cada ano da projeção usa o forward daquele ano | `_premissas`, `_auditCapm` | a curva dá a taxa que o mercado atribui a cada prazo | decisões 74 e 103; rastro explica desde 28/09/2026 |

---

## 4.2 Beta encolhido e desalavancado

| Regra | Código | Fundamento | Evidência |
|---|---|---|---|
| Peso da medida `w = (1/SE²) ÷ (1/SE² + 1/σ²)`; `β = w·β_medido + (1 − w)·β_prior` | [beta_shrinkage.dart, `BetaShrinkage.shrink`](../../packages/equisim_core/lib/src/services/metrics/beta_shrinkage.dart) | encolhimento bayesiano (Vasicek, 1973) | decisão 40; peso mediano 0,98 |
| `β_prior` = beta desalavancado mediano do setor (recuo: universo), realavancado pela estrutura do ativo; `σ` = dispersão robusta dos betas do universo (0,53) | [resolve_beta_prior.dart](../../packages/equisim_core/lib/src/usecases/resolve_beta_prior.dart), [assets/mercado/beta_prior.json](../../assets/mercado/) | "bottom-up beta" (Damodaran) | [beta_setorial.md](../validacao/beta_setorial.md) |
| Hamada: `fator = 1 + (1 − 34%) × D/E`, com D/E limitado a [0; 3]; `β_U = β_L ÷ fator` | `BetaShrinkage.leverageFactor` | Hamada (1972) | decisões 54 e 55 (D/E da janela do beta) |
| Financeiras não se desalavancam nem realavancam | `_resolverCusto` | a alavancagem do banco é permanente e regulada, e o beta medido a contém | decisão 46 |

---

## 4.3 Custo da dívida e escudo fiscal

| Regra | Código | Evidência |
|---|---|---|
| `Kd = Rf + prêmio sintético`; o observado (despesa ÷ dívida) **não** entra na taxa | `CostOfCapital.effectiveCostOfDebt` | decisão 31: o observado caía fora da banda defensável em 70 de 120 avaliados e carrega arrendamento e câmbio |
| Prêmio pela alavancagem (dívida líquida ÷ EBITDA): ≤ 0 → 1,0%; ≤ 1 → 1,3%; ≤ 2 → 1,8%; ≤ 2,5 → 2,4%; ≤ 3 → 3,1%; ≤ 3,5 → 4,0%; ≤ 4 → 5,5%; ≤ 5 → 7,5%; acima, ou EBITDA ≤ 0 → 10% | `CostOfCapital.leverageSpread` | tabela no estilo das agências (Damodaran, "synthetic rating") |
| Prêmio pela cobertura (EBIT ÷ despesa): ≥ 8,5 → 1,0% … < 0,8 → 10%; **só fala** quando despesa ÷ dívida bruta cai em [Rf; Rf + 10 p.p.], e aí vale o maior dos dois | `coverageSpread`, `syntheticSpread` | decisão 130 |
| Sem dívida contratada: `Kd = Rf` | `effectiveCostOfDebt` | — |
| Aviso quando o Kd adotado se afasta mais de 1 p.p. do observado, com a regra aplicada | `costOfDebtWasClamped`, `_avisoDoCustoDaDivida` | item B32 |
| Escudo fiscal: 34% (estatutária), reduzido proporcionalmente quando a cobertura é menor que 1 | `effectiveTaxShield` | decisão 37: a dedução vale na margem, que é a alíquota cheia no Lucro Real |

---

## 4.4 WACC

```
WACC = (E ÷ V)·Ke + (D_bruta ÷ V)·Kd·(1 − escudo) − (C ÷ V)·Rf·(1 − 34%)
V = E + D_líquida;   E = papéis da ponte × preço
```

| Regra | Código | Evidência |
|---|---|---|
| Pesos sobre a dívida **líquida**, a mesma do resto do modelo | `ValuationCascade._wacc`, `CostOfCapital.rawWacc` | decisão 104 |
| O caixa rende a taxa livre de risco, tributada, e não o custo de empréstimo | idem | decisão 113 |
| E = divisor da ponte × preço, e não o valor de mercado da fonte | `_wacc` | decisão 83 |
| Caixa líquido: peso de dívida negativo, WACC acima do Ke, com aviso | `_wacc` | — |
| Piso: WACC ≥ Rf, com aviso | `_wacc` | — |
| Sem valor de mercado: desconto = Ke | `_wacc` | — |

---

## 4.5 A taxa de cada ano

| Situação | Taxa do ano t | Código | Evidência |
|---|---|---|---|
| Com beta desalavancado e não financeira: **resolvida** (4.6) | WACC_t e Ke_t do ponto fixo, sobre o forward do ano | `_resolverCusto`, [levered_rates.dart](../../packages/equisim_core/lib/src/services/valuation/levered_rates.dart) | decisões 41, 42, 46, 105 |
| Banco, ou sem beta desalavancado, **com curva** | o custo de hoje (beta, prêmio, estrutura de hoje) remontado sobre o forward do ano | `_premissas` (`caminhoPelaCurva`), `_descontarDoBalanco` | **item B37, corrigido em 28/09/2026**: antes interpolava em linha reta do CDI de hoje à perpetuidade |
| Sem curva | linha reta do custo sobre o CDI corrente ao custo sobre o CDI de dez anos | `DcfAssumptions.discountRateAt` | recuo |
| Perpetuidade | custo sobre o forward depois do ano N (ou o CDI de dez anos, sem curva), com a estrutura do ano N quando resolvida | `terminalCapm`, `_wacc(terminal: true)` | decisão 105 |

Efeito do B37 medido no gabarito: os 19 financeiros do aplicativo mudaram de
−0,4% a −0,5%; nenhuma via da firma mudou (ela já era resolvida).

---

## 4.6 O ponto fixo

O peso do capital próprio depende do valor do capital próprio, que é o que se
calcula; e a dívida projetada muda o beta ano a ano. O motor resolve as duas
circularidades juntas.

| Regra | Código |
|---|---|
| Dívida e caixa crescem a `g_t` (alavancagem constante na projeção) | `LeveredCostOfCapital.solve` |
| Valor da firma por acumulação regressiva: `V_{t−1} = (FCFF_t × √(1+WACC_t) + V_t) ÷ (1 + WACC_t)`, terminal levantado por meio ano | idem |
| `E_t = V_t − D_t`; `β_L,t = β_U × (1 + 0,66 × D_{t−1}/E_{t−1})`; `Ke_t = Rf_t + β_L,t × 5,5%`; `Kd_t = Rf_t + prêmio`; WACC_t com os pesos do início do ano | idem |
| Amortecimento de 0,5 no capital próprio, tolerância de 10⁻¹⁰ na variação relativa de E₀, até 100 iterações | idem |
| Duas partidas: o caminho sem realavancagem e o custo desalavancado `Rf_t + β_U × prêmio`; se as duas convergem e divergem mais de 0,1%, aviso; se só uma converge, vale ela, com aviso; se nenhuma, recusa "do método, e não do chute" | `LeveredCostOfCapital.solve` (decisão 110) |
| Capital próprio ≤ 0 em algum ano, ou valor da firma ≤ 0: **estrutura de capital recusada**, e o ativo é recusado (não muda de via) | decisões 45 e 102 |
| Via do acionista não financeira: mesma ideia pelo lado do acionista, `E_t = (LPA_t + E_{t+1}) ÷ (1 + Ke_t)` | `solveEquity` (decisão 46) |
| O veredito da vantagem competitiva é refeito contra a taxa de equilíbrio resolvida, até estabilizar (no máximo 10 passes) | [moat_fixed_point.dart](../../packages/equisim_core/lib/src/services/valuation/moat_fixed_point.dart) (decisões 44 e 51) |

A identidade entre a rota da firma e a do acionista (capítulo 5, seção 5.5) só é
exata com as taxas resolvidas; ela está travada por teste (decisão 43,
[identidade_das_vias.md](../validacao/identidade_das_vias.md)).

## Limitações deste capítulo

- Prêmio de mercado único e fixo no tempo; abaixo do prêmio total que Damodaran
  publica para o Brasil.
- Custo da dívida sintético, não de crédito observado.
- Hamada com D/E limitado a 3, e escudo a 34% (bancos pagam 45%, mas não passam
  por aqui).
- O cenário de desconto move o Ke e a perpetuidade, mas não o alvo do retorno
  sobre o capital nem o Kd (decisão 121; item B38).
