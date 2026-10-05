# 1. Insumos e dados

O que entra numa avaliação, de onde vem, e as regras que o motor aplica antes de
qualquer conta de valor. Estudo do assunto: [guia, cap. 2](../estudo/02-a-empresa-em-numeros.md).

---

## 1.1 Fontes

| Dado | Fonte | Onde no código | Observação |
|---|---|---|---|
| Demonstrações anuais (DRE, balanço) | **CVM**, dados abertos (DFP), e **brapi** | [cvm_fundamentals_repository.dart](../../lib/data/repositories/cvm_fundamentals_repository.dart), [fundamentals_merge.dart](../../packages/equisim_core/lib/src/services/cvm/fundamentals_merge.dart) | onde as duas têm o mesmo número, vale a CVM; campo ausente é ausente, nunca zero (decisão 52); a base de patrimônio é o PL da CVM, pelo par VPA × contagem e, sem ele, direto (decisões 81 e 146) |
| Cotações diárias, valor de mercado, setor | **brapi** | [brapi_datasource.dart](../../lib/data/datasources/remote/brapi_datasource.dart) | o setor e o subsetor oficiais da B3 vêm do pacote [assets/b3/emissores.json](../../assets/b3/) |
| Contagem oficial de ações | **B3**, registro de emissores | [b3_registry.dart](../../packages/equisim_core/lib/src/services/b3/b3_registry.dart) | líquida de tesouraria (decisão 83) |
| Proventos em dinheiro | **B3** | [cash_dividends.dart](../../packages/equisim_core/lib/src/services/b3/cash_dividends.dart), [assets/b3/proventos.json](../../assets/b3/) | usados no retorno total do beta e das coortes (decisão 89) e, somados na bolsa inteira, na série do prêmio implícito que dá o prêmio de mercado (decisão 142); nunca no fluxo de um ativo |
| Eventos societários (desdobramento, bonificação) | **B3** e **CVM** | [corporate_events.dart](../../packages/equisim_core/lib/src/services/b3/corporate_events.dart), [capital_events.dart](../../packages/equisim_core/lib/src/services/cvm/capital_events.dart) | completam o ajuste da série de preços (item B29) e o capital posterior (item B28) |
| Composição das units | **CVM**, formulário cadastral | [unit_composition.dart](../../packages/equisim_core/lib/src/services/cvm/unit_composition.dart), [assets/cvm/units.json](../../assets/cvm/) | decisão 106 (item B16) |
| Espécie do controle acionário | **CVM**, formulário cadastral | [shareholder_control.dart](../../packages/equisim_core/lib/src/services/cvm/shareholder_control.dart), [assets/cvm/controle.json](../../assets/cvm/) | só a ressalva de controle estatal; não muda preço (decisão 145, item B46) |
| Prazo das concessões | **CVM**, Formulário de Referência | [fre_concessions.dart](../../packages/equisim_core/lib/src/services/cvm/fre_concessions.dart), [assets/cvm/outorgas.json](../../assets/cvm/) | decisão 88 |
| Títulos prefixados (curva) | **Tesouro Direto** | [tesouro_datasource.dart](../../lib/data/datasources/remote/tesouro_datasource.dart), [yield_curve.dart](../../packages/equisim_core/lib/src/services/valuation/yield_curve.dart) | decisões 74, 79 e 84; pacote web em [assets/tesouro/curva.json](../../assets/tesouro/) |
| CDI, IPCA, IBC-Br | **Banco Central**, SGS (séries 12, 433 e 24364) | [bcb_datasource.dart](../../lib/data/datasources/remote/bcb_datasource.dart) | IBC-Br dessazonalizado |
| Histórico de cotações das coortes | **B3**, COTAHIST | [b3_cotahist.md](../validacao/b3_cotahist.md) | só na validação, inclui as deslistadas |

O aplicativo guarda o que busca num cache local (SQLite, via Drift), para não
repetir a rede e para que a mesma consulta devolva o mesmo dado. Sem cache, ele
continua funcionando ([providers.dart, `cacheDatabaseProvider`](../../lib/di/providers.dart);
[web/ASSETS.md](../../web/ASSETS.md)).

---

## 1.2 Visão *point-in-time*

| Regra | Código | Fundamento | Evidência |
|---|---|---|---|
| Toda avaliação tem uma data; só entram exercícios **publicados** até ela | [point_in_time_view.dart](../../packages/equisim_core/lib/src/time/point_in_time_view.dart) | evitar o viés de antecipação (*look-ahead bias*) em validação histórica | — |
| Publicado = data de recebimento na CVM (`DT_RECEB`) quando existe; senão, fim do exercício + 90 dias | `PointInTimeView.defaultLag` | a defasagem real medida tem mediana de 78 dias; 90 é conservador | comentário da classe |
| Exercício sem demonstração de resultado é descartado, com aviso | `ValuationCascade._evaluate`, `hasIncomeStatement` | ausência não é zero | decisão 52 |
| Aviso se o exercício mais recente tem mais de dois anos | `_evaluate` | dado velho descreve outra empresa | — |

---

## 1.3 Grandezas derivadas do exercício

Todas em [fundamentals.dart](../../packages/equisim_core/lib/src/entities/fundamentals.dart).

| Grandeza | Conta | Nota |
|---|---|---|
| Dívida bruta | empréstimos de curto + longo prazo | a conta-mãe da fonte já contém debêntures e arrendamento |
| Caixa | caixa + aplicações de curto prazo | |
| Dívida líquida | bruta − caixa | **a dívida do modelo inteiro**: ponte, realavancagem, desalavancagem do beta e pesos do WACC (decisões 41, 54, 102, 104) |
| Patrimônio líquido | valor patrimonial por ação × ações do exercício | reconstrói o PL publicado com a contagem daquele exercício |
| Capital investido | PL + dívida bruta − caixa (positivo) | pelo lado do financiamento; o lado operacional não fecha com a fonte e foi medido (comentário de `investedCapitalOperating`) |
| NOPAT | `EBIT × (1 − τ) + equivalência positiva (até o EBIT) × τ` | a equivalência já chega tributada; a negativa não gera crédito (`nopatAtRate`, `taxableEquityIncome`) |
| Alíquota efetiva | −imposto ÷ lucro antes do imposto, em [0; 50%] | nula com lucro antes do imposto ≤ 0 |
| Cobertura de juros | EBIT ÷ despesa financeira (zero com EBIT negativo) | escudo fiscal e, quando a despesa é juro de verdade, prêmio de crédito (decisão 130) |
| Alavancagem | dívida líquida ÷ EBITDA (nula com EBITDA ≤ 0) | prêmio de crédito |

---

## 1.4 A contagem de papéis e a unit

O preço justo é por **papel negociado**, e a contagem que o divide é a mesma que
forma a cotação.

| Regra | Código | Evidência |
|---|---|---|
| Razão da unit declarada (formulário cadastral, entre 1 e 10) vale; sem declaração, a medida `ações × preço ÷ valor de mercado`, arredondada, com tolerância de 5% | `ValuationCascade.quotedUnitRatio`, `_auditUnitRatio` | decisão 106 (item B16): a medida erra 79 de 220 observações de unit nas coortes |
| Contagem oficial da B3, líquida de tesouraria, quando recente, arbitra | `ValuationCascade.quotedShares` | decisão 83 |
| Sem oficial: valor de mercado ÷ preço; se divergir da contagem das demonstrações além de 1,5×, vale a **maior** (menor preço por papel) | idem | decisão 66, confirmada por contrafactual |
| O aviso de contagens discordantes nomeia a contagem que a ponte usou | `_evaluate` | item B40, corrigido em 28/09/2026 |
| Capital emitido depois do balanço entra na contagem e é somado ao capital próprio | `_comCapitalPosterior` | item B28 |

---

## 1.5 Âncoras de mercado

Calculadas em [portfolio_usecases.dart, `ResolveMarketAnchors`](../../packages/equisim_core/lib/src/usecases/portfolio_usecases.dart)
sobre uma janela de dez anos até a data.

| Âncora | Conta | Uso | Valor em 14/09/2026 |
|---|---|---|---:|
| CDI corrente | rendimento dos últimos 63 pregões, anualizado por composição | Ke "do dia", WACC estático, meta | 14,09% |
| CDI de dez anos | taxa composta média | recuo da perpetuidade sem curva | 9,39% |
| Inflação | IPCA de dez anos, composto | âncora do crescimento não identificado | 4,92% |
| Crescimento real | IBC-Br, médias móveis de 12 meses nas pontas | compõe o teto | 1,77% |
| Teto do crescimento perpétuo | `(1 + real) × (1 + inflação) − 1` | limite de `g∞` | 6,78% |
| Retorno do Ibovespa | médias de 63 pregões nas pontas, composto | meta (decisão 60) | — |

Sem rede e sem cache, valem valores de recuo declarados em
`MarketAnchors.fallback2026` ([feasibility.dart](../../packages/equisim_core/lib/src/services/goal/feasibility.dart)).

---

## 1.6 A curva de juros

| Regra | Código | Evidência |
|---|---|---|
| Vértices: Tesouro Prefixado (LTN, taxa à vista direta) e Prefixado com Juros Semestrais (NTN-F, taxa interna tratada como à vista); onde os dois existem, vale a LTN | [yield_curve.dart](../../packages/equisim_core/lib/src/services/valuation/yield_curve.dart), `YieldCurve.at` | decisão 74; diferença LTN × NTN-F medida em −20 a +2 pontos-base |
| Prazo em dias úteis ÷ 252, pelo calendário da data | `BrazilianCalendar` | decisão 79: 99,13% das LTN com o `du` exato desde 2010 |
| Interpolação *flat-forward* (linear no log do fator de desconto); extrapolação pelo último forward | `YieldCurve` | convenção de mercado; não produz forward negativo entre vértices positivos |
| A taxa livre de risco do ano t é o forward de um ano entre t−1 e t | `annualForwards` | — |
| A perpetuidade usa o forward depois do ano N | `terminalRate`; `ValuationInputs.terminalRiskFreeRate` | — |
| Sem curva: CDI corrente no ano 1 e CDI de dez anos na perpetuidade, em linha reta | `DcfAssumptions.discountRateAt` | recuo; no aplicativo web, o pacote da curva vence em sete dias |

---

## 1.7 O beta que entra na avaliação

| Regra | Código | Fundamento | Evidência |
|---|---|---|---|
| Janela de cinco anos até a data; retornos **diários** pareados por data com o Ibovespa | [prepare_valuation_inputs.dart, `_estimateBeta`](../../packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart); [beta.dart](../../packages/equisim_core/lib/src/services/metrics/beta.dart) | regressão de mercado (Sharpe, 1964) | — |
| Retorno total dos dois lados: o ativo com os proventos em dinheiro da B3 reinvestidos | `TotalReturnIndex` | o Ibovespa já é de retorno total | decisão 89 |
| `β = Cov(ativo, índice) ÷ Var(índice)`, com pelo menos 30 pares; erro-padrão `|β|·√((1−ρ²)/(ρ²(n−2)))` | `BetaCalculator` | MQO | — |
| Sem 30 pares: β = 1, declarado como manual | `_estimateBeta` | premissa neutra e transparente | — |
| Correção de não sincronia (Dimson) medida e recusada | — | a Porta 0 já tira quem sofreria dela | decisão 57 |
| Encolhimento para o beta do setor, pela precisão (capítulo 4) | [beta_shrinkage.dart](../../packages/equisim_core/lib/src/services/metrics/beta_shrinkage.dart) | Vasicek (1973) | decisão 40 |
| Aviso quando a janela cobre menos de 80% de cinco anos | `_evaluate` | janela curta, beta menos preciso | decisão 111 |

## Limitações deste capítulo

- O setor é o do emissor na classificação oficial da B3 (297 de 297 emissores
  do universo), baixada em 14/09/2026; mudança exige reempacotar (decisão 87).
  Antes dela, classes sem perfil na brapi escapavam da Porta 1.
- A NTN-F entra como taxa à vista, embora tenha cupom.
- A curva do aplicativo web é um pacote que vence em sete dias; depois disso, a
  avaliação cai para a interpolação de duas pontas e diz isso num aviso.
