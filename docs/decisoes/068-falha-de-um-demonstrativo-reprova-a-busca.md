---
numero: 68
titulo: Falha de um demonstrativo reprova a busca inteira
status: aceita
origem: parecer
data: 2026-09-11
afeta:
  - lib/data/datasources/remote/brapi_datasource.dart
  - test/data/brapi_datasource_test.dart
substitui: []
---

## Contexto

`BrapiDatasource.fundamentalsHistory` busca quatro endpoints — estatísticas,
DRE, balanço e fluxo de caixa — e os funde pela data de encerramento. Diante de
erro em um deles, seguia com `continue` e devolvia `Ok` desde que **algum**
tivesse respondido.

A lente `dados` apontou como achado estrutural, e a conferência mostrou que a
consequência é pior do que o achado dizia:

1. Uma falha na DRE produz série com **balanço preenchido e resultado
   ausente** — exatamente a forma que a
   [decisão 52](052-ausencia-nao-e-zero.md) trata como "ausência não é zero".
2. O repositório **grava o resultado no cache** por `upsertFundamentals`, e o
   cache é preferido nas leituras seguintes. A corrupção sobrevivia à falha de
   rede que a causou.
3. O filtro de `hasIncomeStatement` remove esses exercícios, de modo que a
   falha aparecia como **histórico curto** — e um ativo era recusado por
   "poucos exercícios" quando o que houve foi um 503.

## Decisão

Erro em qualquer um dos quatro endpoints devolve `Err`.

A distinção que torna isso seguro: `getJson` devolve `Err` para status de erro,
resposta vazia, falha de transporte e JSON inválido — todos "deu errado".
Companhia que legitimamente não publica um demonstrativo responde **200 com
lista vazia**, e essa continua passando. A recusa passou a ser por `merged`
vazio, e não por "nenhum endpoint respondeu".

## Consequências aceitas

**Um ativo deixa de ser avaliado quando a rede falha em qualquer um dos
quatro**, onde antes era avaliado com dado incompleto. É a troca certa, e ela
não custa cobertura de verdade: o repositório já recua para o cache diante de
`Err`, e ali a série está completa.

O que se perde é o caso em que a fonte está permanentemente sem um dos
demonstrativos para um ativo específico **e** responde com erro em vez de lista
vazia. Nenhum caso assim foi observado.

**Fica registrado o que foi recusado da mesma lente.** Ela propôs também
inverter a ordem dos interceptors, para que a espera da repetição ficasse fora
do slot do limitador. Conferido: `ThrottleInterceptor` libera o slot no
`onError` e está registrado **antes** do `RetryInterceptor`, de modo que a
liberação já acontece primeiro. A inversão proposta **criaria** o defeito que
ela descreve.
