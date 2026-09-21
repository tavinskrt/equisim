---
numero: 108
titulo: A recusa por liquidez fica, e o beta corrigido fecha só um terço da distância que a justifica
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B12, B14 e B15.
afeta:
  - tool/beta_liquidez.dart
  - tool/validation/congelado.dart
  - docs/validacao/beta_liquidez.md
  - docs/validacao/beta_sincronia.md
substitui: []
---

## Contexto

A [decisão 95](095-a-recusa-por-liquidez-fica-pelo-nivel-e-nao-pela-ordenacao.md)
deixou a recusa por liquidez de pé por **uma** razão. Soltos do corte, os
recusados **ordenam** o retorno — o potencial dado o book-to-market tem IC de
0,116 em 12 meses —, mas o **nível** do preço justo deles sai 27 p.p. acima do
das avaliadas. A explicação proposta foi o beta: papel com pouco negócio responde
ao mercado com atraso, a covariância contemporânea perde a parte atrasada, o beta
sai baixo, o custo de capital sai baixo e o preço justo sai alto.

Se for isso, um beta corrigido tira a razão da recusa, e a Porta 0 tem de decidir
de novo. É o item B14.

[`beta_sincronia.md`](../validacao/beta_sincronia.md) mediu a correção de Dimson
em 11/09/2026 **nos avaliados**, e lá ela não existe: a Porta 0 removeu quem
sofreria. Aquele documento fecha dizendo que, se o corte for afrouxado, o item
volta com o tamanho que o universo cru mostra.

## O que foi medido

Sobre a entrada congelada do gabarito, em 21/09/2026, com 185 recusados **só por
liquidez** e 102 avaliados ([beta_liquidez.md](../validacao/beta_liquidez.md)):

**O viés existe, e cresce com a iliquidez.** Dimson com uma defasagem sobre o
beta diário dá mediana de 1,052 nos soltos, contra 0,988 nos avaliados, e o
efeito se concentra em quem negocia pouco:

| soltos, por frequência | n | beta diário | Dimson(1) | Dimson(5) |
|---|---:|---:|---:|---:|
| negocia todo dia (≥240/ano) | 100 | 0,801 | 0,858 | 0,843 |
| intermitente (120 a 240) | 48 | 0,308 | 0,330 | 0,394 |
| raro (< 120/ano) | 37 | **0,134** | 0,294 | **0,367** |

**E não chega perto.** Com o mesmo encolhimento que a produção aplica
(decisão 40), o beta dos soltos vai de 0,527 a 0,613 com uma defasagem e a 0,723
com cinco. O dos avaliados é **0,955**.

**A distância no nível fecha um terço:**

| | potencial mediano |
|---|---:|
| avaliados | **−48,2%** |
| soltos, beta diário | −30,4% |
| soltos, Dimson(1) encolhido | −31,8% |
| soltos, Dimson(5) encolhido | **−36,9%** |

Dos 17,8 p.p. de distância, Dimson com cinco defasagens fecha 6,5. Sobram 11,3.

**E a correção custa onde não há o que corrigir.** O erro-padrão do beta triplica
nos dois grupos — 0,0844 → 0,2812 nos soltos, 0,0491 → 0,1637 nos avaliados. Como
o encolhimento pondera por `1/SE²`, adotar Dimson no universo transferiria peso
do ativo para o prior setorial justamente onde o beta diário está certo.

## Decisão

**A recusa por liquidez fica**, e agora por duas razões medidas em vez de uma
suposta:

1. **A distância de nível não é o beta.** Dimson explica e fecha um terço dela;
   os outros dois terços continuam sem explicação, e o preço justo dos soltos
   continua 11 p.p. acima do das avaliadas.
2. **Corrigir o beta de todo mundo custa precisão onde não há viés.** É a mesma
   conclusão de `beta_sincronia.md`, agora com o grupo que sofre o viés medido ao
   lado do que não sofre.

**O motor não muda.** O beta continua saindo da regressão diária contemporânea,
encolhida em direção ao prior transversal.

## Consequências aceitas

**Fica um grupo sem explicação, e ele é nomeado.** Os soltos que negociam todo
pregão — 100 dos 185 — têm beta diário de 0,801, quase o dos avaliados, e
potencial de −33,8%: neles a não sincronia não tem o que explicar, e a distância
de nível permanece inteira. O que a separa das avaliadas é o giro de R$ 46 mil
por dia contra R$ 50 milhões, e não a estimação do risco.

**O grupo intermitente é o pior dos dois mundos:** beta de 0,308 e potencial
mediano de −8,8%, o mais inflado dos três. É onde a recusa protege mais.

**A correção de Dimson fica no instrumento, e não no motor.** `beta_liquidez.dart`
a implementa com uma e com cinco defasagens; se o corte de liquidez for
afrouxado um dia, a medição já está escrita.

**O número da decisão 95 era de coorte, e este é de seção transversal.** Lá a
distância era de 27 p.p. sobre 31 coortes trimestrais; aqui é de 17,8 p.p. sobre
o universo de 14/09/2026, com o motor das decisões 102 a 106. A direção e a
ordem de grandeza se confirmam; o número exato depende da montagem, e as duas
estão declaradas.
