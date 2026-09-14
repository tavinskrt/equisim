---
numero: 81
titulo: A base de patrimônio da cascata é o PL da CVM, pela contagem de mercado
status: aceita
origem: parecer
data: 2026-09-14
afeta:
  - packages/equisim_core/lib/src/services/cvm/fundamentals_merge.dart
  - packages/equisim_core/test/fundamentals_merge_test.dart
substitui: []
---

## Contexto

A [decisão 78](078-a-mescla-nao-empresta-fluxo-de-outra-janela.md) achou um fato
do motor que nenhum registro dizia: **a base de patrimônio da cascata é sempre
`VPA × contagem do exercício`** (`FundamentalsSnapshot.equityBookValue`), dois
campos só de mercado. O `totalStockholderEquity` da CVM chegava à cascata e não
era lido em lugar nenhum do núcleo. Era o item A1.11 do plano.

**A medição mudou o que o item supunha.** Sobre os 4.443 exercícios anuais do
universo com as duas fontes, em 14/09/2026:

| a base de mercado bate com | a 0,5% | a 10% |
|---|---:|---:|
| **o PL consolidado da CVM** | **99,4%** | 99,5% |
| o PL do controlador | 60,6% | 83,3% |

A base de mercado **já era** o PL consolidado da CVM. E o lucro também é o
consolidado — o da fonte bate com a conta 3.11 da CVM em 349 de 352 últimos
exercícios —, de modo que base e fluxo estão na mesma convenção, e a ponte já
desconta os não controladores.

O que sobra são duas coisas. No último exercício, **5 de 361** tickers têm base
de mercado a mais de 2% do PL — HAPV3 com R$ 373 bi contra R$ 48 bi, erro de
escala da fonte. E o **ponto de junho** da série ancorada, que pela decisão 78
levava o PL de dezembro somado à dívida e ao caixa de junho.

## Decisão

O VPA do exercício mesclado passa a ser **derivado**: `PL da CVM ÷ contagem do
exercício do mercado`. O produto `VPA × contagem` devolve o PL da demonstração
exatamente, e a cascata não muda.

- A **contagem** continua sendo a do mercado: a da CVM não tem escala
  declarada ([decisão 70](070-a-contagem-de-acoes-da-cvm-nao-tem-escala.md)).
- O VPA **da CVM** continua sem entrar; o derivado registra procedência
  `derivado`.
- Sem PL na CVM, vale o VPA do mercado, como antes.
- PL negativo produz VPA negativo e base nula, a mesma semântica do VPA negativo
  da fonte — a elegibilidade continua lendo isso como insolvência.

## Efeito medido

Na mesma data, entre execuções sem deriva do dado de mercado:

| | anual | ancorada |
|---|---:|---:|
| 04/09/2026 — ativos que mudaram | **3** | — |
| 04/09/2024 — ativos que mudaram | **2** | **74** |
| correlação de postos anual × ancorada, 2024 | | 0,683 → **0,737** |

No caminho anual quase nada muda, como a medição previa. Na série ancorada, o
ponto de junho ganha o PL de junho, e a ancorada fica **mais parecida** com a
anual: parte da distância entre as duas era a base de dezembro.

**Um dos três de 2026 revelou defeito de outra ordem.** A MBRF3 foi de −27% a
−82%, e a razão não era o PL: os documentos da CVM sob MBRF3 eram da BRF, e a
série de mercado, da Marfrig. Ver a
[decisão 82](082-a-ponte-comeca-pelo-registro-oficial-da-b3.md).

## Consequências aceitas

O VPA deixa de ser o publicado pela fonte nos exercícios com CVM. Nada no
núcleo o lê fora do produto com a contagem, e a auditoria mostra os dois.
