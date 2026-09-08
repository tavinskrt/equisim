---
numero: 25
titulo: Reconstrução do motor de avaliação por portas, vias e crescimento fundamental
status: cumprida
origem: orientador
data: 2026-09-04
postura: reconstrucao
citacao: >
  Homologo integralmente a parametrização estatística sugerida e formalizo os
  direcionamentos para as decisões pendentes (M1 a M6) para subsidiar a decisão
  em docs/decisoes/ com postura: reconstrucao
afeta:
  - packages/equisim_core/lib/src/services/valuation
  - packages/equisim_core/lib/src/services/portfolio/expected_return.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/lib/src/usecases/portfolio_usecases.dart
  - packages/equisim_core/lib/src/entities/fundamentals.dart
  - lib/data/datasources/remote/brapi_datasource.dart
  - lib/data/dtos/brapi_dtos.dart
  - docs/refinamento-do-valuation.md
substitui: []
---

## Contexto

A cascata de avaliação foi auditada por execução contra dados de produção, e dez
defeitos foram medidos. Os três de maior efeito:

1. **O retorno esperado é o *upside* cru.** `ExpectedReturn.annualizedFromUpside`
   anualiza por um horizonte de 12 meses, e `(1+u)^(1/1)−1 = u`. A PETR4, com
   +209,2% de *upside*, entrava na média ponderada da carteira como 209,2% ao ano.

2. **O teto da perpetuidade virou o valor de todo mundo.** Oito dos oito ativos
   avaliados por FCFF ficaram exatamente em 8,15%, e o valor terminal responde por
   63,5% a 80,0% do preço justo nesses casos. Uma banda de sanidade que é o valor
   modal deixou de ser banda.

3. **O crescimento sai de uma série contaminada.** A regressão da "fórmula 4" roda
   sobre um LPA montado de duas bases incompatíveis: `earningsPerShare` publicado
   num trecho e `lucro ÷ ações atuais` no outro. Com a bonificação do BBAS3 em
   2024, a série cai de 5,72 para 2,32 entre 2019 e 2020 — troca de denominador,
   não de lucro — e a regressão devolve 0,4% ao ano contra 6,7% sobre o agregado.

A dispersão resultante do *upside* nos dezoito ativos das carteiras de teste vai de
−99,7% (RENT3) a +209,2% (PETR4).

O diagnóstico completo, a arquitetura proposta, a parametrização estatística e as
medições estão em [`docs/refinamento-do-valuation.md`](../refinamento-do-valuation.md).

## Decisão

O motor de avaliação é reconstruído sobre **quatro portas, duas vias e crescimento
fundamental**, com todo limiar determinístico substituído por estatística derivada
do próprio ativo.

**Arquitetura.** Porta 0 filtra elegibilidade (liquidez, histórico, solvência);
Porta 1 roteia instituição financeira para a via do acionista; Porta 3 decide se o
fluxo da firma sustenta perpetuidade; Porta 2 atribui base e taxa em duas saídas
independentes. A via A desconta `NOPAT × (1 − RI)` ao WACC sobre capital investido;
a via B desconta `LPA × (1 − b)` ao Ke sobre patrimônio líquido.

**Crescimento.** `g = ROIC × RI` na via A e `g = ROE × b` na via B, medido como a
mediana das variações anuais da base de capital. A regressão log-linear deixa de ser
o método primário e passa a ser estimador secundário dentro do teste de dispersão.

**Terminal neutro.** `ROIC_∞ = WACC` e `ROE_∞ = Ke`, o que faz
`VT = NOPAT_{N+1}/WACC` — o crescimento perpétuo desaparece da perpetuidade.

**Parâmetros homologados.** Horizonte de convergência de 36 meses; projeção
explícita de 10 anos com decaimento linear da taxa; âncora *top-down* pelo IPCA de
5,00%; teto macroeconômico de 6,52%; e os treze parâmetros estatísticos de P1 a P13
com os valores da seção 10.2 do documento de refinamento.

**Terceiro degrau removido.** `ValuationModel.multiples` e `_tryMultiples` saem: o
método reconstruía o EV a partir do múltiplo que o mercado já atribui ao próprio
ativo, devolvendo o preço de mercado por construção. Os casos sem previsibilidade
passam a ser tratados pela Porta 0, pela migração para a via B e pelo valor da
capacidade de gerar lucro.

## Consequências aceitas

**Todo preço justo já apresentado muda.** Não é ajuste de calibragem: é troca de
método. Números em telas, capturas e no texto da monografia precisam ser refeitos.

**A `docs/validacao/crescimento_log_linear.md` passa a descrever um método que não
é mais o primário.** O registro fica defasado por decisão, não por descuido, e cabe
à lente `registro` apontá-lo.

**A decisão 24 é ampliada, não revogada.** O freio de reinvestimento que ela
introduziu no modelo por LPA passa a valer também na via da firma, onde o fluxo
crescia sem que nada fosse retido para financiar o crescimento.

**A decisão 23 continua valendo integralmente.** A via B é um modelo de desconto de
dividendos, mas obtém o dividendo pela identidade da retenção — `1 − b` é o
*payout* — em vez de buscá-lo em dado publicado de provento. Nenhuma parte da
cadeia removida pela decisão 23 é reaberta.

**O universo elegível encolhe.** Com o corte de liquidez em R$ 2 mi de ADTV de 90
dias, 161 dos 382 papéis-base da B3 permanecem analisáveis. É restrição declarada:
os parâmetros foram calibrados em dezoito ativos cujo ADTV mínimo é de R$ 36,6 mi,
contra mediana de R$ 9,2 mi do universo.

**A exclusão por recuperação judicial depende de lista externa.** A fonte não
publica a informação e `isActive` marca negociabilidade, não continuidade. O filtro
passa a depender de `config/distressed_tickers.json`, mantido à mão.

**Os treze parâmetros continuam sendo escolhas.** O ganho é que passaram a ter
interpretação — nível de significância, ponto de ruptura, materialidade, precisão —
e não que dispensem calibragem. A validação fora da amostra sobre os 161 elegíveis
é o que a completa, e é parte desta decisão.

**A alternativa descartada** era corrigir os defeitos pontualmente, preservando a
cascata atual. Recusada porque os defeitos são acoplados: o teto modal do
crescimento explícito alimenta o teto modal da perpetuidade, que alimenta o peso
terminal, que o horizonte de 12 meses converte em retorno esperado. Corrigir um por
vez deixaria o motor incoerente em cada estado intermediário.

## Condição de encerramento

Acrescentada em 07/09/2026, por determinação do orientador. **É acréscimo ao
corpo de uma decisão aceita**, o que o [README do registro](README.md) reserva
para a marcação de `status` — a exceção fica declarada aqui em vez de silenciosa,
e existe porque a decisão nasceu sem a cláusula que o próprio README exige de
quem declara `postura`.

A postura `reconstrucao` desta decisão se fecha — `status: aceita` passa a
`status: cumprida` — quando as quatro condições valerem ao mesmo tempo:

1. **Roteamento coberto por teste.** As Portas 0 a 3 têm teste unitário que
   trava o comportamento decisório de cada uma.
2. **Base acionária conciliada.** A contagem de ações usada em qualquer ponte
   por papel é arbitrada por `N = lucro ÷ LPA`, e não a corrente crua da fonte.
3. **Validação fora da amostra sem exceção não tratada.** A árvore roda sobre o
   universo elegível e toda saída é declarada — recusa nomeada ou avaliação com
   avisos —, sem falha silenciosa.
4. **Curva de desconto homologada.** O ajuste da taxa livre de risco de
   estrutura a termo está aprovado pelo orientador.

Enquanto as quatro não valerem, a superfície do `afeta` segue acionável.
Alcançá-las é registrar um fato, e a marcação de `status` não reabre a decisão.

**As quatro passaram a valer em 07/09/2026**, e o `status` foi marcado como
`cumprida` pela [decisão 29](029-saude-operacional-na-porta-2a.md), que registra
a conferência condição por condição. A superfície do `afeta` volta à
preservação.
