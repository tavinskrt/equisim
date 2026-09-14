---
numero: 78
titulo: A mescla não empresta fluxo de outra janela, e documento recebido depois da data não ocupa o ano
status: aceita
origem: parecer
data: 2026-09-14
afeta:
  - packages/equisim_core/lib/src/services/cvm/fundamentals_merge.dart
  - packages/equisim_core/lib/src/services/cvm/cvm_series.dart
  - packages/equisim_core/test/fundamentals_merge_test.dart
  - packages/equisim_core/test/cvm_series_test.dart
  - tool/cvm_ligar.dart
  - docs/validacao/cvm_trimestral.md
substitui: []
---

## Contexto

Dois defeitos em `CvmSeries` e na mescla, achados por revisão própria enquanto
as lentes da rodada de A1.8 a A3 rodavam. **Os dois contaminaram a medição que
sustenta a [decisão 73](073-os-doze-meses-ancoram-a-serie-e-nao-entram-por-padrao.md).**

**1. A mescla completava um ponto com exercício de outra janela.** Na série
ancorada, o ponto de doze meses até junho era completado pelo último exercício
de mercado encerrado até ali — o dezembro anterior —, e todo campo que a CVM não
traz vinha de lá: a despesa de juros de outra janela ia para o custo da dívida
(`costOfDebt`), o NOPAT publicado de outra janela vencia o derivado do EBIT
(`nopatOrDerived` prefere o publicado), e o LPA de outro lucro entrava no
árbitro `lucro ÷ LPA` da contagem de ações. No caminho anual o mesmo acontecia
onde o mercado não tem o ano: em 04/09/2026, **um ponto** em 5.052 — o
exercício de 2025 da NATU3, completado pelo de 2024.

**2. DFP recebida depois da data ocupava o ano.** A ingestão guarda a última
versão de cada documento, e a data de recebimento é a dela. A DFP de 2023 da
USIM3 foi reapresentada, e a versão ingerida tem recebimento em 16/01/2025. Em
04/09/2024 ela não existia, mas o caminho anual a mesclava mesmo assim: o
exercício de mercado de 2023, publicado de fato, era descartado, e a cascata
depois removia o ponto mesclado por ser do futuro. **O ano sumia**, e a USIM3
era avaliada sobre 2022. É por isso que USIM3 (−47 p.p.) e USIM5 (−42 p.p.)
apareciam entre os maiores movimentos do A1.7 em 2024: artefato, e não
informação da CVM. Doze tickers do universo têm DFP nessa situação em
04/09/2024; nenhum em 04/09/2026.

### A primeira correção passou do ponto

A primeira versão da regra 1 recusava emprestar **qualquer** campo de outra
janela, fora os que descrevem hoje. Remedida em 04/09/2024, a série ancorada
perdeu **106 de 113** avaliados, todos recusados como insolventes — com R$ 20 bi
de patrimônio na própria linha da WEGE3.

A causa é um fato do motor que nenhum registro dizia: **a base de patrimônio da
cascata é sempre `VPA × contagem do exercício`** (`equityBookValue`), dois
campos só de mercado. O `totalStockholderEquity` que a CVM traz chega à cascata
e **não é lido em lugar nenhum** do núcleo. Sem o par por ação, não há
patrimônio.

## Decisão

1. **Mesma janela é mesma data de encerramento**, com folga de quatro dias
   (`FundamentalsMerge.mesmaJanela`). Quando as datas diferem, o mercado
   empresta só `FundamentalsMerge.emprestaveis`:
   - o que descreve **hoje** — valor de mercado, contagem corrente, EV/EBITDA;
   - o **par por ação do último encerramento** — VPA e contagem do exercício —,
     que é estoque, entra junto e é a base de patrimônio da cascata.

   **Fluxo nunca é emprestado.** O LPA é fluxo por ação e fica de fora.
2. **A série anual usa só DFP publicada na data**, como a ancorada já fazia. O
   ano de um documento ainda não recebido fica com o mercado.
3. A regra mora **na mescla**, e não em quem a chama: é a lição da decisão 70,
   de que regra na montagem é reintroduzida pela próxima montagem.

## Remedição

Em 04/09/2024, na mesma execução — as comparações entre execuções ficaram
contaminadas por cache que venceu no meio de uma delas, em 26 ativos de M em
diante:

| | medido na decisão 73 | corrigido |
|---|---:|---:|
| avaliados, anual → ancorada | 113 → 108 | 113 → 108 |
| mediana do `\|Δ potencial\|` anual × ancorada | 9,8% | **14,8%** |
| `\|Δ\|` > 10 p.p. | 51 | **60** |
| **correlação de postos anual × ancorada** | **0,816** | **0,683** |
| correlação de postos mercado × anual | 0,968 | **0,977** |
| A1.7: `\|Δ\|` > 10 p.p. | 14 | **12** |

**A decisão 73 fica, e sai mais forte.** A série ancorada se afasta **mais** da
anual quando deixa de pegar emprestado o que era do dezembro — a mistura
amortecia a diferença. O caminho anual, que é o padrão, ficou idêntico em 375
de 375 ativos com a regra 1, e na data padrão os agregados do A1.7 não mudam
(127 → 128, mediana de 0,0%, 8 acima de 10 p.p.).

## Consequências aceitas

**Num ponto de junho, a base de patrimônio é a do dezembro anterior**, somada à
dívida e ao caixa de junho. Não é fluxo de outra janela, mas é estoque de outra
data. A saída é a cascata ler o patrimônio da CVM na data do ponto — **item
A1.11 do plano**, que é mudança de método e pede decisão própria, inclusive
sobre o que o PL consolidado da CVM inclui de não controladores.

**O ano de DFP reapresentada fica com o mercado**, e não com a versão original
da CVM, que a ingestão não guarda. A correção certa é o B8: ler a data de cada
versão, e não só a da última.

Pontos de outra janela perdem campos que antes tinham: sem despesa de juros, o
custo da dívida é estimado; sem NOPAT publicado, sai do EBIT; sem LPA, o árbitro
da contagem se abstém e vale a contagem do exercício.
