---
numero: 75
titulo: Eventos de ações se inferem do COTAHIST com recusa, e o que o preço não separa fica declarado
status: aceita
origem: parecer
data: 2026-09-14
afeta:
  - packages/equisim_core/lib/src/services/b3/corporate_events.dart
  - packages/equisim_core/test/corporate_events_test.dart
  - tool/b3_cotahist.dart
  - docs/validacao/b3_cotahist.md
substitui: []
---

## Contexto

O item A3 do plano pede ações societárias e preço de companhias deslistadas. A
fonte é o **COTAHIST** da B3: um arquivo por ano, com o fechamento **bruto** de
todo papel negociado — inclusive os que depois deixaram de existir — e o
`DISMES`, número de distribuição, que incrementa a cada evento.

Conferido sobre o BBAS3 de 2024: o fechamento cai de R$ 56,46 para R$ 27,91 em
16/04/2024 (razão 0,494), na bonificação de 100%, e o `DISMES` passa de 321 para
322. Mas o mesmo papel tem **nove** trocas de `DISMES` no ano, e oito são
proventos, com quedas de 1% a 4%. O número marca que houve evento, não qual.

## Decisão

`CorporateEvents.detect` infere evento de ações numa troca de `DISMES` quando
a razão entre os fechamentos está **longe de 1 e perto de uma fração simples**
— ½, ⅓, 2, 10 e afins. Três recusas:

1. **Pregões distantes** — mais de 7 dias entre os dois — não se comparam: papel
   suspenso volta com `DISMES` novo e preço diferente sem que o salto seja
   evento.
2. **Folga larga para desdobramento e grupamento, apertada para bonificação**,
   com "perto de 1" medido em escala logarítmica, onde ½ e 2 são simétricos.
3. **Bonificação de até 20% não é detectada**, e a régua não finge que é: uma
   bonificação de 10% dá razão 0,909 e uma queda de 8,5% em data ex dá 0,915 — a
   0,6% uma da outra. O teste que tentava separá-las falhou, e com razão.

`CorporateEvents.adjust` divide o passado pelo fator de cada evento, levando a
série à base de hoje. Provento não entra — o retorno é de preço (decisão 23).

## Consequências aceitas

**A conferência contra o `close` ajustado da fonte de mercado**, sobre 2019 e
2024, 343 papéis do universo: **99,96% dos retornos diários batem a 1%** —
118.826 de 118.871.

A primeira versão da conferência media **nível**, e deu 68%. Não era o
detector: a fonte ajusta por todo evento até hoje, e com dois anos do COTAHIST
um evento de 2021 ou de 2025 vira deslocamento constante — SBSP3, POMO3 e RENT3
discordavam em 499 de 499 pregões com zero eventos. No retorno o deslocamento
some.

**Os 45 dias discordantes têm três causas, e todas ficam registradas:**

- **Evento grande com o mercado andando junto.** AERI3 agrupou 15:1 e subiu
  22,8% no mesmo pregão — razão 18,4, fora da folga. AZEV3 agrupou 4:1 com
  +17,9%. E há evento **sem troca de `DISMES`**: AFLT3, razão exatamente 2,0.
- **Bonificação pequena, não detectada por construção**: GGBR3/4 (20%),
  LREN3 e CRPG5/6 (10%).
- **A fonte de mercado ajustando onde o bruto não mostra evento**, ou em data
  diferente: AHEB3, IFCM3, MAPT3, CGAS5, EUCA3.

**O teto é da inferência por preço.** Os dois primeiros grupos só fecham com o
registro oficial de eventos da B3, que declara o fator em vez de deixá-lo ser
adivinhado — item A3.1.

**O que esta decisão não entrega do A3**: o histórico completo do COTAHIST, a
ponte das companhias deslistadas até o CNPJ da CVM, e o uso dos eventos na
contagem de ações da ponte por papel (§1.7). Ficam como A3.2 e A3.3.
