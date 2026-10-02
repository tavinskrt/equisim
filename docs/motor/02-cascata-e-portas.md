# 2. Cascata e portas

A ordem em que o motor decide se avalia uma empresa e por qual caminho. Estudo:
[guia, cap. 4, seções 4.2 e 4.3](../estudo/04-fluxo-de-caixa-descontado.md).

![A cascata](../estudo/img/cascata.svg)

Tudo acontece em [compute_valuation.dart](../../packages/equisim_core/lib/src/usecases/compute_valuation.dart),
a partir de `ValuationCascade.evaluate`.

---

## 2.1 A ordem

| # | Etapa | Função | Recusa quando |
|---:|---|---|---|
| 1 | Concessão que acaba antes do horizonte encurta a projeção | `_evaluate` | — |
| 2 | Preço positivo | `_evaluate` | preço ≤ 0 |
| 3 | Exercícios publicados na data, com demonstração de resultado | `_evaluate` | nenhum exercício |
| 4 | **Porta 0** — elegibilidade | [eligibility.dart](../../packages/equisim_core/lib/src/services/valuation/eligibility.dart), `EligibilityGate.assess` | ver 2.2 |
| 5 | Razão da unit e contagem de papéis | `quotedUnitRatio`, `quotedShares` | contagem indisponível |
| 6 | **Portas 1 e 3** — roteamento | `_route` | — |
| 7 | **Porta 2** — premissas e desconto na via escolhida | `_evaluateLane` | dado não sustenta a via; estrutura de capital recusada; preço justo ≤ 0 |
| 8 | Resultado, cenários, diagnósticos | `_concluir`, `_withScenarios`, `_diagnose` | — |

---

## 2.2 Porta 0 — elegibilidade

| Critério | Parâmetro | Código | Por quê |
|---|---|---|---|
| Liquidez | volume financeiro diário **mediano** dos últimos 90 pregões ≥ R$ 2 milhões (sem volume na série, o teste é omitido) | `minAverageDailyTradedValue`, `liquidityWindowDays`, `medianTradedValue` | preço de papel ilíquido informa pouco e contamina o beta; mediana porque um dia de leilão não faz liquidez |
| Histórico | ≥ 8 exercícios publicados | `minPublishedPeriods` | os testes de ciclo, tendência e crescimento precisam de série |
| Insolvência | patrimônio ≤ 0 (ou ausente) no último **e** no penúltimo exercício | `_insolvent` | sem patrimônio não há base de capital |
| Recuperação judicial | lista mantida | [distressed_registry.dart](../../lib/data/config/distressed_registry.dart) | o fluxo descontado supõe continuidade |

A recusa por liquidez foi medida contra a ordenação e mantida pelo nível, e não
pela ordenação (decisão 95).

---

## 2.3 Porta 1 — instituição financeira

| Regra | Código | Por quê |
|---|---|---|
| Setor "serviços financeiros" da fonte, ou setor B3 "financeiro" com subsetor intermediários financeiros, previdência e seguros ou serviços financeiros diversos → **via do acionista** | [financial_sectors.dart](../../packages/equisim_core/lib/src/services/valuation/financial_sectors.dart), `FinancialSectors.isFinancial` | captação é insumo, não financiamento (Damodaran, "Valuing financial service firms"); decisão 25 |

O aviso da tela explica a razão em uma frase.

---

## 2.4 Porta 3 — fluxo operacional sustentado

| Regra | Código | Por quê |
|---|---|---|
| NOPAT (publicado ou derivado) positivo em pelo menos 60% dos exercícios, com pelo menos 4 → **via da firma**; senão, **via do acionista** | [growth_guards.dart](../../packages/equisim_core/lib/src/services/valuation/growth_guards.dart), `GrowthGuards.firmFlowIsSustained` | a via da firma projeta o resultado operacional; com ele negativo na maioria dos anos, não há base a projetar (decisão 64) |
| A fronteira usa o fluxo, e não a comparação entre retorno e custo de capital do dia | `_route` | medir contra a taxa do dia faria a via andar com o ciclo monetário (decisão 34) |

---

## 2.5 A via não muda depois de escolhida

| Regra | Código | Evidência |
|---|---|---|
| Se a via escolhida recusa (estrutura de capital, preço justo ≤ 0), o ativo é recusado — não é mandado para a outra via | `_evaluateLane` | decisão 102: trocar de modelo porque um recusou faria o preço justo depender de qual conta alcançou um número |
| As duas vias são modelos distintos, não duas opiniões sobre o mesmo número | — | decisão 39: discordavam além de 1,5× em 55 de 92 ativos |

Imposições de diagnóstico (`laneOverride`, `growthOverride`, `terminalReturnOverride`
etc.) existem só para medição e testes; o aplicativo não as usa.

---

## 2.6 As recusas, contadas

Na entrada congelada de 14/09/2026 (gabarito, montagem do aplicativo), de 376
ativos: 189 recusados por liquidez, 34 por histórico, 4 por patrimônio negativo;
os demais recusados por falta de demonstrativo, por dado que não sustenta via ou
por estrutura de capital. **108 avaliados** (motor de 01/10/2026): 88 pela via
da firma, 20 pela do acionista (19 financeiras e uma não financeira). Ver o [caso RENT3](../estudo/casos/rent3.md)
para uma recusa por estrutura de capital.
