# O instrumento da habilidade, pronto — itens C1c, C1d e C3

Medido em 15/09/2026 por `dart run tool/regressao_condicional.dart --trimestral`,
sobre `docs/validacao/backtest_trimestral.json` (de
`dart run tool/backtest_valuation.dart --montagem aplicativo --com-deslistadas
--trimestral --contrafactual-base`, 29 minutos). Dados em
[habilidade_trimestral.json](habilidade_trimestral.json). Decisões:
[96](../decisoes/096-o-t-da-habilidade-e-corrigido-pela-sobreposicao-contra-o-critico-dela.md),
[97](../decisoes/097-a-coorte-forma-preco-contagem-e-valor-de-mercado-na-base-da-data.md) e
[98](../decisoes/098-a-serie-ancorada-ordena-mais-sem-provar-e-fica-fora-do-padrao.md).

> **Isto não é o veredito do R3.** O usuário pediu, em 15/09/2026, para medir a
> habilidade do motor quando todas as fases estiverem completas, e o C1 foi para
> depois da Fase 3. O que sai aqui é o instrumento pronto — coortes trimestrais,
> a amostra com as deslistadas da ponte ampliada, a montagem na base da data e o
> erro-padrão das janelas sobrepostas — e a leitura dele sobre o motor de hoje,
> que a medição final vai refazer.

## 1. O que o instrumento passou a ser

| | rodada anterior (C1a, C1b) | agora |
|---|---|---|
| coortes | 8, em 30/09 de 2018 a 2025 | **31**, no fim de cada trimestre de 31/03/2018 a 30/09/2025 |
| série de exercícios | DFP | DFP, e a ancorada no trimestre ao lado (§4) |
| preço e valor de mercado | preço na base de ações de **hoje** × contagem do exercício | **na base da data**: fator medido no COTAHIST, contagem do FRE, valor de mercado espécie a espécie (C3) |
| deslistadas | 164 companhias da ponte | **189** (C1d) — com a BRF, a Petz, a Tupy, a Sequoia, a Azul |
| `t` do critério | o menor entre o comum e o de Newey-West | **corrigido pela sobreposição contra o crítico dela, e Newey-West acima de 2** |
| observações | 3.077, 951 avaliadas | **10.863, 3.672 avaliadas** |

**As deslistadas.** Em 31 coortes, 2.039 observações de papel da ponte
negociavam na data; 170 saíram por evento não localizado ou salto, e 54 porque o
papel já tinha entrado como listado na mesma coorte. Ficaram 1.864, de 103
companhias, com 449 avaliadas, de 33. Das companhias que o C1d trouxe, a Tupy
entra em 31 coortes e é avaliada em todas; a BRF, em 31, avaliada em 15; a Azul
em 29, a Petz em 21, a Sequoia em 19 — essas três sempre recusadas.

**As listadas.** 8.999 observações, 3.223 avaliadas; 1.077 saem por não ter
pregão no COTAHIST a até dez dias da data — antes, entravam com o último preço da
fonte, de qualquer idade.

## 2. O critério do `t`, e por que ele muda a leitura

Coortes de três em três meses medidas em 36 compartilham até 33 meses de retorno.
A decisão 96 corrige o `t` pela estrutura que isso impõe e o compara com o
crítico que a mesma estrutura dá ao nível de `t > 2`:

| amostra | coortes | sobreposição | crítico |
|---|---:|---:|---:|
| trimestral, 36 meses | 22 | 11 | **2,70** |
| trimestral, 12 meses | 30 | 3 | **2,24** |
| anual, 36 meses | 5 | 2 | **3,24** |
| anual, 12 meses | 7 | 0 | **2,52** |

O de 2,52 é o quantil da t de Student com seis graus de liberdade, 2,5165: a
simulação reproduz o caso sem sobreposição.

## 3. A leitura, sobre o motor de hoje

**36 meses, coortes trimestrais**

| | com deslistadas | sem deslistadas |
|---|---:|---:|
| observações | 2.569 | 2.185 |
| IC do potencial | 0,091 | 0,075 |
| `t` corrigido / crítico | 0,74 / 2,70 | 0,59 / 2,70 |
| IC do P/B | 0,181 | 0,174 |
| `t` corrigido / crítico · Newey-West | **2,93 / 2,70 · 7,09** | 2,39 / 2,70 · 5,57 |
| **coef. do potencial dado o P/B** | **0,030** | **0,014** |
| `t` comum · Newey-West · corrigido / crítico | 1,00 · 0,69 · **0,24 / 2,70** | 0,47 · 0,32 · 0,12 / 2,70 |
| IC incremental | −0,001 | −0,024 |
| coortes com coeficiente positivo | 11 de 22 | 12 de 22 |

**12 meses, coortes trimestrais**

| | com deslistadas | sem deslistadas |
|---|---:|---:|
| observações | 3.494 | 3.053 |
| IC do potencial | 0,052 (corrigido 0,97 / 2,24) | 0,051 |
| IC do P/B | 0,096 (corrigido 1,65 / 2,24) | 0,088 |
| **coef. do potencial dado o P/B** | **0,021** (corrigido 0,36 / 2,24) | 0,020 |

**Nas coortes de 30/09, o mesmo arquivo dá**, em 36 meses com as deslistadas, IC
do potencial de 0,097 e do P/B de 0,182, e o potencial dado o P/B de 0,028 (`t`
corrigido de 0,21 contra 3,24).

**A leitura é a da §0 do plano, com um sinal a menos.** O potencial ordena pouco
e não acrescenta ao P/B — condicionado a ele, o coeficiente é de 0,03 com metade
das coortes de cada lado. **O P/B é a única coisa que passa no critério**, e só
em 36 meses com as deslistadas.

## 4. A série ancorada contra a anual (C1c)

Nas mesmas observações, com o potencial diferente entre as duas em 68,5% delas:

| | 36 meses | 12 meses |
|---|---:|---:|
| IC da anual | 0,088 | 0,046 |
| IC da ancorada | 0,124 | 0,068 |
| diferença | +0,036 | +0,022 |
| `t` comum · Newey-West da diferença | 2,89 · 4,22 | 1,71 · 1,67 |
| **`t` corrigido / crítico** | **0,70 / 2,70** | **0,83 / 2,24** |
| anual dado o P/B | 0,019 | 0,013 |
| ancorada dado o P/B | 0,068 | 0,046 |

**Ordena mais, e não prova.** Pela regra fixada antes da medição, fica fora do
padrão (decisão 98). As regressões com as duas séries juntas não se sustentam:
os postos das duas são muito correlacionados.

## 5. O que a base da data mudou (C3)

Nas mesmas 480 observações das listadas em 30/09, a montagem da rodada anterior
e a da data, na mesma execução:

| 36 meses | base de hoje | base da data |
|---|---:|---:|
| IC do potencial | 0,179 | **0,085** |
| IC do P/B | 0,255 | **0,151** |
| coef. do potencial dado o P/B | 0,052 | 0,028 |

| 12 meses | base de hoje | base da data |
|---|---:|---:|
| IC do potencial | 0,114 | **0,044** |
| IC do P/B | 0,147 (`t` 4,03) | **0,069** (`t` 1,57) |
| coef. do potencial dado o P/B | 0,049 | 0,018 |

**O defeito inflava os dois sinais de valor, e o P/B mais.** Ele olhava para a
frente: a companhia que desdobrou depois da coorte — a que subiu — entrava com
valor de mercado pequeno demais e parecia barata, e a que agrupou, cara. Das 811
observações de 30/09 avaliadas nas duas montagens, o `1 + potencial` muda mais de
10% em 300, a mediana da mudança é de 2,8%, e a correlação de postos do P/B entre
as duas montagens é de 0,761. 26 observações passaram a ser avaliadas, e 7
deixaram de ser; o corte de liquidez mudou de lado em 71.

**O contrafactual é a montagem da rodada anterior**: das 818 avaliações que ela
produz nas duas execuções, 803 são idênticas, e 15 diferem menos de 0,2% pela
reingestão da CVM.

## 6. O que isto não diz

- **Não é a medição final.** O motor vai mudar na Fase 3 — B10, B9, B11, B16 —, e
  o C1 mede o que existir então.
- **Os 36 meses têm 22 coortes que valem por poucas**: o crítico de 2,70 é o preço
  disso, e é alto.
- **A contagem do FRE erra nas dez companhias em que diverge da B3**, e a razão de
  unidade inferida do valor de mercado falha em 79 de 220 observações de unit
  ([ponte_por_papel.md](ponte_por_papel.md)).
- **O motivo de saída das deslistadas** continua não levantado.
