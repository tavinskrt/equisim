---
numero: 69
titulo: A mescla de fontes carrega a procedência de cada campo
status: aceita
origem: parecer
data: 2026-09-11
afeta:
  - packages/equisim_core/lib/src/services/cvm/fundamentals_merge.dart
  - packages/equisim_core/test/fundamentals_merge_test.dart
  - tool/cvm_ligar.dart
  - docs/validacao/cvm_ligacao.md
substitui: []
---

## Contexto

Com a ingestão da CVM (A1.1 a A1.6), o projeto passa a ter **duas fontes** para
o mesmo exercício, e nenhuma basta:

- A **CVM** publica a demonstração com precisão e profundidade que o agregador
  não tem — lucro de banco, ativo total, data de recebimento, ação em
  tesouraria, dívida e imobilizado por conta padronizada.
- A **fonte de mercado** publica o que a CVM não publica: preço, valor de
  mercado e a contagem corrente de papéis, que é o que forma o preço com que o
  valor justo é comparado.

Escolher uma fonte por exercício descartaria o que a outra sabe.

## Decisão

O exercício é montado **campo a campo**, e cada campo carrega de onde veio.

`FundamentalsMerge.merge` prefere a CVM onde ela tem o valor, deixa o mercado
preencher o resto, e devolve um `FundamentalsProvenance` com a origem de cada
campo — `cvm`, `mercado`, `derivado` ou `ausente`.

Duas exceções nomeadas. `somenteDeMercado` — `marketCap`, `sharesOutstanding`
e `enterpriseToEbitda` — **nunca** vem da CVM, porque descreve o hoje do papel
e não o exercício. A `receiptDate` é o oposto: é da CVM por natureza, porque é
ela que registra o protocolo.

## Consequências aceitas

**A procedência é obrigatória, e não ornamento.** Um número mesclado sem origem
é pior que um número de fonte única: quando ele diverge do esperado, não há
como saber qual fonte revisar. Foi por isso que o D2 do plano acompanha o eixo
A em vez de vir depois dele.

**A mescla muda pouco, e muda o certo.** Sobre os 127 avaliados, a mediana do
`|Δ potencial|` é de **0,0%** e apenas **7 se movem mais de 10 p.p.** — e cinco
deles são **bancos** (BMGB4, BPAC11, ITUB4, ITUB3, BRSR6), que passaram a ter
lucro líquido publicado. É exatamente o que a §2.12 previa, e nenhuma cobertura
foi perdida: 127 avaliados antes, 127 depois.

**Onde as duas discordam, a CVM vence por regra, e não por medição.** A regra é
defensável — a CVM é fonte primária e a outra é agregador que a lê — mas é
regra, e a divergência campo a campo não foi medida.
