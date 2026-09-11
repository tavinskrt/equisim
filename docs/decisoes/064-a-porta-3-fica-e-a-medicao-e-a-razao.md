---
numero: 64
titulo: A Porta 3 fica, e a medição é a razão
status: aceita
origem: parecer
data: 2026-09-11
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - docs/validacao/porta3.md
substitui: []
---

## Contexto

A lente `metodo` propôs, como achado estrutural, remover a migração por
`fluxoSustentado` em `ValuationCascade._route`: empresa cujo lucro operacional
não se sustenta passaria a **falhar** em vez de ser roteada para a via do
acionista. O argumento é que a via do acionista seria leniente e lavaria um
ativo ruim numa avaliação. A proposta reverteria a
[decisão 38](038-transicao-continua-entre-as-vias.md), e veio sem medição.

## Decisão

A migração fica. A proposta é recusada **por medição**, não por apego ao
registro.

Sobre 8 coortes anuais *point-in-time* (2018–2025) e 846 avaliações, a Porta 3
tem o **maior** poder de ordenação dos três roteamentos:

| grupo | N | IC 12m | IC 36m |
|---|---:|---:|---:|
| via da firma | 716 | +0,0417 | +0,1279 |
| Porta 1 (banco) | 95 | +0,1127 | +0,1089 |
| **Porta 3** | **35** | **+0,4197** | **+0,3815** |

Recusar esses casos **piora** a ordenação do universo: o IC de 12 meses cai de
+0,0845 para +0,0650 e o de 36, de +0,1486 para +0,1343.

E onde a proposta temia o pior — o insustentável anunciado como oportunidade —,
das 7 avaliações de Porta 3 com potencial acima de +50% apenas **1** terminou
negativa em 36 meses; na via da firma, 31 de 66.

## Consequências aceitas

**A amostra é pequena, e o registro não a infla.** São 35 avaliações e 14
tickers, com `n = 25` no horizonte de 36 meses. A permutação bicaudal dá
**p = 0,0618** em 36 meses e **p = 0,0136** em 12. As varreduras de robustez —
deixa-um-ticker-de-fora e deixa-uma-coorte-de-fora — mantêm o IC36 entre
+0,2707 e +0,4964, de modo que nem um papel nem um ano sustentam o resultado
sozinhos.

O `+0,3815` **não** deve ser citado como estimativa do IC da Porta 3. Ele
sustenta uma afirmação mais modesta e suficiente: a Porta 3 não é a fatia ruim
que a proposta supunha, e removê-la custaria sinal.

A alternativa descartada — barrar cedo e ficar em silêncio — trocaria cobertura
por uma limpeza que a medição não pede. Cobertura não é critério, como a
decisão 39 já dizia; mas recusa que piora a ordenação também não é virtude.
