---
numero: 85
titulo: A substituição das decisões 12, 16, 17 e 18 pela 23 passa a constar do registro
status: aceita
origem: conselheiro
data: 2026-09-14
afeta:
  - docs/decisoes/023-remocao-de-proventos.md
substitui:
  - 12
  - 16
  - 17
  - 18
---

## Contexto

A [decisão 23](023-remocao-de-proventos.md) removeu os proventos do domínio e
declarou, no próprio corpo, que quatro decisões da tabela congelada do
`PLANO_ARQUITETURA.md` deixavam de valer: a 12 (IR sobre JCP), a 16
(tratamento fiscal de `RENDIMENTO`), a 17 (regime tributário e métricas de
provento) e a 18 (se a taxa do provento é bruta ou líquida). Ela **não** as pôs
no campo `substitui`, e disse por quê: o gate local só reconhecia decisão com
arquivo em `docs/decisoes/`, e recusava a referência.

A [decisão 26](026-horizonte-de-convergencia-de-36-meses.md) tirou esse
impedimento: o gate passou a ler as decisões 0 a 18 da tabela congelada, e ela
mesma foi escrita para declarar a substituição que a decisão 25 não pôde. A 23
ficou para trás.

A lente `registro` apontou em 14/09/2026 que as quatro continuam, para quem lê
o registro pelos metadados, **vigentes** — em contradição com uma decisão
aceita.

## Decisão

Esta decisão declara, no campo que o registro lê, a substituição que a 23 fez
no corpo. Nada muda no código nem no método: o que as quatro decidiam já saiu
com a decisão 23 em 02/09/2026.

A 23 não é editada, porque decisão aceita não se edita. É o mesmo caminho da
decisão 26.
