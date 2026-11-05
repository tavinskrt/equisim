# 7. O resto do aplicativo

O Equisim é um aplicativo web (decisão 152) com quatro áreas e a página de cada
ativo. O **Raio-X** de um ativo é o motor dos capítulos 1 a 6: tem página
própria, `/ativo/<ATIVO>` (decisão 155), aberta pela busca (Ctrl/⌘ + K) ou pelo
ativo de uma carteira, e o Voltar dela devolve à área de onde veio. Este
capítulo descreve as áreas e as contas que elas fazem, e a tela que abre a
conta do motor para o usuário refazer com os números dele (7.5), guardar o
resultado (7.6) e acompanhar a carteira realizada contra a meta (7.7).

| Área | Tela | O que faz |
|---|---|---|
| **Estudo** | [builder-page.tsx](../../src/features/study/builder-page.tsx) | monta as carteiras Principal e Reserva e mostra o potencial de cada ativo |
| **Raio-X** (`/ativo/<ATIVO>`) | [asset-page.tsx](../../src/features/asset/asset-page.tsx); [asset-xray.tsx](../../src/features/asset/asset-xray.tsx) | a avaliação de um ativo (capítulo 6), em dois modos — **Essencial**, a leitura e a régua de preço, e **Completo**, com o modelo, a taxa, a normalização, a sensibilidade e a projeção —, e o botão **Simular minhas premissas**, que abre a conta do motor para o usuário refazê-la (7.5); no computador, um índice lateral leva a cada seção. O endereço antigo, `?ativo=<ATIVO>` sobre qualquer área, redireciona para a página |
| **Meta** | [planner-page.tsx](../../src/features/goal/planner-page.tsx) | a rentabilidade que um plano patrimonial exige, e a carteira frente a ela; a curva de acumulação ([accumulation-chart.tsx](../../src/features/goal/accumulation-chart.tsx)) é o piloto dos gráficos da Bklit UI (decisão 156); o **acompanhamento da carteira** ([tracking-panel.tsx](../../src/features/goal/tracking-panel.tsx)) mostra o que a carteira fez desde a data de início, comprando a cada aporte o maior potencial (7.7; decisão 159) |
| **Backtest** | [backtest-page.tsx](../../src/features/backtest/backtest-page.tsx) | a história das duas carteiras sob o mesmo plano de aportes; a evolução comparada ([evolution-chart.tsx](../../src/features/backtest/evolution-chart.tsx)) é desenhada pelo gráfico de linha da Bklit UI, e o risco × retorno segue no Recharts (decisão 158) |
| **Meus valuations** | [valuations-page.tsx](../../src/features/valuations/valuations-page.tsx) | os valuations que o usuário confirmou, de todos os ativos (7.6) |

Onde aparece um ticker — Estudo, seletor, busca, Raio-X, Backtest, Meus
valuations e Simular —, ele vem com a logo da empresa, carregada da brapi pelo
navegador, e as duas primeiras letras da raiz no lugar dela quando a imagem não
vem ([ticker-logo.tsx](../../src/ui/ticker-logo.tsx); decisão 154). A logo não
entra em conta nenhuma.

A interface se move pouco e com motivo (decisão 155): a área entra com um
esmaecer curto e os cartões do Raio-X entram em cascata, as duas coisas em
animação CSS, para o conteúdo nunca depender de JavaScript para aparecer; os
números da leitura contam até o valor e a escolha do Essencial/Completo
desliza, pelo Motion ([motion.tsx](../../src/ui/motion.tsx)). Com a
preferência de movimento reduzido do sistema, tudo isso para, e nenhum número
muda com o movimento: a contagem é só visual, e o leitor de tela lê o valor
final.

O menu da conta tem ainda o **painel de logs de cálculo**
([logs-app.tsx](../../src/features/logs/logs-app.tsx); rota `/logs`, em
janela própria), com o rastro de cada avaliação
([AUDITORIA_DE_CALCULOS.md](../AUDITORIA_DE_CALCULOS.md)).

---

## 7.1 Estudo: as carteiras

| Regra | Código | Evidência |
|---|---|---|
| **Principal**: a carteira vigente, até 15 ativos, **equiponderada**: incluir e tirar ativo reequipondera, a interface não escolhe peso, e um estudo gravado com outros pesos abre equiponderado | [portfolio.ts, `Portfolio.maxAssets`, `Portfolio.add`, `Portfolio.remove`](../../src/core/entities/portfolio.ts); [study-store.ts, `withEqualWeights`](../../src/app/state/study-store.ts) | decisão 160; [study-store.test.ts](../../test/app/study-store.test.ts) |
| **Reserva**: candidatos a entrar na Principal; na simulação, vira carteira inteira sob os mesmos aportes, para comparação | [backtest-page.tsx](../../src/features/backtest/backtest-page.tsx) | — |
| Coluna "potencial": o upside do preço justo de cada ativo | [hooks.ts, `useValuation`](../../src/app/hooks.ts); [potential-cell.tsx](../../src/features/study/potential-cell.tsx) | — |
| **Com valuation do usuário que discorda do motor, a coluna é a dele**: o mais recente confirmado para o ativo, com algum campo trocado, dá o preço justo — marcado "seu" — e o potencial contra a cotação de hoje; confirmar os números do motor tal como estão devolve o ativo ao preço do motor. Vale na Principal e na Reserva, em qualquer estudo, porque o valuation é do usuário | [saved-valuations-store.ts, `userValuationOf`](../../src/app/state/saved-valuations-store.ts); [portfolio-column.tsx, `AssetRow`](../../src/features/study/portfolio-column.tsx); [potential-cell.tsx](../../src/features/study/potential-cell.tsx) | decisão 151; [saved-valuations.test.ts](../../test/app/saved-valuations.test.ts) |
| Setores da Principal: a rosca e a tabela, com o nome do setor quebrando a linha em vez de alargar o cartão | [sector-donut.tsx](../../src/features/study/sector-donut.tsx) | decisão 160 |
| Fora da tela desde a decisão 160: o "Esperado da carteira" (média, pelos pesos, do retorno esperado de cada ativo, 7.2) e o aviso de concentração setorial. Os cálculos seguem no núcleo | [expected-return.ts](../../src/core/services/portfolio/expected-return.ts); [sector-concentration.ts](../../src/core/services/portfolio/sector-concentration.ts) | decisões 58, 103 e 160 |
| Estudos salvos no Firestore (Firebase), por usuário | [portfolio-store.ts](../../src/data/persistence/portfolio-store.ts) | — |

---

## 7.2 O retorno esperado de uma ação

Desde a decisão 160, nenhuma tela mostra o retorno esperado da carteira; o
estimador abaixo segue no núcleo.

| Regra | Código | Evidência |
|---|---|---|
| Retorno esperado de cada ativo = **Ke** (CDI corrente + β × prêmio de mercado) + escore da ordenação comprovada × prêmio de mercado; **na remedição de 02/10/2026 nenhuma ordenação passou** — o book-to-market chega a `t` corrigido de 2,40 contra 2,70, e o potencial do motor a 0,44 —, então é só o Ke. O prêmio é o mesmo do desconto, a média de dez anos do prêmio implícito do pacote | `ExpectedReturn.forPortfolioOrdered`; [hooks.ts, `usePremium`](../../src/app/hooks.ts) | decisões 103 e 142; [habilidade.json](../../public/assets/validacao/habilidade.json) |
| Antes a âncora era o CDI, o que tirava o prêmio de risco inteiro de uma carteira de ações | idem | decisão 58 |
| A tela diz que o prêmio do potencial não está comprovado | [skill-copy.ts](../../src/copy/skill-copy.ts) | decisão 99 |
| Conversão de upside em taxa anual, `(1 + upside)^(1/3) − 1` (36 meses), só para ferramentas de validação | `annualizedFromUpside` | decisão 26 |

---

## 7.3 Meta: a rentabilidade exigida

| Regra | Código | Fundamento |
|---|---|---|
| Plano: aporte inicial, aporte mensal, valor desejado, prazo | [planner-page.tsx](../../src/features/goal/planner-page.tsx) | — |
| Taxa mensal que resolve `V_f = V₀(1+i)ⁿ + PMT·((1+i)ⁿ − 1)/i`, por Newton-Raphson com bisseção de resguardo (tolerância 10⁻¹²); anual = `(1 + i)^12 − 1` | [required-return.ts, `RequiredReturnSolver.solve`](../../src/core/services/goal/required-return.ts) | valor futuro de série uniforme; não há forma fechada |
| Viabilidade: abaixo do CDI de dez anos → a renda fixa basta; até o retorno do Ibovespa de dez anos → plausível; até 2× → exigente; até 2,5× → muito exigente; acima → irrealista | [feasibility.ts, `GoalFeasibility.assess`](../../src/core/services/goal/feasibility.ts) | limiares relativos ao mercado da década, e não absolutos |
| A carteira se confronta com a meta pelo que fez, no acompanhamento (7.7). O cartão "Carteira frente à meta" (esperado menos exigido) e a curva do esperado saíram com a decisão 160 | `planner-page.tsx` | decisão 160 |

---

## 7.4 Simulação: a carteira com aportes no passado

| Regra | Código | Evidência |
|---|---|---|
| Janela de 1 a 10 anos contados de hoje para trás (padrão 5); encurtada até o primeiro pregão do ativo mais novo | [backtest.ts](../../src/app/backtest.ts) | — |
| Aporte inicial e mensais (dia 5; dia inexistente cai no primeiro pregão seguinte, ou no último do mês) | [portfolio-backtest.ts, `ContributionPlan`](../../src/core/services/backtest/portfolio-backtest.ts) | lente `nucleo`, 21/09/2026 |
| **Sem rebalanceamento**: cada aporte é dividido pelos pesos-alvo, e os pesos derivam com o mercado | `PortfolioBacktest` | decisão 9 |
| Compra **ação inteira**; a sobra fica em caixa por ativo e entra no aporte seguinte | idem | regra do projeto |
| Tarifa da B3 de 0,030% por compra, em inteiros (centavos e partes por milhão) | `TransactionCosts.b3` | decisão 126 |
| Retorno só de **preço**: a simulação não credita provento | idem | decisões 23 e 89 |
| Métricas sobre a série TWR neutralizada de aportes: TWR, XIRR (retorno do investidor), CAGR, volatilidade amostral anualizada, máximo drawdown, Sharpe contra o CDI observado, Sortino (Sortino e Satchell), Calmar | [risk-metrics.ts](../../src/core/services/metrics/risk-metrics.ts), [returns.ts](../../src/core/services/metrics/returns.ts) | conferência cruzada em Python |
| Desempenho por ativo apurado com o caixa que sobrou dele | `AssetPerformance` | decisão 65 |
| Exportação em CSV | [csv-export.ts](../../src/app/csv-export.ts) | — |

---

## 7.5 Simular minhas premissas: o cálculo do usuário

O motor decide cada premissa sozinho. A tela **Simular minhas premissas**
([manual-page.tsx](../../src/features/manual/manual-page.tsx); rota
`/ativo/<ATIVO>/simular`), aberta pelo botão do Raio-X, deixa o usuário
discordar: os campos abrem
com os números do motor para o ativo, e cada troca refaz a conta na hora
(decisão 147).

**A conta é a do motor, e não uma cópia dela.** Ao concluir a via, a cascata
congela o que decidiu — o fluxo-base, as premissas finais, a taxa que descontou
cada ano e a ponte da dívida — em `ValuationResult.manual`. O cálculo do usuário
desconta de novo pela mesma calculadora, trocando só o que ele digitou.

| Regra | Código | Evidência |
|---|---|---|
| A conta congelada: fluxo-base, premissas finais, taxa de cada ano (o `Ke`, nas duas vias) e, na via da firma, a rota da dívida, do caixa e dos minoritários | [manual-valuation.ts, `ManualValuation`](../../src/core/services/valuation/manual-valuation.ts); [compute-valuation.ts, `freeze` e `firmRoute`](../../src/core/usecases/compute-valuation.ts); [dcf.ts, `FirmDiscountRoute`](../../src/core/services/valuation/dcf.ts) | decisão 147 |
| **Sem troca, o preço do motor**, bit a bit e ao centavo da tela | `ManualValuation.evaluate` | [manual-valuation.test.ts](../../test/core/manual-valuation.test.ts), sete rotas; [manual-calculation-check.ts](../../tool/manual-calculation-check.ts), 110 de 110 ativos da entrada congelada em 11/10/2026 e 121 de 121 em 03/11/2026 |
| Lucro de partida em reais: `NOPAT` na via da firma, lucro líquido na do acionista, que desconta lucro por ação — a tela converte pelas ações da ponte | `ManualValuation.enginePremises` | — |
| **Por que o motor normalizou o lucro de partida, e para que lado**: o cartão do lucro traz a pergunta, o retorno do último exercício contra o típico, os anos do ciclo em barras, o teste que decidiu, a conta e as travas; abre sozinho quando o motor partiu de outro lucro que não o publicado | [normalization-panel.tsx](../../src/features/asset/normalization-panel.tsx), sobre `ValuationDiagnostics.baseNormalization` | pedido do orientador, 14/10/2026; capítulo 3, seção 3.2.1 |
| Crescimento do ano 1, que cai em linha reta até a perpetuidade (o motor) ou fica constante nos dez anos | `ManualGrowthPath`; [dcf.ts, `growthPath` e `plannedGrowthAt`](../../src/core/services/valuation/dcf.ts) | — |
| Taxa de desconto: o caminho do motor deslocado em paralelo — todos os anos e a perpetuidade — ou uma taxa só | `ManualRatePath` | — |
| **A taxa digitada só desconta.** Na via da firma ela entra no custo do capital próprio; o custo médio do capital, para onde o retorno converge e que fixa o reinvestimento da perpetuidade da firma, fica o do motor | `ManualValuation.assumptions` | movê-lo junto fazia o preço **subir** com a taxa em 12 dos 90 ativos da via da firma (decisão 147) |
| Reinvestimento pelo retorno sobre o capital, `b = g ÷ retorno`, com o retorno convergindo à taxa e o crescimento confinado a 95% dele (o motor), ou por parcela fixa do lucro, com o crescimento solto e a perpetuidade de Gordon com a mesma parcela | `ManualReinvestment`; `ReinvestmentPolicy.parcelaFixa` | teste em fórmula fechada |
| Retorno do capital novo na perpetuidade: igual à taxa — `lucro do ano 11 ÷ taxa`, e crescer não cria valor — ou outro, com Gordon e reinvestimento `g ÷ retorno` | `DcfAssumptions.withTerminalReturnOnCapital` | — |
| Recusas com o campo nomeado: lucro não positivo, taxa não positiva, parcela fora de `[0, 100%)`, retorno do capital novo não positivo, perpetuidade de Gordon a menos de 0,5 ponto do crescimento perpétuo | `InvalidInput.field` | — |
| Avisos: o ano em que o crescimento foi confinado, o fluxo negativo, a concessão que deixa de acabar no contrato, o crescimento perpétuo que quase não pesa com o capital novo rendendo a taxa | `ManualNoticeKind`; [manual-copy.ts](../../src/copy/manual-copy.ts) | — |
| "Onde você discorda do motor": do preço do motor ao do usuário, um grupo de premissas de cada vez, em ordem fixa; os degraus somam a diferença inteira | `ManualValuation.attribution` | teste e conferência do universo |
| "O que o preço de hoje supõe": o valor de um campo que iguala o preço justo ao de mercado, com os outros como estão — grade de 400 pontos e bisseção | `ManualValuation.solve` | a taxa achada devolve o preço de mercado a menos de R$ 10⁻¹³ nos 103 ativos com solução |
| O preço do usuário não herda a faixa calibrada nem a habilidade medida, que são do preço do motor | tela, rodapé | decisões 92 e 147 |

## 7.6 O valuation confirmado: gravado e no painel de logs

O botão **Confirmar valuation**, no cartão "Seu preço justo" da simulação e
na barra do rodapé no celular, guarda o valuation do usuário (decisão 150). O que
se guarda é o **retrato da conta no momento da confirmação**: as premissas
digitadas, as do motor de que elas partiram, e o resultado inteiro que
`ManualValuation.evaluate` devolveu — sem refazer conta nenhuma ao reler.

| Regra | Código | Evidência |
|---|---|---|
| O registro: identificador, ativo, instante, data da avaliação do motor, via, preço de mercado, preço do motor, ações, premissas do motor e do usuário, o `ManualOutcome` inteiro (ponte, dez anos, terminal, avisos) e a decomposição contra o motor | [manual-valuation-record.ts, `ManualValuationRecord.capture`](../../src/core/services/valuation/manual-valuation-record.ts) | [manual-valuation-record.test.ts](../../test/core/manual-valuation-record.test.ts): sem troca, o preço do motor bit a bit, nas duas vias |
| Premissa sem conta não vira registro: a falha é a mesma da tela, com o campo nomeado | `ManualValuationRecord.capture` | idem |
| Relido do texto, o registro é o mesmo número a número; documento corrompido é descartado sem derrubar a lista | `toJson`, `fromJson` (formato 1, chaves de enum gravadas como dado) | idem |
| Preço do usuário ao centavo pela regra de `Money.fromReais`; o número exato, em ponto flutuante, também fica gravado | `ManualValuationRecord.fairValue` | decisão 125 |
| Gravação no Firestore, coleção `valuations`, um documento por registro e nomeado por ele: repetir a gravação não duplica; no modo local, sem Firebase, a mesma gravação vai ao IndexedDB do navegador | [manual-valuation-store.ts](../../src/data/persistence/manual-valuation-store.ts); [firestore.rules](../../firestore.rules) | — |
| **No painel de logs, um evento de cálculo** em `/core/valuation/manual/<ATIVO>`, com as premissas, o resultado e seis fórmulas — valor presente dos anos, terminal, patrimônio, preço por ação, potencial e diferença contra o motor —, emitido na confirmação e ao carregar o histórico gravado; o identificador do evento é o do registro, e o painel não o repete | `ManualValuationRecord.toAuditEvent`; [saved-valuations-store.ts](../../src/app/state/saved-valuations-store.ts); filtro "Valuations confirmados" em [logs-app.tsx](../../src/features/logs/logs-app.tsx) | [saved-valuations.test.ts](../../test/app/saved-valuations.test.ts) |
| Gravação recusada vai ao painel como falha, com o motivo, e a tela diz o motivo | `SavedValuationsActions.confirm` | idem |
| No Raio-X, o cartão "Seus valuations salvos" do ativo, do mais recente ao mais antigo, com as premissas e o resultado do dia, e os botões de reabrir na simulação e de apagar; em **Meus valuations**, os de todos os ativos | [saved-for-asset.tsx](../../src/features/asset/saved-for-asset.tsx); [valuations-page.tsx](../../src/features/valuations/valuations-page.tsx) | idem |

## 7.7 Meta: o acompanhamento da carteira realizada

A curva de acumulação (7.3) diz o que o plano exige sob taxas constantes. O
**acompanhamento** diz o que a carteira fez (decisão 159): desde uma data de
início, cada aporte da meta compra o ativo da Principal com o maior potencial
do dia, e o patrimônio resultante é comparado, com os mesmos aportes nas
mesmas datas, ao caminho exigido, ao esperado, ao CDI e ao Ibovespa.

O cálculo inteiro é `PortfolioTracker.run`, no núcleo, sem relógio nem rede:
recebe o plano, as cotações, os proventos, as compras já gravadas, a data final
e as duas fontes de preço justo, e devolve o patrimônio dia a dia e as compras.

| Regra | Código | Evidência |
|---|---|---|
| O plano congela, no dia do início, a meta (aporte inicial, mensal, valor desejado, prazo) e os ativos da Principal; dia do aporte de 1 a 28 (padrão 5). Mudou a carteira, começa-se outro acompanhamento | [portfolio-tracking.ts, `TrackingPlan`, `TrackingRecord`](../../src/core/services/goal/portfolio-tracking.ts) | — |
| Calendário: o inicial no primeiro pregão a partir do início; cada mensal, a partir do mês seguinte, no primeiro pregão a partir do dia pedido, ou no último pregão do mês **só se o mês já acabou** — o mês em curso espera o dia chegar | `schedule` | teste "mês em curso" |
| **A regra do aporte**: o ativo de maior potencial, `preço justo ÷ preço do dia − 1`, **entre os que pesam menos que o teto** `2/N` (limitado a 100%); peso = posição ÷ total em ações, antes da compra. Nenhum abaixo do teto: o maior potencial geral, e a compra marca "teto ignorado". Empate pela ordem da carteira | `TopUpsidePolicy.choose`, `TopUpsidePolicy.defaultCap` | líder de potencial repetido em 60% dos trimestres (decisão 159) |
| O caixa compra **ações inteiras** — lote de uma, como no fracionário — do escolhido; se o caixa não paga uma ação com a tarifa, passa ao seguinte; se nenhum cabe, não há compra. A sobra fica no caixa, comum à carteira | `affordableShares` ([portfolio-backtest.ts](../../src/core/services/backtest/portfolio-backtest.ts)); `TransactionCosts.b3` | decisão 126 |
| **Preço justo retrospectivo**: aporte agendado antes do dia da criação compra no próprio pregão, com a coorte trimestral vigente — o motor ponto no tempo da validação —, na base da série: `(1 + u_c) · P(c)`, com `P(c)` o fechamento da série na data da coorte | `UpsideCohorts.readingAt`; pacote [upside_coortes.json](../../public/assets/validacao/upside_coortes.json), gerado por [upside-cohorts-package.ts](../../tool/upside-cohorts-package.ts) | decisões 97 e 128; 31 coortes, 31/03/2018 a 30/09/2025 |
| Coorte com mais de 122 dias é velha: a compra usa a última coorte contra o preço do dia, e a tela conta quantas. As cotações começam dez dias antes da coorte vigente no início — e não a um prazo fixo do início —, para que o fechamento da data da coorte exista mesmo meses depois dela | `UpsideCohorts.staleAfterDays`; `TrackingOutcome.staleOrders`; [tracking.ts, `computeTracking`](../../src/app/tracking.ts) | [tracking.test.ts](../../test/app/tracking.test.ts), início cinco meses depois da coorte |
| **Preço justo ao vivo**: aporte a partir da criação compra com a avaliação do motor de hoje, no último pregão disponível; sem a avaliação, o aporte fica pendente e o caixa espera. A primeira passada roda sem o motor e só pede as avaliações se houver aporte ao vivo vencido | `PortfolioTracker.run` (`live`, `pendingLive`); [tracking.ts, `computeTracking`](../../src/app/tracking.ts) | teste "aporte ao vivo" |
| **Proventos** no caixa na data ex, sobre as ações da data-com: `ações × P_com(série) × D_líquido ÷ P_com(B3)`, a mesma identidade do índice de retorno total; JCP líquido da retenção da data-com — 15% até 2025, 17,5% desde 2026 | `CashDividend.netAmountOnRecordDate`; `B3CashDividends.jcpWithholdingOn` | Lei 9.249/1995, art. 9º, § 2º; LC 224/2025 |
| **Compra gravada não muda**: ao reabrir, vale como está, e só o aporte sem registro é decidido. Coleção `trackingOrders`, documento `<acompanhamento>-<aporte em 4 dígitos>`; as regras do Firestore só deixam criar pelo dono do acompanhamento e só regravar idêntico | `recorded`; [tracking-store.ts](../../src/data/persistence/tracking-store.ts); [firestore.rules](../../firestore.rules) | [tracking.test.ts](../../test/app/tracking.test.ts) |
| **Aporte sem preço justo para nenhum ativo não é gravado**: o dinheiro fica em caixa, a tela avisa, e a decisão se refaz na abertura seguinte — uma falta de dado não vira registro de "não comprar" | `PortfolioTracker.run` (`unpriced`) | [portfolio-tracking.test.ts](../../test/core/portfolio-tracking.test.ts) |
| Patrimônio em centavos inteiros, fechando `aportado + proventos − pago − tarifa = caixa` | `PortfolioTracker.run` | teste de identidade |
| Retorno da carteira: XIRR sobre os aportes e o patrimônio final; TWR à parte | `TrackingOutcome.moneyWeightedReturn`, `timeWeightedReturn` | — |
| Exigido com os mesmos aportes: `V_k = V_{k−1}·(1+a)^(Δdias/365) + aporte_k`, base de 365 dias, a do XIRR — a carteira com XIRR igual a `a` termina sobre a curva | `FlowBenchmarks.atAnnualRate` | teste |
| CDI: o saldo do pregão anterior recebe as taxas diárias do Banco Central dos dias `[d_{k−1}, d_k)` | `FlowBenchmarks.onDailyRates` | — |
| Ibovespa: cada aporte compra cotas do índice no fechamento do dia | `FlowBenchmarks.onIndex` | índice de retorno total na metodologia da B3 |
| O exigido é o da meta (7.3). O esperado da carteira não é mais gravado nem desenhado: o registro guarda o campo, vazio desde a decisão 160, e o de acompanhamentos anteriores é ignorado | [tracking-store.ts (app), `TrackingActions.start`](../../src/app/state/tracking-store.ts); [tracking.ts, `computeTracking`](../../src/app/tracking.ts) | decisões 159 e 160 |
| Todo aviso que fala de coorte diz o que ela é: a fotografia trimestral do preço justo, o motor de cada fim de trimestre com só os dados públicos até ali | [tracking.ts, `cohortMeaning`](../../src/app/tracking.ts) | decisão 160 |
| No ritmo de agora: o patrimônio de hoje e os aportes que faltam ao XIRR atual, pela fórmula da curva de acumulação | `projectedEndValue` | — |
| Data de início: hoje, ou no passado desde a primeira coorte; futuro recusado | `startDateProblem` | — |

A tela diz que retrospecto não é prova de habilidade (decisões 96 e 103) e,
ao escolher data passada, que a Principal de hoje carrega viés de
sobrevivência.

## Limitações deste capítulo

- A simulação é de preço: quem recebe provento obtém mais. O acompanhamento
  (7.7) é a exceção: credita e reinveste provento, porque é comparado a
  medidas de retorno total.
- Sem rebalanceamento, a carteira simulada pode ficar muito diferente dos pesos
  escolhidos em janelas longas.
- O cálculo do usuário não é validado: ele é a conta do motor com a opinião de
  quem a digita, e pode chegar a qualquer preço.
- O valuation salvo é o retrato do dia: reabri-lo aplica os números dele à
  conta congelada **de hoje**, que pode ter mudado com dados novos, e por isso
  o preço reaberto pode diferir do gravado.
- O acompanhamento compra com o preço justo da época, mas os ativos são os da
  Principal de hoje: no passado, o resultado é favorecido pelo viés de
  sobrevivência. E o potencial do motor não comprovou ordenar retornos; o
  acompanhamento mostra o que a regra fez, e não que ela funciona.
- Depois da última coorte, enquanto o pacote não for refeito, a compra
  retrospectiva usa um preço justo de até um ano antes.
- O painel de logs só existe com a auditoria ligada (servidor de
  desenvolvimento, ou `VITE_EQUISIM_AUDIT=true` no build); sem ela, o
  valuation é gravado do mesmo jeito e só não vai ao painel.
