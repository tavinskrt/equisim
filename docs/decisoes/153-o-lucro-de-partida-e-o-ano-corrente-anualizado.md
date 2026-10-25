---
numero: 153
titulo: O lucro de partida é o do ano corrente anualizado quando já há ITR depois da última DFP
status: aceita
origem: voce
data: 2026-10-25
citacao: >
  A ideia não é captar pico ou vale, mas sim trazer o valor mais atual
  possível. [...] Acredito que nem precisamos usar mais o de 2025, e sim
  substituir pelo anualizado do ano mesmo. [Escolha no cartão: "No motor,
  anualizado do ano".]
afeta:
  - src/core/services/cvm/year-to-date.ts
  - src/core/services/cvm/cvm-series.ts
  - src/core/services/cvm/fundamentals-merge.ts
  - src/core/entities/fundamentals.ts
  - src/core/services/valuation/capital-base.ts
  - src/core/services/valuation/growth-guards.ts
  - src/core/services/valuation/eligibility.ts
  - src/core/services/valuation/base-normalization.ts
  - src/core/services/valuation/manual-valuation.ts
  - src/core/usecases/compute-valuation.ts
  - src/data/repositories/cvm-fundamentals-repository.ts
  - src/copy/normalization-copy.ts
  - src/features/asset/normalization-panel.tsx
  - src/features/asset/asset-xray.tsx
  - src/features/manual/premise-fields.tsx
  - tool/backtest-valuation.ts
  - tool/validation/frozen.ts
  - tool/cohorts/delisted.ts
  - test/core/year-to-date.test.ts
  - docs/motor/01-insumos-e-dados.md
  - docs/motor/03-base-e-crescimento.md
substitui: []
---

## Contexto

O lucro de partida da cascata era o da última DFP. Entre uma DFP e a seguinte
ele ficava congelado, mesmo com ITRs do ano corrente já públicos. Em
25/10/2026 o BBAS3 partia do lucro de 2025, R$ 16.781,9 mi, com o 1S26
publicado desde 12/08/2026 e lucro de R$ 6.363,0 mi no semestre.

A [decisão 73](073-os-doze-meses-ancoram-a-serie-e-nao-entram-por-padrao.md)
já montava a série de doze meses ancorada no trimestre, mas a deixou fora do
padrão. E ela não serve hoje de qualquer jeito: a CVM não publica o ITR de 2025,
e a série ancorada recua para DFP em todo o universo.

A pergunta foi qual lucro é o mais atual. Os doze meses ainda carregam três
trimestres do ano anterior. O anualizado do acumulado do ano usa só o ano
corrente.

## Decisão

**A série anual termina no ano corrente anualizado** quando há ITR publicado
depois da última DFP. O ponto novo é o acumulado do ITR mais recente vezes
`12 ÷ meses` nos fluxos, com o balanço na data do ITR. Os exercícios anteriores
continuam sendo as DFPs.

Como o ponto é o último da série, ele é o "último exercício" de toda a Porta 2:
o retorno atual é o lucro anualizado sobre o patrimônio do fim da última DFP, a
janela do ciclo passa a ser os oito exercícios completos anteriores a ele, e a
trava de saúde compara o ano corrente com três anos antes.

Três regras protegem as guardas que contam por ano:

1. **O ponto entra nos retornos e fica fora das variações da base.** A variação
   anual da base, a retenção observada, o capital externo (Guarda 2) e a
   regressão da base ignoram o ponto, porque a base dele está a meses da
   anterior, e não a um ano.
2. **O ponto não conta como exercício na Porta 0.** Os oito exercícios
   publicados são exercícios completos.
3. **Só entra o ITR do exercício seguinte à última DFP**, e só se o ano dele
   for o seguinte. O exercício social fora do calendário teria dois pontos no
   mesmo ano, e fica com a série de DFPs.

A regra é uma só para o aplicativo, o backtest, a entrada congelada da
validação e as coortes de deslistadas: todos leem `CvmSeries.yearToDateByDefault`.

## Consequências aceitas

**Anualizar é supor que o resto do ano repete o acumulado.** Não há correção
de sazonalidade. Varejo que concentra o lucro no quarto trimestre sai
subavaliado do 1º ao 3º ITR, e agro que concentra no primeiro semestre sai
superavaliado. O primeiro trimestre vezes quatro é o caso mais ruidoso.

**Item não recorrente do acumulado é multiplicado junto.** No BBAS3, 57% do
lucro do 1S26 é crédito tributário (resultado antes dos tributos de
R$ 2.725,1 mi, crédito de R$ 3.637,8 mi). A regra anterior também não separava
isso, mas agora o fator de anualização o amplia.

**O efeito no BBAS3, medido com o pacote de 14/09/2026:** lucro anualizado de
R$ 12.725,9 mi (1S26 × 2), retorno de 6,6% contra o típico de 16,1%. A queda de
61,6% sobre 2023 passa do limite de 50% da trava de saúde, e a base **não** é
normalizada para cima. O lucro de partida vai de R$ 29.691,5 mi (2025 × 1,77) a
R$ 12.725,9 mi, e o preço justo cai para 42,9% do anterior com as demais
premissas iguais.

**A validação não foi refeita.** A decisão 73 deixou a série trimestral fora
do padrão até a coorte trimestral (C1c) mostrar se a sensibilidade à janela é
informação ou ruído. Esta decisão adota o ano corrente por escolha, antes
dessa evidência. As coortes e o gabarito da cascata precisam ser regravados com
a base ingerida (`data/`), que não está no repositório, e o resultado delas
pode pedir que esta decisão seja revista. O C7 pré-registrado não muda: roda o
núcleo Dart selado.

**Alternativa descartada:** ligar a série ancorada da decisão 73. Ela não tem
viés de sazonalidade, mas recua para DFP em todo o universo enquanto faltar o
ITR de 2025, e carrega três trimestres do ano anterior, que é o que se quis
evitar.
