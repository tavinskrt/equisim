# O beta do papel pouco negociado — item B14

> **Medido em 21/09/2026**, sobre a entrada congelada do gabarito da cascata.
>
> ```bash
> dart run tool/gabarito_cascata.dart     # congela a entrada
> dart run tool/beta_liquidez.dart        # grava beta_liquidez.json
> ```
>
> A montagem foi **conferida contra o gabarito** ativo a ativo na montagem do
> aplicativo: zero divergências. Sem essa conferência os números abaixo
> descreveriam outro motor.

## 0. A pergunta

A [decisão 95](../decisoes/095-a-recusa-por-liquidez-fica-pelo-nivel-e-nao-pela-ordenacao.md)
deixou a recusa por liquidez de pé por **uma** razão. Soltos do corte, os
recusados ordenam o retorno; o que não presta é o **nível** — o preço justo deles
sai 27 p.p. acima do das avaliadas. A explicação proposta foi o beta: papel com
pouco negócio responde ao mercado com atraso, a covariância contemporânea perde
a parte atrasada, o beta sai baixo, o custo de capital sai baixo e o preço justo
sai alto.

**Se for isso, um beta corrigido tira a razão da recusa.**

[`beta_sincronia.md`](beta_sincronia.md) mediu a correção de Dimson nos
**avaliados** e não a encontrou — a Porta 0 já tinha removido quem sofreria —, e
fechou dizendo: *se o corte de liquidez for afrouxado, este item volta, e volta
com o tamanho que o universo cru mostra.* Aqui ele volta.

## 1. Os dois grupos

| | n | pregões/ano (mediana) | pregões/ano (p10) | giro diário mediano |
|---|---:|---:|---:|---:|
| recusados só por liquidez | 185 | 244 | **63** | **R$ 46 mil** |
| avaliados | 102 | 250 | 250 | R$ 50,5 milhões |

**Os soltos não são um grupo só.** Metade deles negocia todo pregão; o que os
separa das avaliadas ali é o giro, não a frequência.

## 2. O viés existe, e cresce com a iliquidez

Dimson soma as inclinações contra o mercado defasado, contemporâneo e adiantado.
Com uma defasagem — a forma clássica — e com cinco, porque papel que negocia 63
vezes por ano não responde ao mercado no dia seguinte:

| Dimson ÷ diário | p10 | mediana | p90 | acima do diário |
|---|---:|---:|---:|---:|
| soltos, 1 defasagem | 0,536 | **1,052** | 1,825 | 116 de 185 |
| soltos, 5 defasagens | −0,146 | **1,098** | 2,389 | 109 de 185 |
| avaliados, 1 defasagem | 0,907 | 0,988 | 1,119 | 47 de 102 |
| avaliados, 5 defasagens | 0,713 | 1,048 | 1,218 | 60 de 102 |

Por frequência de negócio, dentro dos soltos:

| | n | beta diário | Dimson(1) | Dimson(5) | potencial mediano |
|---|---:|---:|---:|---:|---:|
| negocia todo dia (≥240/ano) | 100 | 0,801 | 0,858 | 0,843 | −33,8% |
| intermitente (120 a 240) | 48 | 0,308 | 0,330 | 0,394 | **−8,8%** |
| raro (< 120/ano) | 37 | **0,134** | 0,294 | **0,367** | −34,5% |

**No grupo raro o beta mais que dobra com a correção.** É o viés previsto pela
teoria, com o sinal previsto, no grupo previsto.

## 3. E não chega perto

O que chega ao preço é o beta **encolhido** em direção ao prior transversal
([decisão 40](../decisoes/040-beta-encolhido-por-precisao.md)) — comparar o
encolhido de produção com um Dimson cru premiaria o estimador mais ruidoso. Com
o mesmo encolhimento nos dois, e o erro-padrão de cada um:

| beta encolhido | produção | diário | Dimson(1) | Dimson(5) |
|---|---:|---:|---:|---:|
| soltos | 0,527 | 0,527 | 0,613 | **0,723** |
| avaliados | 0,955 | 0,958 | 0,943 | 0,933 |

E o nível do potencial, que é a grandeza da decisão 95:

| | potencial mediano |
|---|---:|
| avaliados | **−48,2%** |
| soltos, beta diário | −30,4% |
| soltos, Dimson(1) encolhido | −31,8% |
| soltos, Dimson(5) encolhido | **−36,9%** |

**Dos 17,8 p.p. de distância, Dimson com cinco defasagens fecha 6,5.** Sobram
11,3, e eles não são o beta.

## 4. E a correção custa onde não há o que corrigir

| erro-padrão do beta (mediana) | diário | Dimson(1) | Dimson(5) |
|---|---:|---:|---:|
| soltos | 0,0844 | 0,1463 | **0,2812** |
| avaliados | 0,0491 | 0,0851 | **0,1637** |

Triplica nos dois grupos. Como o encolhimento pondera por `1/SE²`, adotar Dimson
no universo transferiria peso do ativo para o prior setorial **justamente onde o
beta diário está certo** — é a mesma conclusão de `beta_sincronia.md`, agora com
o grupo que sofre o viés medido ao lado do que não sofre.

## 5. O que se decidiu

[Decisão 108](../decisoes/108-a-recusa-por-liquidez-fica-e-o-beta-corrigido-fecha-um-terco-da-distancia.md):
**a recusa por liquidez fica, e o motor não muda.** Agora por duas razões
medidas em vez de uma suposta — a distância de nível não é o beta, e corrigir o
beta de todo mundo custa precisão onde não há viés.

## 6. O que isto não diz

- **Não explica os dois terços que sobram.** O que separa os soltos das
  avaliadas no nível do preço justo continua sem causa identificada — e o grupo
  que negocia todo pregão, com beta quase igual ao das avaliadas, mostra que ela
  não é de estimação de risco.
- **O número da decisão 95 era de coorte.** Lá a distância era de 27 p.p. sobre
  31 coortes trimestrais; aqui é de 17,8 p.p. sobre o universo de 14/09/2026,
  com o motor das decisões 102 a 106. Direção e ordem de grandeza se confirmam;
  o número exato depende da montagem.
- **O erro-padrão de Dimson é cota inferior**: ele soma as variâncias dos
  coeficientes e ignora a covariância entre eles. Serve para ordem de grandeza,
  que é o uso aqui, e subdeclara o custo em vez de exagerá-lo.
