# 7. O resto do aplicativo

O Equisim tem quatro abas. A de **Valuation** é o motor dos capítulos 1 a 6.
Este capítulo descreve as outras três e as contas que elas fazem, e a tela que
abre a conta do motor para o usuário refazer com os números dele (7.5) e
guardar o resultado (7.6).

| Aba | Tela | O que faz |
|---|---|---|
| **Estudo** | [study_page.dart](../../lib/presentation/study/study_page.dart) | monta as carteiras Principal e Reserva e mostra o potencial de cada ativo |
| **Valuation** | [valuation_page.dart](../../lib/presentation/valuation/valuation_page.dart) | a avaliação de um ativo das carteiras (capítulo 6), e o botão **Editar valuation**, que abre a conta do motor para o usuário refazê-la (7.5) |
| **Meta** | [goal_page.dart](../../lib/presentation/goals/goal_page.dart) | a rentabilidade que um plano patrimonial exige, e a carteira frente a ela |
| **Simulação** | [backtest_page.dart](../../lib/presentation/backtest/backtest_page.dart) | a história das duas carteiras sob o mesmo plano de aportes |

O menu do perfil tem ainda o **painel de logs de cálculo**
([logs_page.dart](../../lib/presentation/audit/logs_page.dart); rota `#/logs`),
com o rastro de cada avaliação ([AUDITORIA_DE_CALCULOS.md](../AUDITORIA_DE_CALCULOS.md)).

---

## 7.1 Estudo: as carteiras

| Regra | Código | Evidência |
|---|---|---|
| **Principal**: a carteira vigente, até 15 ativos, com pesos que somam 100% | [portfolio.dart, `Portfolio.maxAssets`, `Portfolio.equalWeighted`, `Portfolio.hasValidWeights`](../../packages/equisim_core/lib/src/entities/portfolio.dart) | — |
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

---

## 7.5 Editar valuation: o cálculo do usuário

O motor decide cada premissa sozinho. A tela **Editar valuation**
([manual_valuation_page.dart](../../lib/presentation/valuation/manual_valuation_page.dart)),
aberta pelo botão do cartão de preço, deixa o usuário discordar: os campos abrem
com os números do motor para o ativo, e cada troca refaz a conta na hora
(decisão 147).

**A conta é a do motor, e não uma cópia dela.** Ao concluir a via, a cascata
congela o que decidiu — o fluxo-base, as premissas finais, a taxa que descontou
cada ano e a ponte da dívida — em `ValuationResult.manual`. O cálculo do usuário
desconta de novo pela mesma calculadora, trocando só o que ele digitou.

| Regra | Código | Evidência |
|---|---|---|
| A conta congelada: fluxo-base, premissas finais, taxa de cada ano (o `Ke`, nas duas vias) e, na via da firma, a rota da dívida, do caixa e dos minoritários | [manual_valuation.dart, `ManualValuation`](../../packages/equisim_core/lib/src/services/valuation/manual_valuation.dart); [compute_valuation.dart, `_freeze` e `_firmRoute`](../../packages/equisim_core/lib/src/usecases/compute_valuation.dart); [dcf.dart, `FirmDiscountRoute`](../../packages/equisim_core/lib/src/services/valuation/dcf.dart) | decisão 147 |
| **Sem troca, o preço do motor**, bit a bit e ao centavo da tela | `ManualValuation.evaluate` | [manual_valuation_test.dart](../../test/core/manual_valuation_test.dart), sete rotas; [conferir_calculo_manual.dart](../../tool/conferir_calculo_manual.dart), 110 de 110 ativos da entrada congelada em 11/10/2026 |
| Lucro de partida em reais: `NOPAT` na via da firma, lucro líquido na do acionista, que desconta lucro por ação — a tela converte pelas ações da ponte | `ManualValuation.enginePremises` | — |
| **Por que o motor normalizou o lucro de partida, e para que lado**: o cartão do lucro traz a pergunta, o retorno do último exercício contra o típico, os anos do ciclo em barras, o teste que decidiu, a conta e as travas; abre sozinho quando o motor partiu de outro lucro que não o publicado | [normalization_panel.dart](../../lib/presentation/valuation/normalization_panel.dart), sobre `ValuationDiagnostics.baseNormalization` | pedido do orientador, 14/10/2026; capítulo 3, seção 3.2.1 |
| Crescimento do ano 1, que cai em linha reta até a perpetuidade (o motor) ou fica constante nos dez anos | `ManualGrowthPath`; [dcf.dart, `growthPath` e `plannedGrowthAt`](../../packages/equisim_core/lib/src/services/valuation/dcf.dart) | — |
| Taxa de desconto: o caminho do motor deslocado em paralelo — todos os anos e a perpetuidade — ou uma taxa só | `ManualRatePath` | — |
| **A taxa digitada só desconta.** Na via da firma ela entra no custo do capital próprio; o custo médio do capital, para onde o retorno converge e que fixa o reinvestimento da perpetuidade da firma, fica o do motor | `ManualValuation._assumptions` | movê-lo junto fazia o preço **subir** com a taxa em 12 dos 90 ativos da via da firma (decisão 147) |
| Reinvestimento pelo retorno sobre o capital, `b = g ÷ retorno`, com o retorno convergindo à taxa e o crescimento confinado a 95% dele (o motor), ou por parcela fixa do lucro, com o crescimento solto e a perpetuidade de Gordon com a mesma parcela | `ManualReinvestment`; `ReinvestmentPolicy.parcelaFixa` | teste em fórmula fechada |
| Retorno do capital novo na perpetuidade: igual à taxa — `lucro do ano 11 ÷ taxa`, e crescer não cria valor — ou outro, com Gordon e reinvestimento `g ÷ retorno` | `DcfAssumptions.withTerminalReturnOnCapital` | — |
| Recusas com o campo nomeado: lucro não positivo, taxa não positiva, parcela fora de `[0, 100%)`, retorno do capital novo não positivo, perpetuidade de Gordon a menos de 0,5 ponto do crescimento perpétuo | `InvalidInput.field` | — |
| Avisos: o ano em que o crescimento foi confinado, o fluxo negativo, a concessão que deixa de acabar no contrato, o crescimento perpétuo que quase não pesa com o capital novo rendendo a taxa | `ManualNoticeKind`; [manual_copy.dart](../../lib/presentation/valuation/manual_copy.dart) | — |
| "Onde você discorda do motor": do preço do motor ao do usuário, um grupo de premissas de cada vez, em ordem fixa; os degraus somam a diferença inteira | `ManualValuation.attribution` | teste e conferência do universo |
| "O que o preço de hoje supõe": o valor de um campo que iguala o preço justo ao de mercado, com os outros como estão — grade de 400 pontos e bisseção | `ManualValuation.solve` | a taxa achada devolve o preço de mercado a menos de R$ 10⁻¹³ nos 103 ativos com solução |
| O preço do usuário não herda a faixa calibrada nem a habilidade medida, que são do preço do motor | tela, rodapé | decisões 92 e 147 |

## 7.6 O valuation confirmado: gravado e no painel de logs

O botão **Confirmar valuation**, no cartão "Seu preço justo" da edição e na
barra do rodapé no celular, guarda o valuation do usuário (decisão 150). O que
se guarda é o **retrato da conta no momento da confirmação**: as premissas
digitadas, as do motor de que elas partiram, e o resultado inteiro que
`ManualValuation.evaluate` devolveu — sem refazer conta nenhuma ao reler.

| Regra | Código | Evidência |
|---|---|---|
| O registro: identificador, ativo, instante, data da avaliação do motor, via, preço de mercado, preço do motor, ações, premissas do motor e do usuário, o `ManualOutcome` inteiro (ponte, dez anos, terminal, avisos) e a decomposição contra o motor | [manual_valuation_record.dart, `ManualValuationRecord.capture`](../../packages/equisim_core/lib/src/services/valuation/manual_valuation_record.dart) | [manual_valuation_record_test.dart](../../test/core/manual_valuation_record_test.dart): sem troca, o preço do motor bit a bit, nas duas vias |
| Premissa sem conta não vira registro: a falha é a mesma da tela, com o campo nomeado | `ManualValuationRecord.capture` | idem |
| Relido do texto, o registro é o mesmo número a número; documento corrompido é descartado sem derrubar a lista | `toJson`, `fromJson` (formato 1, chaves de enum gravadas como dado) | idem |
| Preço do usuário ao centavo pela regra de `Money.fromReais`; o `double` exato também fica gravado | `ManualValuationRecord.fairValue` | decisão 125 |
| Gravação no Firestore, coleção `valuations`, um documento por registro e nomeado por ele: repetir a gravação não duplica | [manual_valuation_repository.dart](../../lib/data/repositories/manual_valuation_repository.dart); [firestore.rules](../../firestore.rules) | — |
| **No painel de logs, um evento de cálculo** em `/core/valuation/manual/<ATIVO>`, com as premissas, o resultado e seis fórmulas — valor presente dos anos, terminal, patrimônio, preço por ação, potencial e diferença contra o motor —, emitido na confirmação e ao carregar o histórico gravado; o identificador do evento é o do registro, e o painel não o repete | `ManualValuationRecord.toAuditEvent`; [saved_valuations.dart](../../lib/presentation/valuation/saved_valuations.dart); filtro "Valuations confirmados" em [logs_page.dart](../../lib/presentation/audit/logs_page.dart) | [saved_valuations_test.dart](../../test/ui/saved_valuations_test.dart) |
| Gravação recusada vai ao painel como falha, com o motivo, e a tela diz o motivo | `SavedValuationsNotifier.confirm` | idem |
| Na aba Valuation, o cartão "Seus valuations salvos" do ativo, do mais recente ao mais antigo, com as premissas e o resultado do dia, e os botões de reabrir na edição e de apagar | [saved_valuations_card.dart](../../lib/presentation/valuation/saved_valuations_card.dart) | idem |

## Limitações deste capítulo

- A simulação é de preço: quem recebe provento obtém mais.
- Sem rebalanceamento, a carteira simulada pode ficar muito diferente dos pesos
  escolhidos em janelas longas.
- O retorno esperado da carteira não usa o preço justo (nenhuma ordenação foi
  comprovada); é o custo de capital, que o mercado exige em média.
- O cálculo do usuário não é validado: ele é a conta do motor com a opinião de
  quem a digita, e pode chegar a qualquer preço.
- O valuation salvo é o retrato do dia: reabri-lo aplica os números dele à
  conta congelada **de hoje**, que pode ter mudado com dados novos, e por isso
  o preço reaberto pode diferir do gravado.
- O painel de logs só existe com a auditoria ligada (modo de depuração ou
  `--dart-define=EQUISIM_AUDIT=true`); sem ela, o valuation é gravado do mesmo
  jeito e só não vai ao painel.
