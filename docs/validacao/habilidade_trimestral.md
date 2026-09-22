# O instrumento da habilidade, pronto — itens C1c, C1d e C3

> **A leitura mais recente é a §8**, de 21/09/2026, sobre o motor da Fase 3 e
> as coortes reexecutadas pelo item C5. As seções 1 a 7 registram as anteriores,
> e ficam porque a comparação entre instrumentos é parte do que este documento
> serve para mostrar.

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
| observações | 3.077, 951 avaliadas | **10.874, 3.673 avaliadas** |

**As deslistadas.** Em 31 coortes, 2.039 observações de papel da ponte
negociavam na data; 170 saíram por evento não localizado ou salto, e 54 porque o
papel já tinha entrado como listado na mesma coorte. Ficaram 1.864, de 103
companhias, com 449 avaliadas, de 33. Das companhias que o C1d trouxe, a Tupy
entra em 31 coortes e é avaliada em todas; a BRF, em 31, avaliada em 15; a Azul
em 29, a Petz em 21, a Sequoia em 19 — essas três sempre recusadas.

**As listadas.** 9.010 observações, 3.224 avaliadas; 1.077 saem por não ter
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

## 9. Sobre o motor que fecha a Fase 3 — remedido em 22/09/2026

**É a leitura sobre o motor com a Fase 3 inteira fechada**: além do da §8, as
versões antigas dos documentos da CVM (item B8, decisão 128), o juro da rota
derivada seguindo a curva (item B24, decisão 127) e a fronteira do dinheiro
arredondando o decimal escrito (decisão 125). Mesmas 10.919 observações, 31
coortes.

| 36 meses, trimestral, com deslistadas (n = 2.164) | média | `t` corrigido / crítico | Newey-West | passa |
|---|---:|---:|---:|---|
| **potencial dado o B/M (critério do R3)** | **0,028** | **0,15 / 2,70** | 0,40 | não |
| IC do potencial | 0,088 | 0,53 / 2,70 | 1,23 | não |
| IC do book-to-market | 0,160 | 2,07 / 2,70 | 4,36 | não |
| IC do lucro sobre o preço | 0,123 | 1,04 / 2,70 | 2,82 | não |
| IC do composto | 0,146 | 1,19 / 2,70 | 2,86 | não |
| IC do múltiplo de pares | 0,083 | 1,24 / 2,70 | 3,49 | não |

**Nada muda de veredito, e quase nada de número.** O potencial condicionado ao
B/M vai de 0,027 a 0,028; o book-to-market sobe de `t` corrigido 1,98 para 2,07,
e continua abaixo do crítico. As versões antigas mexem em 2,8% das observações
avaliadas, e o juro pela curva move o preço justo em −0,65% na mediana — os dois
defeitos eram reais, e nenhum deles era o que separava o motor da habilidade.
**Líquido de custo de transação** (item C4), a leitura é a mesma
([custos_transacao.md](custos_transacao.md)).

## 8. Sobre o motor da Fase 3 — remedido em 21/09/2026, com a base restaurada

**É a primeira leitura sobre o motor que a Fase 3 deixou.** Entre 16/09 e hoje o
motor mudou doze vezes — as decisões 104 a 121 —, e as coortes continuavam sendo
as da decisão 102 porque o `data/` não existia nesta máquina. O item **C5**
restaurou a base bruta — CVM, COTAHIST, Tesouro, FRE, registro e complemento da
B3 — e reexecutou o backtest: **10.919 observações, 31 coortes**.

| 36 meses, trimestral, com as deslistadas | 16/09 (§7) | **21/09** |
|---|---|---|
| observações da regressão | 2.452 | **2.165** |
| coortes | 22 | 22 |
| IC do potencial · `t` corrigido | 0,078 · 0,61 | **0,089 · 0,53** |
| IC do book-to-market · `t` corrigido | 0,186 · 2,52 | **0,157 · 1,98** |
| IC do lucro sobre preço · `t` corrigido | — | 0,124 · 1,02 |
| IC do composto · `t` corrigido | 0,173 · 1,57 | **0,147 · 1,17** |
| **potencial dado o B/M · `t` corrigido** | 0,010 · 0,08 | **0,027 · 0,15** |
| ortogonalizado ao P/B (item B2) | +0,016 | **+0,025** |

Crítico de 2,70. **Nenhuma ordenação passa, e agora nem de perto**: o
book-to-market, que estava a 2,52 do crítico de 2,70, caiu para **1,98**.

**O que isso é, e o que não é.** Não é o motor piorando: o potencial **subiu**,
de 0,078 para 0,089, e o condicionado ao B/M também, de 0,010 para 0,027. O que
caiu foi o **fator contra o qual ele é medido** — e a queda do book-to-market
vem da amostra, não da cascata: são 287 observações a menos, com a base bruta
reconstruída de zero e o COTAHIST rebaixado do dia.

**A regra da [decisão 103](../decisoes/103-o-premio-do-retorno-esperado-sai-da-ordenacao-comprovada-e-hoje-nao-ha.md)
devolve o mesmo:** prêmio nenhum. E ela agora foi aplicada a **cinco**
candidatas, com a quarta e a quinta entrando nesta rodada
([multiplos_ordenacao.md](multiplos_ordenacao.md), item B22).

**A faixa calibrada, medida na mesma execução, passa** — 90% nominal cobrindo
88,1% em 12 meses e 89,3% em 36, desvio máximo de 2,6 p.p. contra o limite de 5
([cobertura_banda.md](cobertura_banda.md)).

## 7. Sobre o motor da decisão 102 — remedido em 16/09/2026

A decisão 102 tirou a migração de via: a via da firma avalia o capital próprio pelo
fluxo do acionista derivado, e nenhuma avaliação passa mais para a via do
acionista pela conta. O preço justo de toda a via da firma mudou, e o backtest foi
reexecutado. **O JSON desta medição é o do motor novo; as §§1 a 5 registram o de
15/09/2026.** A mesma execução mede as três ordenações lado a lado, que é o item B1
([ordenacao_lado_a_lado.md](ordenacao_lado_a_lado.md)).

| 36 meses, trimestral, com as deslistadas | 15/09 (§3) | **16/09** |
|---|---|---|
| observações avaliadas no backtest | 3.673 | **3.470** |
| observações da regressão | 2.570 | **2.452** |
| IC do potencial · `t` corrigido | 0,091 · 0,74 | **0,078 · 0,61** |
| IC do book-to-market · `t` corrigido | 0,181 · 2,92 | **0,186 · 2,52** |
| IC do composto · `t` corrigido | — | **0,173 · 1,57** |
| **potencial dado o B/M · `t` corrigido** | 0,030 · 0,24 | **0,010 · 0,08** |

Crítico de 2,70 nas duas. **O book-to-market deixa de passar** no critério da
decisão 96, e nenhuma das três ordenações passa — o que, pela regra fixada antes
de medir, tira o prêmio do retorno esperado ([decisão 103](../decisoes/103-o-premio-do-retorno-esperado-sai-da-ordenacao-comprovada-e-hoje-nao-ha.md)).

**A série ancorada contra a anual** (§4), sobre 2.359 observações: IC de 0,059
contra 0,079, diferença de +0,020 com `t` corrigido de 0,36. A decisão 98 continua
valendo — ordena mais, e não prova.

**O contrafactual da base** (§5), nas coortes de 30/09 das listadas, 461
observações: o IC do book-to-market vai de 0,253 na base de hoje a 0,161 na da
data, e o do potencial, de 0,204 a 0,114. A correção do C3 continua sendo a maior
mudança do instrumento.
