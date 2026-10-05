# 7. O resto do aplicativo

O Equisim tem quatro abas. A de **Valuation** é o motor dos capítulos 1 a 6.
Este capítulo descreve as outras três e as contas que elas fazem.

| Aba | Tela | O que faz |
|---|---|---|
| **Estudo** | [study_page.dart](../../lib/presentation/study/study_page.dart) | monta as carteiras Principal e Reserva e mostra o potencial de cada ativo |
| **Valuation** | [valuation_page.dart](../../lib/presentation/valuation/valuation_page.dart) | a avaliação de um ativo das carteiras (capítulo 6) |
| **Meta** | [goal_page.dart](../../lib/presentation/goals/goal_page.dart) | a rentabilidade que um plano patrimonial exige, e a carteira frente a ela |
| **Simulação** | [backtest_page.dart](../../lib/presentation/backtest/backtest_page.dart) | a história das duas carteiras sob o mesmo plano de aportes |

O menu do perfil tem ainda o **painel de logs de cálculo**
([logs_page.dart](../../lib/presentation/audit/logs_page.dart); rota `#/logs`),
com o rastro de cada avaliação ([AUDITORIA_DE_CALCULOS.md](../AUDITORIA_DE_CALCULOS.md)).

---

## 7.1 Estudo: as carteiras

| Regra | Código | Evidência |
|---|---|---|
| **Principal**: a carteira vigente, até 15 ativos, com pesos que somam 100% | [portfolio.dart, `Portfolio.maxAssets`, `Portfolio.weighted`](../../packages/equisim_core/lib/src/entities/portfolio.dart) | — |
| **Reserva**: candidatos a entrar na Principal; na simulação, vira carteira inteira sob os mesmos aportes, para comparação | [backtest_page.dart](../../lib/presentation/backtest/backtest_page.dart) | — |
| Coluna "potencial": o upside do preço justo de cada ativo | `valuationProvider` | — |
| "Esperado da carteira": média, pelos pesos, do retorno esperado de cada ativo com avaliação (7.2) | [expected_return.dart](../../packages/equisim_core/lib/src/services/portfolio/expected_return.dart) | decisões 58 e 103 |
| Concentração setorial declarada | [sector_concentration.dart](../../packages/equisim_core/lib/src/services/portfolio/sector_concentration.dart) | — |
| Estudos salvos no Firestore (Firebase), por usuário | [portfolio_repository.dart](../../lib/data/repositories/portfolio_repository.dart) | — |

---

## 7.2 O retorno esperado de uma ação

| Regra | Código | Evidência |
|---|---|---|
| Retorno esperado de cada ativo = **Ke** (CDI corrente + β × prêmio de mercado) + escore da ordenação comprovada × prêmio de mercado; **na remedição de 02/10/2026 nenhuma ordenação passou** — o book-to-market chega a `t` corrigido de 2,40 contra 2,70, e o potencial do motor a 0,44 —, então é só o Ke. O prêmio é o mesmo do desconto, a média de dez anos do prêmio implícito do pacote | `ExpectedReturn.forPortfolioOrdered`, `marketPremiumReadingProvider` | decisões 103 e 142; [habilidade.json](../../assets/validacao/habilidade.json) |
| Antes a âncora era o CDI, o que tirava o prêmio de risco inteiro de uma carteira de ações | idem | decisão 58 |
| A tela diz que o prêmio do potencial não está comprovado | [skill_copy.dart](../../lib/presentation/goals/skill_copy.dart) | decisão 99 |
| Conversão de upside em taxa anual, `(1 + upside)^(1/3) − 1` (36 meses), só para ferramentas de validação | `annualizedFromUpside` | decisão 26 |

---

## 7.3 Meta: a rentabilidade exigida

| Regra | Código | Fundamento |
|---|---|---|
| Plano: aporte inicial, aporte mensal, valor desejado, prazo | [goal_page.dart](../../lib/presentation/goals/goal_page.dart) | — |
| Taxa mensal que resolve `V_f = V₀(1+i)ⁿ + PMT·((1+i)ⁿ − 1)/i`, por Newton-Raphson com bisseção de resguardo (tolerância 10⁻¹²); anual = `(1 + i)^12 − 1` | [required_return.dart, `RequiredReturnSolver.solve`](../../packages/equisim_core/lib/src/services/goal/required_return.dart) | valor futuro de série uniforme; não há forma fechada |
| Viabilidade: abaixo do CDI de dez anos → a renda fixa basta; até o retorno do Ibovespa de dez anos → plausível; até 2× → exigente; até 2,5× → muito exigente; acima → irrealista | [feasibility.dart, `GoalFeasibility.assess`](../../packages/equisim_core/lib/src/services/goal/feasibility.dart) | limiares relativos ao mercado da década, e não absolutos |
| Carteira frente à meta: esperado da carteira (7.2) menos o exigido = folga | `goal_page.dart` | — |

---

## 7.4 Simulação: a carteira com aportes no passado

| Regra | Código | Evidência |
|---|---|---|
| Janela de 1 a 10 anos contados de hoje para trás (padrão 5); encurtada até o primeiro pregão do ativo mais novo | [backtest_providers.dart](../../lib/presentation/backtest/backtest_providers.dart) | — |
| Aporte inicial e mensais (dia 5; dia inexistente cai no primeiro pregão seguinte, ou no último do mês) | [portfolio_backtest.dart, `ContributionPlan`](../../packages/equisim_core/lib/src/services/backtest/portfolio_backtest.dart) | lente `nucleo`, 21/09/2026 |
| **Sem rebalanceamento**: cada aporte é dividido pelos pesos-alvo, e os pesos derivam com o mercado | `PortfolioBacktest` | decisão 9 |
| Compra **ação inteira**; a sobra fica em caixa por ativo e entra no aporte seguinte | idem | regra do projeto |
| Tarifa da B3 de 0,030% por compra, em inteiros (centavos e partes por milhão) | `TransactionCosts.b3` | decisão 126 |
| Retorno só de **preço**: a simulação não credita provento | idem | decisões 23 e 89 |
| Métricas sobre a série TWR neutralizada de aportes: TWR, XIRR (retorno do investidor), CAGR, volatilidade amostral anualizada, máximo drawdown, Sharpe contra o CDI observado, Sortino (Sortino e Satchell), Calmar | [risk_metrics.dart](../../packages/equisim_core/lib/src/services/metrics/risk_metrics.dart), [returns.dart](../../packages/equisim_core/lib/src/services/metrics/returns.dart) | conferência cruzada em Python |
| Desempenho por ativo apurado com o caixa que sobrou dele | `AssetPerformance` | decisão 65 |
| Exportação em CSV | [csv_export.dart](../../lib/presentation/export/csv_export.dart) | — |

## Limitações deste capítulo

- A simulação é de preço: quem recebe provento obtém mais.
- Sem rebalanceamento, a carteira simulada pode ficar muito diferente dos pesos
  escolhidos em janelas longas.
- O retorno esperado da carteira não usa o preço justo (nenhuma ordenação foi
  comprovada); é o custo de capital, que o mercado exige em média.
