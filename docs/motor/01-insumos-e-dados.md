# 1. Insumos e dados

O que entra numa avaliação, de onde vem, e as regras que o motor aplica antes de
qualquer conta de valor. Estudo do assunto: [guia, cap. 2](../estudo/02-a-empresa-em-numeros.md).

---

## 1.1 Fontes

| Dado | Fonte | Onde no código | Observação |
|---|---|---|---|
| Demonstrações anuais (DRE, balanço) | **CVM**, dados abertos (DFP), e **brapi** | [cvm-fundamentals-repository.ts](../../src/data/repositories/cvm-fundamentals-repository.ts), [fundamentals-merge.ts](../../src/core/services/cvm/fundamentals-merge.ts) | onde as duas têm o mesmo número, vale a CVM; campo ausente é ausente, nunca zero; a base de patrimônio é o PL da CVM, pelo par VPA × contagem e, sem ele, direto |
| Ano corrente anualizado | **CVM**, dados abertos (ITR) | [year-to-date.ts](../../src/core/services/cvm/year-to-date.ts), [cvm-series.ts](../../src/core/services/cvm/cvm-series.ts) | com ITR publicado depois da última DFP, a série anual ganha um ponto final: o acumulado do ano × 12 ÷ meses nos fluxos, o balanço na data do ITR |
| Cotações diárias, valor de mercado, setor | **brapi** | [brapi-datasource.ts](../../src/data/datasources/brapi-datasource.ts) | o setor e o subsetor oficiais da B3 vêm do pacote [public/assets/b3/emissores.json](../../public/assets/b3/) |
| Contagem oficial de ações | **B3**, registro de emissores | [b3-registry.ts](../../src/core/services/b3/b3-registry.ts) | líquida de tesouraria ([b3_registro.md](../validacao/b3_registro.md)) |
| Proventos em dinheiro | **B3** | [cash-dividends.ts](../../src/core/services/b3/cash-dividends.ts), [public/assets/b3/proventos.json](../../public/assets/b3/) | usados no retorno total do beta e das coortes ([proventos.md](../validacao/proventos.md)) e, somados na bolsa inteira, na série do prêmio implícito que dá o prêmio de mercado ([premio_implicito.md](../validacao/premio_implicito.md)); nunca no fluxo de um ativo |
| Eventos societários (desdobramento, bonificação) | **B3** e **CVM** | [corporate-events.ts](../../src/core/services/b3/corporate-events.ts), [capital-events.ts](../../src/core/services/cvm/capital-events.ts) | completam o ajuste da série de preços e o capital emitido depois do balanço (1.4) |
| Composição das units | **CVM**, formulário cadastral | [unit-composition.ts](../../src/core/services/cvm/unit-composition.ts), [public/assets/cvm/units.json](../../public/assets/cvm/) | a razão declarada decide; a medida no valor de mercado confere ([ponte_por_papel.md](../validacao/ponte_por_papel.md)) |
| Espécie do controle acionário | **CVM**, formulário cadastral | [shareholder-control.ts](../../src/core/services/cvm/shareholder-control.ts), [public/assets/cvm/controle.json](../../public/assets/cvm/) | só a ressalva de controle estatal; não muda preço ([estatais.md](../validacao/estatais.md)) |
| Prazo das concessões | **CVM**, Formulário de Referência | [fre-concessions.ts](../../src/core/services/cvm/fre-concessions.ts), [public/assets/cvm/outorgas.json](../../public/assets/cvm/) | o excedente sobre o capital termina no fim do contrato (capítulo 5; [outorgas.md](../validacao/outorgas.md)) |
| Títulos prefixados (curva) | **Tesouro Direto** | [treasury-datasource.ts](../../src/data/datasources/treasury-datasource.ts), [yield-curve.ts](../../src/core/services/valuation/yield-curve.ts) | a taxa livre de risco padrão (1.6; [curva_de_juros.md](../validacao/curva_de_juros.md)); pacote web em [public/assets/tesouro/curva.json](../../public/assets/tesouro/) |
| CDI, IPCA, IBC-Br | **Banco Central**, SGS (séries 12, 433 e 24364) | [bcb-datasource.ts](../../src/data/datasources/bcb-datasource.ts) | IBC-Br dessazonalizado |
| Histórico de cotações das coortes | **B3**, COTAHIST | [b3_cotahist.md](../validacao/b3_cotahist.md) | só na validação, inclui as deslistadas |

O aplicativo guarda o que busca num cache local (IndexedDB do navegador, banco
`equisim-cache`), para não repetir a rede e para que a mesma consulta devolva o
mesmo dado, com validade por tipo: cotações por 12 horas, fundamentos por 30
dias, perfil por 90 e séries do Banco Central por um dia. Sem IndexedDB (janela
anônima, armazenamento bloqueado), o cache fica em memória e o aplicativo
continua funcionando ([boot.ts, `openStore`](../../src/app/boot.ts);
[cache-database.ts](../../src/data/cache/cache-database.ts);
[cache-policy.ts](../../src/data/cache/cache-policy.ts)). As ferramentas de
medição leem o mesmo formato de um SQLite em disco
([sqlite-cache.ts](../../tool/lib/sqlite-cache.ts)).

---

## 1.2 Visão *point-in-time*

| Regra | Código | Fundamento | Evidência |
|---|---|---|---|
| Toda avaliação tem uma data; só entram exercícios **publicados** até ela | [point-in-time-view.ts](../../src/core/time/point-in-time-view.ts) | evitar o viés de antecipação (*look-ahead bias*) em validação histórica | — |
| Publicado = data de recebimento na CVM (`DT_RECEB`) quando existe; senão, fim do exercício + 90 dias | `PointInTimeView.defaultLag` | a defasagem real medida tem mediana de 78 dias; 90 é conservador | comentário da classe |
| Exercício sem demonstração de resultado é descartado, com aviso | `ValuationCascade.evaluate`, `hasIncomeStatement` | ausência não é zero | o aviso diz quantos exercícios saíram |
| Aviso se o exercício mais recente tem mais de dois anos | `evaluate` | dado velho descreve outra empresa | — |

---

## 1.3 Grandezas derivadas do exercício

Todas em [fundamentals.ts](../../src/core/entities/fundamentals.ts).

| Grandeza | Conta | Nota |
|---|---|---|
| Dívida bruta | empréstimos de curto + longo prazo | a conta-mãe da fonte já contém debêntures e arrendamento |
| Caixa | caixa + aplicações de curto prazo | |
| Dívida líquida | bruta − caixa | **a dívida do modelo inteiro**: ponte, realavancagem, desalavancagem do beta e pesos do WACC ([divida_do_wacc.md](../validacao/divida_do_wacc.md)) |
| Patrimônio líquido | valor patrimonial por ação × ações do exercício | reconstrói o PL publicado com a contagem daquele exercício |
| Capital investido | PL + dívida bruta − caixa (positivo) | pelo lado do financiamento; o lado operacional não fecha com a fonte e foi medido (comentário de `investedCapitalOperating`) |
| NOPAT | `EBIT × (1 − τ) + equivalência positiva (até o EBIT) × τ` | a equivalência já chega tributada; a negativa não gera crédito (`nopatAtRate`, `taxableEquityIncome`) |
| Alíquota efetiva | −imposto ÷ lucro antes do imposto, em [0; 50%] | nula com lucro antes do imposto ≤ 0 |
| Cobertura de juros | EBIT ÷ despesa financeira (zero com EBIT negativo) | escudo fiscal e, quando a despesa é juro de verdade, prêmio de crédito (capítulo 4) |
| Alavancagem | dívida líquida ÷ EBITDA (nula com EBITDA ≤ 0) | prêmio de crédito |

---

## 1.4 A contagem de papéis e a unit

O preço justo é por **papel negociado**, e a contagem que o divide é a mesma que
forma a cotação.

| Regra | Código | Evidência |
|---|---|---|
| Razão da unit declarada (formulário cadastral, entre 1 e 10) vale; sem declaração, a medida `ações × preço ÷ valor de mercado`, arredondada, com tolerância de 5% | `ValuationCascade.quotedUnitRatio`, `auditUnitRatio` | a medida erra 79 de 220 observações de unit nas coortes ([ponte_por_papel.md](../validacao/ponte_por_papel.md)) |
| Contagem oficial da B3, líquida de tesouraria, quando recente, arbitra | `ValuationCascade.quotedShares` | [b3_registro.md](../validacao/b3_registro.md) |
| Sem oficial: valor de mercado ÷ preço; se divergir da contagem das demonstrações além de 1,5×, vale a **maior** (menor preço por papel) | idem | confirmada por contrafactual: trocar a contábil pela implícita no valor de mercado levaria os onze casos em que ela vence para cima, até +69.039,8% na MILS3, o falso desconto que a regra existe para barrar |
| O aviso de contagens discordantes nomeia a contagem que a ponte usou | `evaluate` | — |
| Capital emitido depois do balanço entra na contagem e é somado ao capital próprio | `withPosteriorCapital` | sem o valor declarado, a avaliação avisa |

---

## 1.5 Âncoras de mercado

Calculadas em [portfolio-usecases.ts, `ResolveMarketAnchors`](../../src/core/usecases/portfolio-usecases.ts)
sobre uma janela de dez anos até a data.

| Âncora | Conta | Uso | Valor em 14/09/2026 (refeito em 03/11/2026) |
|---|---|---|---:|
| CDI corrente | rendimento dos últimos 63 pregões, anualizado por composição | Ke "do dia", WACC estático, meta | 14,05% |
| CDI de dez anos | taxa composta média | recuo da perpetuidade sem curva | 9,40% |
| Inflação | IPCA de dez anos, composto | âncora do crescimento não identificado | 4,96% |
| Crescimento real | IBC-Br, médias móveis de 12 meses nas pontas | compõe o teto | 1,77% |
| Teto do crescimento perpétuo | `(1 + real) × (1 + inflação) − 1` | limite de `g∞` | 6,83% |
| Retorno do Ibovespa | médias de 63 pregões nas pontas, composto | meta | as pontas médias tiram 1,51 p.p. de ruído da medida de um pregão só |

Sem rede e sem cache, valem valores de recuo declarados em
`MarketAnchors.fallback2026` ([feasibility.ts](../../src/core/services/goal/feasibility.ts)).

---

## 1.6 A curva de juros

| Regra | Código | Evidência |
|---|---|---|
| Vértices: Tesouro Prefixado (LTN, taxa à vista direta) e Prefixado com Juros Semestrais (NTN-F, taxa interna tratada como à vista); onde os dois existem, vale a LTN | [yield-curve.ts](../../src/core/services/valuation/yield-curve.ts), `YieldCurve.at` | diferença LTN × NTN-F medida em −20 a +2 pontos-base ([curva_de_juros.md](../validacao/curva_de_juros.md)) |
| Prazo em dias úteis ÷ 252, pelo calendário da data | `BrazilianCalendar` | 99,13% das LTN com o `du` exato desde 2010 ([curva_de_juros.md](../validacao/curva_de_juros.md)) |
| Interpolação *flat-forward* (linear no log do fator de desconto); extrapolação pelo último forward | `YieldCurve` | convenção de mercado; não produz forward negativo entre vértices positivos |
| A taxa livre de risco do ano t é o forward de um ano entre t−1 e t | `annualForwards` | — |
| A perpetuidade usa o forward depois do ano N | `terminalRate`; `ValuationInputs.terminalRiskFreeRate` | — |
| Sem curva: CDI corrente no ano 1 e CDI de dez anos na perpetuidade, em linha reta | `DcfAssumptions.discountRateAt` | recuo; no aplicativo web, o pacote da curva vence em sete dias |

---

## 1.7 O beta que entra na avaliação

| Regra | Código | Fundamento | Evidência |
|---|---|---|---|
| Janela de cinco anos até a data; retornos **diários** pareados por data com o Ibovespa | [prepare-valuation-inputs.ts, `estimateBeta`](../../src/core/usecases/prepare-valuation-inputs.ts); [beta.ts](../../src/core/services/metrics/beta.ts) | regressão de mercado (Sharpe, 1964) | — |
| Retorno total dos dois lados: o ativo com os proventos em dinheiro da B3 reinvestidos | `TotalReturnIndex` | o Ibovespa já é de retorno total | [proventos.md](../validacao/proventos.md) |
| `β = Cov(ativo, índice) ÷ Var(índice)`, com pelo menos 30 pares; erro-padrão `|β|·√((1−ρ²)/(ρ²(n−2)))` | `BetaCalculator` | MQO | — |
| Sem 30 pares: β = 1, declarado como manual | `estimateBeta` | premissa neutra e transparente | — |
| Correção de não sincronia (Dimson) medida e recusada | — | a Porta 0 já tira quem sofreria dela | [beta_sincronia.md](../validacao/beta_sincronia.md) |
| Encolhimento para o beta do setor, pela precisão (capítulo 4) | [beta-shrinkage.ts](../../src/core/services/metrics/beta-shrinkage.ts) | Vasicek (1973) | [beta_setorial.md](../validacao/beta_setorial.md) |
| Aviso quando a janela cobre menos de 80% de cinco anos | `evaluate` | janela curta, beta menos preciso | — |

## Limitações deste capítulo

- O setor é o do emissor na classificação oficial da B3 (297 de 297 emissores
  do universo), baixada em 14/09/2026; mudança de classificação exige
  reempacotar o registro.
- A NTN-F entra como taxa à vista, embora tenha cupom.
- A curva do aplicativo web é um pacote que vence em sete dias; depois disso, a
  avaliação cai para a interpolação de duas pontas e diz isso num aviso.
