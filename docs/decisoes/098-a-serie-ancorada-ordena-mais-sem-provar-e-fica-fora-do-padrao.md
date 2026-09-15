---
numero: 98
titulo: A série ancorada no trimestre ordena mais que a anual sem provar, e continua fora do padrão
status: aceita
origem: voce
data: 2026-09-15
citacao: >
  Seus itens de escopo para esta rodada são C1d, C1c e C3.
afeta:
  - tool/backtest_valuation.dart
  - tool/regressao_condicional.dart
  - packages/equisim_core/lib/src/services/cvm/cvm_series.dart
  - docs/validacao/habilidade_trimestral.md
  - docs/validacao/habilidade_trimestral.json
  - docs/validacao/cvm_trimestral.md
substitui: []
---

## Contexto

A [decisão 73](073-os-doze-meses-ancoram-a-serie-e-nao-entram-por-padrao.md)
deixou a série de doze meses ancorada no trimestre mais recente disponível e fora
do padrão: o efeito dela sobre a ordenação é grande — correlação de postos de
0,683 contra a anual —, e se isso é informação ou ruído de calendário era a
pergunta das coortes trimestrais (C1c). O plano marcou o A1.8 com "vira padrão só
se o C1c mostrar que ela ordena melhor que a anual".

Três coisas deixaram a pergunta respondível nesta rodada: a CVM republicou o ITR
de 2025 em 14/09/2026, e a série ancorada deixou de recuar para DFP naquele ano; o
backtest passou a avaliar as duas séries sobre os mesmos insumos em cada coorte
trimestral; e o erro-padrão das janelas sobrepostas ganhou critério
([decisão 96](096-o-t-da-habilidade-e-corrigido-pela-sobreposicao-contra-o-critico-dela.md)).

**A regra foi fixada antes de ver o resultado**: a ancorada vira padrão só se, nas
coortes trimestrais com as deslistadas e nas mesmas observações, a diferença de IC
em 36 meses for positiva e passar no critério da decisão 96, e a de 12 meses não
for negativa.

## Decisão

**A série ancorada continua fora do padrão**, e a decisão 73 continua valendo. O
backtest continua avaliando as duas, e a medição final da habilidade (C1) as
reporta lado a lado.

## Consequências aceitas

**Ela ordena mais, e não prova.** Em 2.467 observações de 22 coortes, com as
deslistadas e o potencial diferente entre as duas séries em 68,5% delas:

| 36 meses | anual | ancorada |
|---|---:|---:|
| IC do potencial | 0,088 | 0,124 |
| coef. do potencial dado o P/B | 0,019 | 0,068 |
| diferença de IC, ancorada − anual | | **+0,036** |
| `t` comum / Newey-West da diferença | | 2,89 / 4,22 |
| **`t` corrigido pela sobreposição / crítico** | | **0,70 / 2,70** |

Em 12 meses, 3.350 observações de 30 coortes: IC de 0,046 contra 0,068, diferença
de +0,022 com `t` corrigido de 0,83 contra o crítico de 2,24. A ancorada ganha nas
duas leituras e em 15 das 22 coortes de 36 meses, e o `t` comum, que a decisão 93
ainda aceitaria, a aprovaria. **É exatamente o caso que a decisão 96 existe para
não aprovar**: 22 coortes que compartilham 33 meses de retorno cada.

**Nas regressões com as duas séries juntas, os coeficientes não se sustentam**:
os dois potenciais têm postos muito correlacionados, e a média do coeficiente da
ancorada dado a anual e o B/M sai negativa, −0,044, com 16 de 21 coortes
positivas — o sinal é de poucas coortes extremas. A comparação que vale é a de
IC e a de cada uma dada só o B/M.

**O que a mantém em aberto.** A diferença é positiva nos dois horizontes e a
direção é a esperada — a série de junho vê a virada do ciclo seis meses antes da
de dezembro. A medição final, com as fases completas, é onde ela se decide de
novo, sobre o motor que existir então.
